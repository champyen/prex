const ffi = @import("fs_ffi.zig");
const c = ffi.raw;

extern fn get_mount_list() callconv(.c) *c.struct_list;
extern fn get_mount_lock() callconv(.c) *c.mutex_t;
extern fn get_vfssw() callconv(.c) [*c]const c.struct_vfssw;

extern fn namei(path: [*c]const u8, vpp: [*c]c.vnode_t) callconv(.c) c_int;
extern fn vget(mp: c.mount_t, path: [*c]const u8) callconv(.c) c.vnode_t;
extern fn vput(vp: c.vnode_t) callconv(.c) void;
extern fn vn_unlock(vp: c.vnode_t) callconv(.c) void;
extern fn vrele(vp: c.vnode_t) callconv(.c) void;
extern fn vflush(mp: c.mount_t) callconv(.c) void;
extern fn binval(dev: c.dev_t) callconv(.c) void;
extern fn bio_sync() callconv(.c) void;

const has_threads = @hasDecl(c, "CONFIG_FS_THREADS") and c.CONFIG_FS_THREADS > 1;

fn mountLock() void {
    if (has_threads) {
        _ = c.mutex_lock(get_mount_lock());
    }
}

fn mountUnlock() void {
    if (has_threads) {
        _ = c.mutex_unlock(get_mount_lock());
    }
}

fn fs_getfs(name: [*c]const u8) ?*const c.struct_vfssw {
    var fs: [*]const c.struct_vfssw = @ptrCast(get_vfssw());
    while (fs[0].vs_name != null) : (fs += 1) {
        if (ffi.prog.string.strncmp(name, fs[0].vs_name, c.FSMAXNAMES) == 0) {
            return &fs[0];
        }
    }
    return null;
}

fn VFS_MOUNT(mp: c.mount_t, dev: [*c]u8, flags: c_int, data: ?*anyopaque) c_int {
    if (mp) |m| {
        const m_ptr: *c.struct_mount = @ptrCast(m);
        if (m_ptr.m_op) |op| {
            const op_ptr: *c.struct_vfsops = @ptrCast(op);
            if (op_ptr.vfs_mount) |mount_fn| {
                return mount_fn(mp, dev, flags, data);
            }
        }
    }
    return ffi.prog.errno.ENOSYS;
}

fn VFS_UNMOUNT(mp: c.mount_t) c_int {
    if (mp) |m| {
        const m_ptr: *c.struct_mount = @ptrCast(m);
        if (m_ptr.m_op) |op| {
            const op_ptr: *c.struct_vfsops = @ptrCast(op);
            if (op_ptr.vfs_unmount) |unmount_fn| {
                return unmount_fn(mp);
            }
        }
    }
    return ffi.prog.errno.ENOSYS;
}

fn VFS_SYNC(mp: c.mount_t) c_int {
    if (mp) |m| {
        const m_ptr: *c.struct_mount = @ptrCast(m);
        if (m_ptr.m_op) |op| {
            const op_ptr: *c.struct_vfsops = @ptrCast(op);
            if (op_ptr.vfs_sync) |sync_fn| {
                return sync_fn(mp);
            }
        }
    }
    return ffi.prog.errno.ENOSYS;
}

