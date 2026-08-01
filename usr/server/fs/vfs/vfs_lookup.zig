const ffi = @import("fs_ffi.zig");
const c = ffi.raw;

extern fn vfs_findroot(path: [*c]const u8, mp: [*c]c.mount_t, p: [*c][*c]u8) callconv(.c) c_int;
extern fn vn_lookup(mp: c.mount_t, path: [*c]const u8) callconv(.c) c.vnode_t;
extern fn vref(vp: c.vnode_t) callconv(.c) void;
extern fn vn_lock(vp: c.vnode_t) callconv(.c) void;
extern fn vget(mp: c.mount_t, path: [*c]const u8) callconv(.c) c.vnode_t;
extern fn vput(vp: c.vnode_t) callconv(.c) void;
extern fn sec_vnode_permission(path: [*c]const u8) callconv(.c) c_int;

extern fn strlcpy(dst: [*c]u8, src: [*c]const u8, size: usize) callconv(.c) usize;
extern fn strlcat(dst: [*c]u8, src: [*c]const u8, size: usize) callconv(.c) usize;
extern fn strrchr(s: [*c]const u8, ch: c_int) callconv(.c) [*c]u8;

fn VOP_LOOKUP(dvp: c.vnode_t, name_str: [*c]const u8, vp: c.vnode_t) c_int {
    if (dvp) |d| {
        const d_ptr: *c.struct_vnode = @ptrCast(d);
        if (d_ptr.v_op) |op| {
            const op_ptr: *c.struct_vnops = @ptrCast(op);
            if (op_ptr.vop_lookup) |lookup_fn| {
                return lookup_fn(dvp, @constCast(name_str), vp);
            }
        }
    }
    return ffi.prog.errno.ENOSYS;
}

pub export fn namei(path: [*c]u8, vpp: [*c]c.vnode_t) callconv(.c) c_int {
    var mp: c.mount_t = null;
    var p: [*c]u8 = null;

    if (vfs_findroot(path, &mp, &p) != 0) {
        return ffi.prog.errno.ENOTDIR;
    }

    var node: [c.PATH_MAX]u8 = undefined;
    _ = strlcpy(&node, "/", node.len);
    _ = strlcat(&node, p, node.len);

    var vp = vn_lookup(mp, &node);
    if (vp != null) {
        vpp.* = vp;
        return 0;
    }

    const mp_ptr: *c.struct_mount = @ptrCast(mp);
    const dvp_ref = mp_ptr.m_root;
    if (dvp_ref == null) {
        c.sys_panic("VFS: no root");
    }
    var dvp = dvp_ref.?;

    vref(dvp);
    vn_lock(dvp);
    node[0] = 0;

    var name: [c.PATH_MAX]u8 = undefined;

    while (p[0] != 0) {
        while (p[0] == '/') : (p += 1) {}
        var i: usize = 0;
        while (i < c.PATH_MAX) : (i += 1) {
            if (p[0] == 0 or p[0] == '/') break;
            name[i] = p[0];
            p += 1;
        }
        name[i] = 0;

        _ = strlcat(&node, "/", node.len);
        _ = strlcat(&node, &name, node.len);

        vp = vn_lookup(mp, &node);
        if (vp == null) {
            vp = vget(mp, &node);
            if (vp == null) {
                vput(dvp);
                return ffi.prog.errno.ENOMEM;
            }

            const err = VOP_LOOKUP(dvp, &name, vp);
            const vp_node: *c.struct_vnode = @ptrCast(vp.?);
            if (err != 0 or (p[0] == '/' and vp_node.v_type != c.VDIR)) {
                vput(vp);
                vput(dvp);
                return err;
            }
        }
        vput(dvp);
        const vp_val = vp.?;
        dvp = vp_val;

        while (p[0] != 0 and p[0] != '/') : (p += 1) {}
    }

    const vp_node: *c.struct_vnode = @ptrCast(vp.?);
    if (vp_node.v_type != c.VDIR and sec_vnode_permission(path) != 0) {
        vp_node.v_mode &= ~@as(@TypeOf(vp_node.v_mode), 0o111);
    }

    vpp.* = vp;
    return 0;
}

pub export fn lookup(path: [*c]u8, vpp: [*c]c.vnode_t, name: [*c][*c]u8) callconv(.c) c_int {
    var buf: [c.PATH_MAX]u8 = undefined;
    var root = [_]u8{ '/', 0 };

    _ = strlcpy(&buf, path, buf.len);
    const file = strrchr(&buf, '/');
    if (buf[0] == 0) return ffi.prog.errno.ENOTDIR;

    var dir: [*c]u8 = undefined;
    if (@intFromPtr(file) == @intFromPtr(@as([*c]u8, &buf))) {
        dir = &root;
    } else {
        file[0] = 0;
        dir = &buf;
    }

    var vp: c.vnode_t = null;
    const err = namei(dir, &vp);
    if (err != 0) return err;

    const vp_node: *c.struct_vnode = @ptrCast(vp.?);
    if (vp_node.v_type != c.VDIR) {
        vput(vp);
        return ffi.prog.errno.ENOTDIR;
    }
    vpp.* = vp;

    const r = strrchr(path, '/');
    if (r == null) return ffi.prog.errno.EINVAL;
    name.* = r + 1;

    return 0;
}
