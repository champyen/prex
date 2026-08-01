const ffi = @import("fs_ffi.zig");
const c = ffi.raw;

extern fn get_vnode_table() callconv(.c) [*]c.struct_list;
extern fn get_vnode_lock() callconv(.c) *c.mutex_t;
extern fn strncmp(s1: [*c]const u8, s2: [*c]const u8, n: usize) callconv(.c) c_int;
extern fn strlcpy(dst: [*c]u8, src: [*c]const u8, size: usize) callconv(.c) usize;
extern fn strlen(s: [*c]const u8) callconv(.c) usize;
extern fn memset(dest: ?*anyopaque, ch: c_int, count: usize) callconv(.c) ?*anyopaque;

const VNODE_BUCKETS = 32;

const VREAD: c_int = 0o00004;
const VWRITE: c_int = 0o00002;
const VEXEC: c_int = 0o00001;

const S_IFREG: c.mode_t = 0o100000;
const S_IFDIR: c.mode_t = 0o040000;
const S_IFBLK: c.mode_t = 0o060000;
const S_IFCHR: c.mode_t = 0o020000;
const S_IFLNK: c.mode_t = 0o120000;
const S_IFSOCK: c.mode_t = 0o140000;
const S_IFIFO: c.mode_t = 0o010000;

const has_threads = @hasDecl(c, "CONFIG_FS_THREADS") and c.CONFIG_FS_THREADS > 1;

fn vnHash(mp: c.mount_t, path: [*c]const u8) c_uint {
    var val: c_uint = 0;
    if (path) |p| {
        var i: usize = 0;
        while (p[i] != 0) : (i += 1) {
            val = (val << 5) +% val +% @as(c_uint, @intCast(p[i]));
        }
    }
    return (val ^ @as(c_uint, @intCast(@intFromPtr(mp)))) & @as(c_uint, @intCast(VNODE_BUCKETS - 1));
}

fn vnodeLock() void {
    if (has_threads) {
        _ = c.mutex_lock(get_vnode_lock());
    }
}

fn vnodeUnlock() void {
    if (has_threads) {
        _ = c.mutex_unlock(get_vnode_lock());
    }
}

fn vopInactive(vp: c.vnode_t) void {
    const v: *c.struct_vnode = @ptrCast(vp.?);
    const op_ptr: *c.struct_vnops = @ptrCast(v.v_op);
    if (op_ptr.vop_inactive) |inactive_fn| {
        _ = inactive_fn(vp);
    }
}

fn vopGetattr(vp: c.vnode_t, vattr: *c.struct_vattr) c_int {
    const v: *c.struct_vnode = @ptrCast(vp.?);
    const op_ptr: *c.struct_vnops = @ptrCast(v.v_op);
    if (op_ptr.vop_getattr) |getattr_fn| {
        return getattr_fn(vp, vattr);
    }
    return -1;
}

fn vopIoctl(vp: c.vnode_t, fp: c.file_t, request: c_ulong, arg: ?*anyopaque) c_int {
    const v: *c.struct_vnode = @ptrCast(vp.?);
    const op_ptr: *c.struct_vnops = @ptrCast(v.v_op);
    if (op_ptr.vop_ioctl) |ioctl_fn| {
        return ioctl_fn(vp, fp, request, arg);
    }
    return -1;
}

pub export fn vn_lookup(mp: c.mount_t, path: [*c]const u8) callconv(.c) c.vnode_t {
    const table = get_vnode_table();
    const head: *ffi.List = @ptrCast(&table[vnHash(mp, path)]);

    var n = head.first();
    while (n != head) {
        const vp: *c.struct_vnode = n.?.entry(c.struct_vnode, "v_link");
        if (vp.v_mount == mp and strncmp(vp.v_path, path, c.PATH_MAX) == 0) {
            vp.v_refcnt += 1;
            vnodeUnlock();
            _ = c.mutex_lock(&vp.v_lock);
            vp.v_nrlocks += 1;
            return vp;
        }
        n = n.?.next;
    }
    vnodeUnlock();
    return null;
}

pub export fn vn_lock(vp: c.vnode_t) callconv(.c) void {
    const v: *c.struct_vnode = @ptrCast(vp.?);
    _ = c.mutex_lock(&v.v_lock);
    v.v_nrlocks += 1;
}

pub export fn vn_unlock(vp: c.vnode_t) callconv(.c) void {
    const v: *c.struct_vnode = @ptrCast(vp.?);
    v.v_nrlocks -= 1;
    _ = c.mutex_unlock(&v.v_lock);
}