pub export fn sys_mount(dev: [*c]u8, dir: [*c]u8, fsname: [*c]u8, flags: c_int, data: ?*anyopaque) callconv(.c) c_int {
    if (dir == null or dir[0] == 0) return ffi.prog.errno.ENOENT;

    const fs = fs_getfs(fsname) orelse return ffi.prog.errno.ENODEV;

    var device: c.device_t = 0;
    if (dev != null and dev[0] != 0) {
        if (ffi.prog.string.strncmp(dev, "/dev/", 5) != 0) {
            return ffi.prog.errno.ENOTBLK;
        }
        const dev_name = dev + 5;
        const err = c.device_open(dev_name, c.DO_RDWR, &device);
        if (err != 0) return err;
    }

    mountLock();

    const head = get_mount_list();
    const list_head: *ffi.List = @ptrCast(head);
    var n = list_head.next;
    while (n != list_head) {
        const next_node = n.?.next;
        const mp = n.?.entry(c.struct_mount, "m_link");
        const path_ptr = @as([*c]const u8, @ptrCast(&mp.m_path));
        if (ffi.prog.string.strcmp(path_ptr, dir) == 0 or (device != 0 and mp.m_dev == @as(c.dev_t, @intCast(device)))) {
            mountUnlock();
            if (device != 0) _ = c.device_close(device);
            return ffi.prog.errno.EBUSY;
        }
        n = next_node;
    }

    const mem = ffi.prog.stdlib.malloc(@sizeOf(c.struct_mount)) orelse {
        mountUnlock();
        if (device != 0) _ = c.device_close(device);
        return ffi.prog.errno.ENOMEM;
    };
    const mp: *c.struct_mount = @ptrCast(@alignCast(mem));
    mp.m_count = 0;
    mp.m_op = fs.vs_op;
    mp.m_flags = flags;
    mp.m_dev = @intCast(device);
    _ = ffi.prog.string.strlcpy(@ptrCast(&mp.m_path), dir, @sizeOf(@TypeOf(mp.m_path)));

    var vp_covered: c.vnode_t = null;
    if (dir[0] == '/' and dir[1] == 0) {
        vp_covered = null;
    } else {
        const err = namei(dir, &vp_covered);
        if (err != 0) {
            mountUnlock();
            ffi.prog.stdlib.free(mp);
            if (device != 0) _ = c.device_close(device);
            return ffi.prog.errno.ENOENT;
        }
        const vp_cov_node: *c.struct_vnode = @ptrCast(vp_covered.?);
        if (vp_cov_node.v_type != c.VDIR) {
            mountUnlock();
            vput(vp_covered);
            ffi.prog.stdlib.free(mp);
            if (device != 0) _ = c.device_close(device);
            return ffi.prog.errno.ENOTDIR;
        }
    }
    mp.m_covered = vp_covered;

    const vp = vget(mp, "/");
    if (vp == null) {
        mountUnlock();
        if (vp_covered != null) vput(vp_covered);
        ffi.prog.stdlib.free(mp);
        if (device != 0) _ = c.device_close(device);
        return ffi.prog.errno.ENOMEM;
    }
    const vp_node: *c.struct_vnode = @ptrCast(vp.?);
    vp_node.v_type = c.VDIR;
    vp_node.v_flags = c.VROOT;
    vp_node.v_mode = c.S_IFDIR | c.S_IRUSR | c.S_IWUSR | c.S_IXUSR;
    mp.m_root = vp;

    const err = VFS_MOUNT(mp, dev, flags, data);
    if (err != 0) {
        mountUnlock();
        vput(vp);
        if (vp_covered != null) vput(vp_covered);
        ffi.prog.stdlib.free(mp);
        if (device != 0) _ = c.device_close(device);
        return err;
    }

    if ((mp.m_flags & c.MNT_RDONLY) != 0) {
        vp_node.v_mode &= ~@as(@TypeOf(vp_node.v_mode), c.S_IWUSR);
    }

    vn_unlock(vp);
    if (vp_covered != null) {
        vn_unlock(vp_covered);
    }

    const link: *ffi.List = @ptrCast(&mp.m_link);
    link.init();
    list_head.insert(link);

    mountUnlock();
    return 0;
}

pub export fn sys_umount(path: [*c]u8) callconv(.c) c_int {
    mountLock();

    const head = get_mount_list();
    const list_head: *ffi.List = @ptrCast(head);
    var n = list_head.next;
    var mp: ?*c.struct_mount = null;
    while (n != list_head) {
        const next_node = n.?.next;
        const tmp = n.?.entry(c.struct_mount, "m_link");
        const path_ptr = @as([*c]const u8, @ptrCast(&tmp.m_path));
        if (ffi.prog.string.strcmp(path_ptr, path) == 0) {
            mp = tmp;
            break;
        }
        n = next_node;
    }

    if (mp == null) {
        mountUnlock();
        return ffi.prog.errno.EINVAL;
    }

    const mount_entry = mp.?;
    if (mount_entry.m_covered == null) {
        mountUnlock();
        return ffi.prog.errno.EINVAL;
    }

    const err = VFS_UNMOUNT(mount_entry);
    if (err != 0) {
        mountUnlock();
        return err;
    }

    const link: *ffi.List = @ptrCast(&mount_entry.m_link);
    link.remove();

    vrele(mount_entry.m_covered);
    vflush(mount_entry);
    binval(mount_entry.m_dev);

    if (mount_entry.m_dev != 0) {
        _ = c.device_close(@intCast(mount_entry.m_dev));
    }
    ffi.prog.stdlib.free(mount_entry);

    mountUnlock();
    return 0;
}