pub export fn vget(mp: c.mount_t, path: [*c]const u8) callconv(.c) c.vnode_t {
    const vp_raw = ffi.prog.stdlib.malloc(@sizeOf(c.struct_vnode)) orelse return null;
    const vp: *c.struct_vnode = @ptrCast(@alignCast(vp_raw));
    _ = memset(vp, 0, @sizeOf(c.struct_vnode));

    const path_len = strlen(path) + 1;
    const path_buf_raw = ffi.prog.stdlib.malloc(path_len) orelse {
        ffi.prog.stdlib.free(vp);
        return null;
    };
    const path_buf: [*]u8 = @ptrCast(@alignCast(path_buf_raw));

    const mp_ptr: *c.struct_mount = @ptrCast(mp.?);
    const m_op: *c.struct_vfsops = @ptrCast(mp_ptr.m_op);
    vp.v_mount = mp;
    vp.v_refcnt = 1;
    vp.v_op = m_op.vfs_vnops;
    _ = strlcpy(path_buf, path, path_len);
    vp.v_path = @ptrCast(path_buf);
    const poll_list: *ffi.List = @ptrCast(&vp.v_poll_list);
    poll_list.init();
    _ = c.mutex_init(&vp.v_lock);
    vp.v_nrlocks = 0;

    if (m_op.vfs_vget) |vfs_vget_fn| {
        if (vfs_vget_fn(mp, vp) != 0) {
            _ = c.mutex_destroy(&vp.v_lock);
            ffi.prog.stdlib.free(vp.v_path);
            ffi.prog.stdlib.free(vp);
            return null;
        }
    }
    c.vfs_busy(vp.v_mount);
    _ = c.mutex_lock(&vp.v_lock);
    vp.v_nrlocks += 1;

    vnodeLock();
    const table = get_vnode_table();
    const head: *ffi.List = @ptrCast(&table[vnHash(mp, path)]);
    const vp_link: *ffi.List = @ptrCast(&vp.v_link);
    head.insert(vp_link);
    vnodeUnlock();
    return vp;
}

pub export fn vput(vp: c.vnode_t) callconv(.c) void {
    const v: *c.struct_vnode = @ptrCast(vp.?);
    v.v_refcnt -= 1;
    if (v.v_refcnt > 0) {
        vn_unlock(vp);
        return;
    }
    vnodeLock();
    const vp_link: *ffi.List = @ptrCast(&v.v_link);
    vp_link.remove();
    vnodeUnlock();

    vopInactive(vp);
    c.vfs_unbusy(v.v_mount);
    v.v_nrlocks -= 1;
    _ = c.mutex_unlock(&v.v_lock);
    _ = c.mutex_destroy(&v.v_lock);
    ffi.prog.stdlib.free(v.v_path);
    ffi.prog.stdlib.free(vp);
}

pub export fn vref(vp: c.vnode_t) callconv(.c) void {
    const v: *c.struct_vnode = @ptrCast(vp.?);
    vnodeLock();
    v.v_refcnt += 1;
    vnodeUnlock();
}

pub export fn vrele(vp: c.vnode_t) callconv(.c) void {
    const v: *c.struct_vnode = @ptrCast(vp.?);
    vnodeLock();
    v.v_refcnt -= 1;
    if (v.v_refcnt > 0) {
        vnodeUnlock();
        return;
    }
    const vp_link: *ffi.List = @ptrCast(&v.v_link);
    vp_link.remove();
    vnodeUnlock();

    vopInactive(vp);
    c.vfs_unbusy(v.v_mount);
    _ = c.mutex_destroy(&v.v_lock);
    ffi.prog.stdlib.free(v.v_path);
    ffi.prog.stdlib.free(vp);
}

pub export fn vgone(vp: c.vnode_t) callconv(.c) void {
    const v: *c.struct_vnode = @ptrCast(vp.?);
    vnodeLock();
    const vp_link: *ffi.List = @ptrCast(&v.v_link);
    vp_link.remove();
    c.vfs_unbusy(v.v_mount);
    _ = c.mutex_destroy(&v.v_lock);
    ffi.prog.stdlib.free(v.v_path);
    ffi.prog.stdlib.free(vp);
    vnodeUnlock();
}

pub export fn vcount(vp: c.vnode_t) callconv(.c) c_int {
    vn_lock(vp);
    const v: *c.struct_vnode = @ptrCast(vp.?);
    const count = v.v_refcnt;
    vn_unlock(vp);
    return count;
}

pub export fn vnode_poll_register(vp: c.vnode_t, pl: *c.struct_poll_listener) callconv(.c) void {
    const v: *c.struct_vnode = @ptrCast(vp.?);
    vnodeLock();
    const poll_list: *ffi.List = @ptrCast(&v.v_poll_list);
    const pl_link: *ffi.List = @ptrCast(&pl.link);
    poll_list.insert(pl_link);
    vnodeUnlock();

    if (v.v_type == c.VCHR or v.v_type == c.VBLK) {
        _ = vopIoctl(vp, null, c.TIOCSETEVENT, @as(?*anyopaque, @ptrCast(&pl.sem)));
    }
}

pub export fn vnode_poll_deregister(vp: c.vnode_t, pl: *c.struct_poll_listener) callconv(.c) void {
    vnodeLock();
    const pl_link: *ffi.List = @ptrCast(&pl.link);
    pl_link.remove();
    vnodeUnlock();

    const v: *c.struct_vnode = @ptrCast(vp.?);
    if (v.v_type == c.VCHR or v.v_type == c.VBLK) {
        var null_sem: c.sem_t = 0;
        _ = vopIoctl(vp, null, c.TIOCSETEVENT, @as(?*anyopaque, @ptrCast(&null_sem)));
    }
}

pub export fn vnode_poll_signal(vp: c.vnode_t, events: c_short) callconv(.c) void {
    const v: *c.struct_vnode = @ptrCast(vp.?);
    const poll_list: *ffi.List = @ptrCast(&v.v_poll_list);

    vnodeLock();
    var n = poll_list.first();
    while (n != poll_list) {
        const pl: *c.struct_poll_listener = n.?.entry(c.struct_poll_listener, "link");
        if (@as(c_short, @intCast(pl.events & @as(c_int, @intCast(events)))) != 0) {
            _ = c.sem_post(&pl.sem);
        }
        n = n.?.next;
    }
    vnodeUnlock();
}

pub export fn vflush(mp: c.mount_t) callconv(.c) void {
    _ = mp;
    const table = get_vnode_table();
    vnodeLock();
    var i: c_int = 0;
    while (i < VNODE_BUCKETS) : (i += 1) {
        const head: *ffi.List = @ptrCast(&table[@intCast(i)]);
        var n = head.first();
        while (n != head) {
            _ = n.?.entry(c.struct_vnode, "v_link");
            // XXX: incomplete in original C code
            n = n.?.next;
        }
    }
    vnodeUnlock();
}

pub export fn vn_stat(vp: c.vnode_t, st: *c.struct_stat) callconv(.c) c_int {
    const v: *c.struct_vnode = @ptrCast(vp.?);
    _ = memset(st, 0, @sizeOf(c.struct_stat));
    var vattr: c.struct_vattr = .{ .va_type = 0, .va_mode = 0, .va_mtime = 0 };

    if (vopGetattr(vp, &vattr) == 0) {
        st.st_mtime = vattr.va_mtime;
    }

    st.st_ino = @intCast(@intFromPtr(vp));
    st.st_size = @intCast(v.v_size);
    var mode: c.mode_t = v.v_mode;
    switch (v.v_type) {
        c.VREG => {
            mode |= S_IFREG;
        },
        c.VDIR => {
            mode |= S_IFDIR;
        },
        c.VBLK => {
            mode |= S_IFBLK;
        },
        c.VCHR => {
            mode |= S_IFCHR;
        },
        c.VLNK => {
            mode |= S_IFLNK;
        },
        c.VSOCK => {
            mode |= S_IFSOCK;
        },
        c.VFIFO => {
            mode |= S_IFIFO;
        },
        else => {
            return ffi.prog.errno.EBADF;
        },
    }
    st.st_mode = mode;
    st.st_blksize = @intCast(c.BSIZE);
    st.st_blocks = @intCast(v.v_size / @as(usize, @intCast(c.S_BLKSIZE)));
    st.st_uid = 0;
    st.st_gid = 0;
    if (v.v_type == c.VCHR or v.v_type == c.VBLK) {
        st.st_rdev = @intCast(@intFromPtr(v.v_data));
    }
    return 0;
}

pub export fn vn_access(vp: c.vnode_t, flags: c_int) callconv(.c) c_int {
    const v: *c.struct_vnode = @ptrCast(vp.?);

    if ((flags & VEXEC) != 0 and (v.v_mode & 0o111) == 0) {
        return ffi.prog.errno.EACCES;
    }
    if ((flags & VREAD) != 0 and (v.v_mode & 0o444) == 0) {
        return ffi.prog.errno.EACCES;
    }
    if ((flags & VWRITE) != 0) {
        const mp_ptr: *c.struct_mount = @ptrCast(v.v_mount.?);
        if ((mp_ptr.m_flags & c.MNT_RDONLY) != 0) {
            return ffi.prog.errno.EROFS;
        }
        if ((v.v_mode & 0o222) == 0) {
            return ffi.prog.errno.EACCES;
        }
    }
    return 0;
}

pub export fn vop_nullop() callconv(.c) c_int {
    return 0;
}

pub export fn vop_einval() callconv(.c) c_int {
    return ffi.prog.errno.EINVAL;
}

pub export fn vop_poll_default(vp: c.vnode_t, fp: c.file_t, events: c_int) callconv(.c) c_int {
    _ = vp;
    _ = fp;
    return events & (c.POLLIN | c.POLLOUT | c.POLLRDNORM | c.POLLWRNORM);
}

pub export fn vnode_init() callconv(.c) void {
    const table = get_vnode_table();
    var i: c_int = 0;
    while (i < VNODE_BUCKETS) : (i += 1) {
        const head: *ffi.List = @ptrCast(&table[@intCast(i)]);
        head.init();
    }
}