pub export fn sys_sync() callconv(.c) c_int {
    mountLock();
    const head = get_mount_list();
    const list_head: *ffi.List = @ptrCast(head);
    var n = list_head.next;
    while (n != list_head) {
        const next_node = n.?.next;
        const mp = n.?.entry(c.struct_mount, "m_link");
        _ = VFS_SYNC(mp);
        n = next_node;
    }
    mountUnlock();
    bio_sync();
    return 0;
}

fn count_match(path: [*c]const u8, mount_root: [*c]const u8) usize {
    var len: usize = 0;
    var p: [*]const u8 = @ptrCast(path);
    var mr: [*]const u8 = @ptrCast(mount_root);
    while (p[0] != 0 and mr[0] != 0) {
        if (p[0] != mr[0]) break;
        p += 1;
        mr += 1;
        len += 1;
    }
    if (mr[0] != 0) return 0;
    if (len == 1 and (p - 1)[0] == '/') return 1;
    if (p[0] == 0 or p[0] == '/') return len;
    return 0;
}

pub export fn vfs_findroot(path: [*c]u8, mp: [*c]c.mount_t, root: [*c][*c]u8) callconv(.c) c_int {
    if (path == null) return -1;

    mountLock();
    var m: ?*c.struct_mount = null;
    const head = get_mount_list();
    const list_head: *ffi.List = @ptrCast(head);
    var n = list_head.next;
    var max_len: usize = 0;
    while (n != list_head) {
        const next_node = n.?.next;
        const tmp = n.?.entry(c.struct_mount, "m_link");
        const tmp_path = @as([*c]const u8, @ptrCast(&tmp.m_path));
        const len = count_match(path, tmp_path);
        if (len > max_len) {
            max_len = len;
            m = tmp;
        }
        n = next_node;
    }
    mountUnlock();

    if (m == null) return -1;
    var r = path + max_len;
    if (r[0] == '/') {
        r += 1;
    }
    root.* = r;
    mp.* = m;
    return 0;
}

pub export fn vfs_busy(mp: c.mount_t) callconv(.c) void {
    if (mp) |m| {
        mountLock();
        const m_ptr: *c.struct_mount = @ptrCast(m);
        m_ptr.m_count += 1;
        mountUnlock();
    }
}

pub export fn vfs_unbusy(mp: c.mount_t) callconv(.c) void {
    if (mp) |m| {
        mountLock();
        const m_ptr: *c.struct_mount = @ptrCast(m);
        m_ptr.m_count -= 1;
        mountUnlock();
    }
}

pub export fn vfs_nullop() callconv(.c) c_int {
    return 0;
}

pub export fn vfs_einval() callconv(.c) c_int {
    return ffi.prog.errno.EINVAL;
}

pub export fn mount_dump() callconv(.c) void {
    mountLock();
    c.dprintf("mount_dump\n");
    c.dprintf("dev      count root\n");
    c.dprintf("-------- ----- --------\n");
    const head = get_mount_list();
    const list_head: *ffi.List = @ptrCast(head);
    var n = list_head.next;
    while (n != list_head) {
        const next_node = n.?.next;
        const mp = n.?.entry(c.struct_mount, "m_link");
        c.dprintf("%8x %5d %s\n", mp.m_dev, mp.m_count, @as([*c]const u8, @ptrCast(&mp.m_path)));
        n = next_node;
    }
    mountUnlock();
}
