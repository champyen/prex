const ffi = @import("fs_ffi.zig");
const c = ffi.raw;

extern fn namei(path: [*c]const u8, vpp: [*c]c.vnode_t) callconv(.c) c_int;
extern fn lookup(path: [*c]const u8, vpp: [*c]c.vnode_t, name: [*c][*c]u8) callconv(.c) c_int;
extern fn vn_access(vp: c.vnode_t, flags: c_int) callconv(.c) c_int;
extern fn vn_lock(vp: c.vnode_t) callconv(.c) void;
extern fn vn_unlock(vp: c.vnode_t) callconv(.c) void;
extern fn vput(vp: c.vnode_t) callconv(.c) void;
extern fn vrele(vp: c.vnode_t) callconv(.c) void;
extern fn vgone(vp: c.vnode_t) callconv(.c) void;
extern fn vcount(vp: c.vnode_t) callconv(.c) c_int;
extern fn vn_stat(vp: c.vnode_t, st: [*c]c.struct_stat) callconv(.c) c_int;

extern fn strcmp(s1: [*c]const u8, s2: [*c]const u8) callconv(.c) c_int;
extern fn strncmp(s1: [*c]const u8, s2: [*c]const u8, n: usize) callconv(.c) c_int;
extern fn strlen(s: [*c]const u8) callconv(.c) usize;
extern fn strrchr(s: [*c]const u8, ch: c_int) callconv(.c) [*c]u8;
extern fn strlcpy(dst: [*c]u8, src: [*c]const u8, size: usize) callconv(.c) usize;

const SEEK_SET: c_int = 0;
const SEEK_CUR: c_int = 1;
const SEEK_END: c_int = 2;
const R_OK: c_int = 0x04;
const W_OK: c_int = 0x02;
const X_OK: c_int = 0x01;

fn VOP_CREATE(dvp: c.vnode_t, name: [*c]const u8, mode: c.mode_t) c_int {
    if (dvp) |d| {
        const d_ptr: *c.struct_vnode = @ptrCast(d);
        if (d_ptr.v_op) |op| {
            const op_ptr: *c.struct_vnops = @ptrCast(op);
            if (op_ptr.vop_create) |create_fn| {
                return create_fn(dvp, @constCast(name), mode);
            }
        }
    }
    return ffi.prog.errno.ENOSYS;
}

fn VOP_TRUNCATE(vp: c.vnode_t, size: c.off_t) c_int {
    if (vp) |v| {
        const v_ptr: *c.struct_vnode = @ptrCast(v);
        if (v_ptr.v_op) |op| {
            const op_ptr: *c.struct_vnops = @ptrCast(op);
            if (op_ptr.vop_truncate) |trunc_fn| {
                return trunc_fn(vp, size);
            }
        }
    }
    return ffi.prog.errno.ENOSYS;
}

fn VOP_OPEN(vp: c.vnode_t, flags: c_int) c_int {
    if (vp) |v| {
        const v_ptr: *c.struct_vnode = @ptrCast(v);
        if (v_ptr.v_op) |op| {
            const op_ptr: *c.struct_vnops = @ptrCast(op);
            if (op_ptr.vop_open) |open_fn| {
                return open_fn(vp, flags);
            }
        }
    }
    return ffi.prog.errno.ENOSYS;
}

fn VOP_CLOSE(vp: c.vnode_t, fp: c.file_t) c_int {
    if (vp) |v| {
        const v_ptr: *c.struct_vnode = @ptrCast(v);
        if (v_ptr.v_op) |op| {
            const op_ptr: *c.struct_vnops = @ptrCast(op);
            if (op_ptr.vop_close) |close_fn| {
                return close_fn(vp, fp);
            }
        }
    }
    return ffi.prog.errno.ENOSYS;
}

fn VOP_READ(vp: c.vnode_t, fp: c.file_t, buf: ?*anyopaque, size: usize, count: [*c]usize) c_int {
    if (vp) |v| {
        const v_ptr: *c.struct_vnode = @ptrCast(v);
        if (v_ptr.v_op) |op| {
            const op_ptr: *c.struct_vnops = @ptrCast(op);
            if (op_ptr.vop_read) |read_fn| {
                return read_fn(vp, fp, buf, size, count);
            }
        }
    }
    return ffi.prog.errno.ENOSYS;
}

fn VOP_WRITE(vp: c.vnode_t, fp: c.file_t, buf: ?*anyopaque, size: usize, count: [*c]usize) c_int {
    if (vp) |v| {
        const v_ptr: *c.struct_vnode = @ptrCast(v);
        if (v_ptr.v_op) |op| {
            const op_ptr: *c.struct_vnops = @ptrCast(op);
            if (op_ptr.vop_write) |write_fn| {
                return write_fn(vp, fp, buf, size, count);
            }
        }
    }
    return ffi.prog.errno.ENOSYS;
}

fn VOP_SEEK(vp: c.vnode_t, fp: c.file_t, oldoff: c.off_t, newoff: c.off_t) c_int {
    if (vp) |v| {
        const v_ptr: *c.struct_vnode = @ptrCast(v);
        if (v_ptr.v_op) |op| {
            const op_ptr: *c.struct_vnops = @ptrCast(op);
            if (op_ptr.vop_seek) |seek_fn| {
                return seek_fn(vp, fp, oldoff, newoff);
            }
        }
    }
    return ffi.prog.errno.ENOSYS;
}

fn VOP_IOCTL(vp: c.vnode_t, fp: c.file_t, request: c_ulong, buf: ?*anyopaque) c_int {
    if (vp) |v| {
        const v_ptr: *c.struct_vnode = @ptrCast(v);
        if (v_ptr.v_op) |op| {
            const op_ptr: *c.struct_vnops = @ptrCast(op);
            if (op_ptr.vop_ioctl) |ioctl_fn| {
                return ioctl_fn(vp, fp, request, buf);
            }
        }
    }
    return ffi.prog.errno.ENOTTY;
}

fn VOP_FSYNC(vp: c.vnode_t, fp: c.file_t) c_int {
    if (vp) |v| {
        const v_ptr: *c.struct_vnode = @ptrCast(v);
        if (v_ptr.v_op) |op| {
            const op_ptr: *c.struct_vnops = @ptrCast(op);
            if (op_ptr.vop_fsync) |fsync_fn| {
                return fsync_fn(vp, fp);
            }
        }
    }
    return ffi.prog.errno.ENOSYS;
}

fn VOP_READDIR(vp: c.vnode_t, fp: c.file_t, dir: [*c]c.struct_dirent) c_int {
    if (vp) |v| {
        const v_ptr: *c.struct_vnode = @ptrCast(v);
        if (v_ptr.v_op) |op| {
            const op_ptr: *c.struct_vnops = @ptrCast(op);
            if (op_ptr.vop_readdir) |readdir_fn| {
                return readdir_fn(vp, fp, dir);
            }
        }
    }
    return ffi.prog.errno.ENOSYS;
}

fn VOP_MKDIR(dvp: c.vnode_t, name: [*c]const u8, mode: c.mode_t) c_int {
    if (dvp) |d| {
        const d_ptr: *c.struct_vnode = @ptrCast(d);
        if (d_ptr.v_op) |op| {
            const op_ptr: *c.struct_vnops = @ptrCast(op);
            if (op_ptr.vop_mkdir) |mkdir_fn| {
                return mkdir_fn(dvp, @constCast(name), mode);
            }
        }
    }
    return ffi.prog.errno.ENOSYS;
}

fn VOP_RMDIR(dvp: c.vnode_t, vp: c.vnode_t, name: [*c]const u8) c_int {
    if (dvp) |d| {
        const d_ptr: *c.struct_vnode = @ptrCast(d);
        if (d_ptr.v_op) |op| {
            const op_ptr: *c.struct_vnops = @ptrCast(op);
            if (op_ptr.vop_rmdir) |rmdir_fn| {
                return rmdir_fn(dvp, vp, @constCast(name));
            }
        }
    }
    return ffi.prog.errno.ENOSYS;
}

fn VOP_RENAME(dvp1: c.vnode_t, vp1: c.vnode_t, name1: [*c]const u8, dvp2: c.vnode_t, vp2: c.vnode_t, name2: [*c]const u8) c_int {
    if (dvp1) |d1| {
        const d1_ptr: *c.struct_vnode = @ptrCast(d1);
        if (d1_ptr.v_op) |op| {
            const op_ptr: *c.struct_vnops = @ptrCast(op);
            if (op_ptr.vop_rename) |rename_fn| {
                return rename_fn(dvp1, vp1, @constCast(name1), dvp2, vp2, @constCast(name2));
            }
        }
    }
    return ffi.prog.errno.ENOSYS;
}

fn VOP_REMOVE(dvp: c.vnode_t, vp: c.vnode_t, name: [*c]const u8) c_int {
    if (dvp) |d| {
        const d_ptr: *c.struct_vnode = @ptrCast(d);
        if (d_ptr.v_op) |op| {
            const op_ptr: *c.struct_vnops = @ptrCast(op);
            if (op_ptr.vop_remove) |remove_fn| {
                return remove_fn(dvp, vp, @constCast(name));
            }
        }
    }
    return ffi.prog.errno.ENOSYS;
}

fn FFLAGS(oflags: c_int) c_int {
    return oflags + 1;
}

fn check_dir_empty(path: [*c]u8) c_int {
    var fp: c.file_t = undefined;
    var dir: c.struct_dirent = undefined;

    var err = sys_opendir(path, &fp);
    if (err != 0) return err;

    while (true) {
        err = sys_readdir(fp, &dir);
        if (err != 0 and err != ffi.prog.errno.EACCES) break;
        if (strcmp(@ptrCast(&dir.d_name), ".") != 0 and strcmp(@ptrCast(&dir.d_name), "..") != 0) break;
    }

    _ = sys_closedir(fp);

    if (err == ffi.prog.errno.ENOENT) return 0;
    if (err == 0) return ffi.prog.errno.EEXIST;
    return err;
}

pub export fn sys_open(path: [*c]u8, flags: c_int, mode: c.mode_t, pfp: [*c]c.file_t) callconv(.c) c_int {
    var vp: ?*c.struct_vnode = null;
    var dvp: ?*c.struct_vnode = null;
    var filename: [*c]u8 = undefined;
    var err: c_int = 0;

    var f_flags = FFLAGS(flags);
    if ((f_flags & (c.FREAD | c.FWRITE)) == 0) {
        return ffi.prog.errno.EINVAL;
    }

    if ((f_flags & c.O_CREAT) != 0) {
        err = namei(path, &vp);
        if (err == ffi.prog.errno.ENOENT) {
            err = lookup(path, &dvp, &filename);
            if (err != 0) return err;
            err = vn_access(dvp, c.VWRITE);
            if (err != 0) {
                vput(dvp);
                return err;
            }
            var m = mode;
            m = (m & ~@as(c.mode_t, c.S_IFMT)) | @as(c.mode_t, c.S_IFREG);
            err = VOP_CREATE(dvp, filename, m);
            vput(dvp);
            if (err != 0) return err;
            err = namei(path, &vp);
            if (err != 0) return err;
            f_flags &= ~@as(c_int, c.O_TRUNC);
        } else if (err != 0) {
            return err;
        } else {
            if ((f_flags & c.O_EXCL) != 0) {
                vput(vp);
                return ffi.prog.errno.EEXIST;
            }
            f_flags &= ~@as(c_int, c.O_CREAT);
        }
    } else {
        err = namei(path, &vp);
        if (err != 0) return err;
    }

    if ((f_flags & c.O_CREAT) == 0) {
        if ((f_flags & c.FWRITE) != 0 or (f_flags & c.O_TRUNC) != 0) {
            err = vn_access(vp, c.VWRITE);
            if (err != 0) {
                vput(vp);
                return err;
            }
            if (vp.?.v_type == c.VDIR) {
                vput(vp);
                return ffi.prog.errno.EISDIR;
            }
        }
    }

    if ((f_flags & c.O_TRUNC) != 0) {
        if ((f_flags & c.FWRITE) == 0 or (vp.?.v_type == c.VDIR)) {
            vput(vp);
            return ffi.prog.errno.EINVAL;
        }
        err = VOP_TRUNCATE(vp, 0);
        if (err != 0) {
            vput(vp);
            return err;
        }
    }

    const mem = ffi.prog.stdlib.malloc(@sizeOf(c.struct_file)) orelse {
        vput(vp);
        return ffi.prog.errno.ENOMEM;
    };
    const fp_ptr: *c.struct_file = @ptrCast(@alignCast(mem));

    err = VOP_OPEN(vp, f_flags);
    if (err != 0) {
        ffi.prog.stdlib.free(fp_ptr);
        vput(vp);
        return err;
    }

    fp_ptr.f_vnode = vp;
    fp_ptr.f_flags = f_flags;
    fp_ptr.f_offset = 0;
    fp_ptr.f_count = 1;
    pfp.* = fp_ptr;
    vn_unlock(vp);
    return 0;
}

pub export fn sys_close(fp: c.file_t) callconv(.c) c_int {
    const fp_ptr: *c.struct_file = @ptrCast(fp);

    if (fp_ptr.f_count <= 0) {
        return ffi.prog.errno.EINVAL;
    }

    const vp = fp_ptr.f_vnode;
    fp_ptr.f_count -= 1;
    if (fp_ptr.f_count > 0) {
        vrele(vp);
        return 0;
    }
    vn_lock(vp);
    const err = VOP_CLOSE(vp, fp);
    if (err != 0) {
        vn_unlock(vp);
        return err;
    }
    vput(vp);
    ffi.prog.stdlib.free(fp_ptr);
    return 0;
}

pub export fn sys_read(fp: c.file_t, buf: ?*anyopaque, size: usize, count: [*c]usize) callconv(.c) c_int {
    const fp_ptr: *c.struct_file = @ptrCast(fp);

    if ((fp_ptr.f_flags & c.FREAD) == 0) {
        return ffi.prog.errno.EBADF;
    }
    if (size == 0) {
        count.* = 0;
        return 0;
    }
    const vp = fp_ptr.f_vnode;
    vn_lock(vp);
    const err = VOP_READ(vp, fp, buf, size, count);
    vn_unlock(vp);
    return err;
}

pub export fn sys_write(fp: c.file_t, buf: ?*anyopaque, size: usize, count: [*c]usize) callconv(.c) c_int {
    const fp_ptr: *c.struct_file = @ptrCast(fp);

    if ((fp_ptr.f_flags & c.FWRITE) == 0) {
        return ffi.prog.errno.EBADF;
    }
    if (size == 0) {
        count.* = 0;
        return 0;
    }
    const vp = fp_ptr.f_vnode;
    vn_lock(vp);
    const err = VOP_WRITE(vp, fp, buf, size, count);
    vn_unlock(vp);
    return err;
}

pub export fn sys_lseek(fp: c.file_t, off: c.off_t, @"type": c_int, cur_off: [*c]c.off_t) callconv(.c) c_int {
    const fp_ptr: *c.struct_file = @ptrCast(fp);
    const vp: *c.struct_vnode = @ptrCast(fp_ptr.f_vnode);

    vn_lock(vp);
    var new_off = off;
    switch (@"type") {
        SEEK_SET => {
            if (new_off < 0) new_off = 0;
            const v_size = @as(c.off_t, @intCast(vp.v_size));
            if (new_off > v_size) new_off = v_size;
        },
        SEEK_CUR => {
            const v_size = @as(c.off_t, @intCast(vp.v_size));
            if (fp_ptr.f_offset + new_off > v_size) {
                new_off = v_size;
            } else if (fp_ptr.f_offset + new_off < 0) {
                new_off = 0;
            } else {
                new_off = fp_ptr.f_offset + new_off;
            }
        },
        SEEK_END => {
            const v_size = @as(c.off_t, @intCast(vp.v_size));
            if (new_off > 0) {
                new_off = v_size;
            } else if (v_size + new_off < 0) {
                new_off = 0;
            } else {
                new_off = v_size + new_off;
            }
        },
        else => {
            vn_unlock(vp);
            return ffi.prog.errno.EINVAL;
        },
    }

    if (VOP_SEEK(vp, fp, fp_ptr.f_offset, new_off) != 0) {
        vn_unlock(vp);
        return ffi.prog.errno.EINVAL;
    }
    cur_off.* = new_off;
    fp_ptr.f_offset = new_off;
    vn_unlock(vp);
    return 0;
}

pub export fn sys_ioctl(fp: c.file_t, request: c_ulong, buf: ?*anyopaque) callconv(.c) c_int {
    const fp_ptr: *c.struct_file = @ptrCast(fp);

    if ((fp_ptr.f_flags & (c.FREAD | c.FWRITE)) == 0) {
        return ffi.prog.errno.EBADF;
    }

    const vp = fp_ptr.f_vnode;
    vn_lock(vp);
    const err = VOP_IOCTL(vp, fp, request, buf);
    vn_unlock(vp);
    return err;
}

pub export fn sys_fsync(fp: c.file_t) callconv(.c) c_int {
    const fp_ptr: *c.struct_file = @ptrCast(fp);

    if ((fp_ptr.f_flags & c.FWRITE) == 0) {
        return ffi.prog.errno.EBADF;
    }

    const vp = fp_ptr.f_vnode;
    vn_lock(vp);
    const err = VOP_FSYNC(vp, fp);
    vn_unlock(vp);
    return err;
}

pub export fn sys_fstat(fp: c.file_t, st: [*c]c.struct_stat) callconv(.c) c_int {
    const fp_ptr: *c.struct_file = @ptrCast(fp);
    const vp = fp_ptr.f_vnode;
    vn_lock(vp);
    const err = vn_stat(vp, st);
    vn_unlock(vp);
    return err;
}

pub export fn sys_opendir(path: [*c]u8, file: [*c]c.file_t) callconv(.c) c_int {
    var fp: c.file_t = undefined;

    const err = sys_open(path, c.O_RDONLY, 0, &fp);
    if (err != 0) return err;

    const fp_s: *c.struct_file = @ptrCast(fp);
    const dvp: *c.struct_vnode = @ptrCast(fp_s.f_vnode);
    vn_lock(dvp);
    if (dvp.v_type != c.VDIR) {
        vn_unlock(dvp);
        _ = sys_close(fp);
        return ffi.prog.errno.ENOTDIR;
    }
    vn_unlock(dvp);

    file.* = fp;
    return 0;
}

pub export fn sys_closedir(fp: c.file_t) callconv(.c) c_int {
    const fp_ptr: *c.struct_file = @ptrCast(fp);
    const dvp: *c.struct_vnode = @ptrCast(fp_ptr.f_vnode);

    vn_lock(dvp);
    if (dvp.v_type != c.VDIR) {
        vn_unlock(dvp);
        return ffi.prog.errno.EBADF;
    }
    vn_unlock(dvp);
    return sys_close(fp);
}

pub export fn sys_readdir(fp: c.file_t, dir: [*c]c.struct_dirent) callconv(.c) c_int {
    const fp_ptr: *c.struct_file = @ptrCast(fp);
    const dvp: *c.struct_vnode = @ptrCast(fp_ptr.f_vnode);

    vn_lock(dvp);
    if (dvp.v_type != c.VDIR) {
        vn_unlock(dvp);
        return ffi.prog.errno.EBADF;
    }
    const err = VOP_READDIR(dvp, fp, dir);
    vn_unlock(dvp);
    return err;
}

pub export fn sys_rewinddir(fp: c.file_t) callconv(.c) c_int {
    const fp_ptr: *c.struct_file = @ptrCast(fp);
    const dvp: *c.struct_vnode = @ptrCast(fp_ptr.f_vnode);

    vn_lock(dvp);
    if (dvp.v_type != c.VDIR) {
        vn_unlock(dvp);
        return ffi.prog.errno.EBADF;
    }
    fp_ptr.f_offset = 0;
    vn_unlock(dvp);
    return 0;
}

pub export fn sys_seekdir(fp: c.file_t, loc: c_long) callconv(.c) c_int {
    const fp_ptr: *c.struct_file = @ptrCast(fp);
    const dvp: *c.struct_vnode = @ptrCast(fp_ptr.f_vnode);

    vn_lock(dvp);
    if (dvp.v_type != c.VDIR) {
        vn_unlock(dvp);
        return ffi.prog.errno.EBADF;
    }
    fp_ptr.f_offset = @intCast(loc);
    vn_unlock(dvp);
    return 0;
}

pub export fn sys_telldir(fp: c.file_t, loc: [*c]c_long) callconv(.c) c_int {
    const fp_ptr: *c.struct_file = @ptrCast(fp);
    const dvp: *c.struct_vnode = @ptrCast(fp_ptr.f_vnode);

    vn_lock(dvp);
    if (dvp.v_type != c.VDIR) {
        vn_unlock(dvp);
        return ffi.prog.errno.EBADF;
    }
    loc.* = @intCast(fp_ptr.f_offset);
    vn_unlock(dvp);
    return 0;
}

pub export fn sys_mkdir(path: [*c]u8, mode: c.mode_t) callconv(.c) c_int {
    var vp: ?*c.struct_vnode = null;
    var dvp: ?*c.struct_vnode = null;
    var name: [*c]u8 = undefined;

    var err = namei(path, &vp);
    if (err == 0) {
        vput(vp);
        return ffi.prog.errno.EEXIST;
    }

    err = lookup(path, &dvp, &name);
    if (err != 0) return err;

    err = vn_access(dvp, c.VWRITE);
    if (err != 0) {
        vput(dvp);
        return err;
    }
    var m = mode;
    m = (m & ~@as(c.mode_t, c.S_IFMT)) | @as(c.mode_t, c.S_IFDIR);

    err = VOP_MKDIR(dvp, name, m);
    vput(dvp);
    return err;
}

pub export fn sys_rmdir(path: [*c]u8) callconv(.c) c_int {
    var vp: ?*c.struct_vnode = null;
    var dvp: ?*c.struct_vnode = null;
    var name: [*c]u8 = undefined;

    var err = check_dir_empty(path);
    if (err != 0) return err;

    err = namei(path, &vp);
    if (err != 0) return err;

    err = vn_access(vp, c.VWRITE);
    if (err != 0) {
        vput(vp);
        return err;
    }
    if (vp.?.v_type != c.VDIR) {
        vput(vp);
        return ffi.prog.errno.ENOTDIR;
    }
    if ((vp.?.v_flags & c.VROOT) != 0 or vcount(vp) >= 2) {
        vput(vp);
        return ffi.prog.errno.EBUSY;
    }

    err = lookup(path, &dvp, &name);
    if (err != 0) {
        vput(vp);
        return err;
    }

    err = VOP_RMDIR(dvp, vp, name);
    vn_unlock(vp);
    vgone(vp);
    vput(dvp);
    return err;
}

pub export fn sys_mknod(path: [*c]u8, mode: c.mode_t) callconv(.c) c_int {
    var vp: ?*c.struct_vnode = null;
    var dvp: ?*c.struct_vnode = null;
    var name: [*c]u8 = undefined;

    switch (mode & c.S_IFMT) {
        c.S_IFREG, c.S_IFDIR, c.S_IFIFO, c.S_IFSOCK => {},
        else => return ffi.prog.errno.EINVAL,
    }

    var err = namei(path, &vp);
    if (err == 0) {
        vput(vp);
        return ffi.prog.errno.EEXIST;
    }

    err = lookup(path, &dvp, &name);
    if (err != 0) return err;

    err = vn_access(dvp, c.VWRITE);
    if (err != 0) {
        vput(dvp);
        return err;
    }
    if ((mode & c.S_IFMT) == c.S_IFDIR) {
        err = VOP_MKDIR(dvp, name, mode);
    } else {
        err = VOP_CREATE(dvp, name, mode);
    }
    vput(dvp);
    return err;
}

pub export fn sys_rename(src: [*c]u8, dest: [*c]u8) callconv(.c) c_int {
    var vp1: ?*c.struct_vnode = null;
    var vp2: ?*c.struct_vnode = null;
    var dvp1: ?*c.struct_vnode = null;
    var dvp2: ?*c.struct_vnode = null;
    var sname: [*c]u8 = undefined;
    var dname: [*c]u8 = undefined;
    var dest_var = dest;

    var err = namei(src, &vp1);
    if (err != 0) return err;

    err = vn_access(vp1, c.VWRITE);
    if (err != 0) {
        vput(vp1);
        return err;
    }

    if (strncmp(src, dest_var, c.PATH_MAX) == 0) {
        vput(vp1);
        return 0;
    }

    const len = strlen(dest_var);
    if (strncmp(src, dest_var, len) == 0) {
        vput(vp1);
        return ffi.prog.errno.EINVAL;
    }

    if (vcount(vp1) >= 2) {
        vput(vp1);
        return ffi.prog.errno.EBUSY;
    }

    err = namei(dest_var, &vp2);
    if (err == 0) {
        if (vp1.?.v_type == c.VDIR and vp2.?.v_type != c.VDIR) {
            err = ffi.prog.errno.ENOTDIR;
            vput(vp2);
            vput(vp1);
            return err;
        } else if (vp1.?.v_type != c.VDIR and vp2.?.v_type == c.VDIR) {
            err = ffi.prog.errno.EISDIR;
            vput(vp2);
            vput(vp1);
            return err;
        }
        if (vp2.?.v_type == c.VDIR and check_dir_empty(dest_var) != 0) {
            err = ffi.prog.errno.EEXIST;
            vput(vp2);
            vput(vp1);
            return err;
        }
        if (vcount(vp2) >= 2) {
            err = ffi.prog.errno.EBUSY;
            vput(vp2);
            vput(vp1);
            return err;
        }
    }

    dname = strrchr(dest_var, '/');
    if (dname == null) {
        if (vp2 != null) vput(vp2);
        vput(vp1);
        return ffi.prog.errno.ENOTDIR;
    }
    if (@intFromPtr(dname) == @intFromPtr(dest_var)) {
        dest_var = @constCast("/");
    }

    dname[0] = 0;
    dname += 1;

    err = lookup(src, &dvp1, &sname);
    if (err != 0) {
        if (vp2 != null) vput(vp2);
        vput(vp1);
        return err;
    }

    err = namei(dest_var, &dvp2);
    if (err != 0) {
        vput(dvp1);
        if (vp2 != null) vput(vp2);
        vput(vp1);
        return err;
    }

    if (dvp1.?.v_mount != dvp2.?.v_mount) {
        err = ffi.prog.errno.EXDEV;
        vput(dvp2);
        vput(dvp1);
        if (vp2 != null) vput(vp2);
        vput(vp1);
        return err;
    }
    err = VOP_RENAME(dvp1, vp1, sname, dvp2, vp2, dname);
    vput(dvp2);
    vput(dvp1);
    if (vp2 != null) vput(vp2);
    vput(vp1);
    return err;
}

pub export fn sys_unlink(path: [*c]u8) callconv(.c) c_int {
    var name: [*c]u8 = undefined;
    var vp: ?*c.struct_vnode = null;
    var dvp: ?*c.struct_vnode = null;

    var err = namei(path, &vp);
    if (err != 0) return err;

    err = vn_access(vp, c.VWRITE);
    if (err != 0) {
        vput(vp);
        return err;
    }
    if (vp.?.v_type == c.VDIR) {
        vput(vp);
        return ffi.prog.errno.EPERM;
    }
    if ((vp.?.v_flags & c.VROOT) != 0 or vcount(vp) >= 2) {
        vput(vp);
        return ffi.prog.errno.EBUSY;
    }

    err = lookup(path, &dvp, &name);
    if (err != 0) {
        vput(vp);
        return err;
    }

    _ = VOP_REMOVE(dvp, vp, name);

    vn_unlock(vp);
    vgone(vp);
    vput(dvp);
    return 0;
}

pub export fn sys_access(path: [*c]u8, mode: c_int) callconv(.c) c_int {
    var vp: ?*c.struct_vnode = null;

    var err = namei(path, &vp);
    if (err != 0) return err;

    var flags: c_int = 0;
    if ((mode & R_OK) != 0) flags |= c.VREAD;
    if ((mode & W_OK) != 0) flags |= c.VWRITE;
    if ((mode & X_OK) != 0) flags |= c.VEXEC;

    err = vn_access(vp, flags);
    vput(vp);
    return err;
}

pub export fn sys_stat(path: [*c]u8, st: [*c]c.struct_stat) callconv(.c) c_int {
    var vp: ?*c.struct_vnode = null;

    var err = namei(path, &vp);
    if (err != 0) return err;

    err = vn_stat(vp, st);
    vput(vp);
    return err;
}

pub export fn sys_truncate(path: [*c]u8, length: c.off_t) callconv(.c) c_int {
    _ = path;
    _ = length;
    return 0;
}

pub export fn sys_ftruncate(fp: c.file_t, length: c.off_t) callconv(.c) c_int {
    _ = fp;
    _ = length;
    return 0;
}

pub export fn sys_fchdir(fp: c.file_t, cwd: [*c]u8) callconv(.c) c_int {
    const fp_ptr: *c.struct_file = @ptrCast(fp);
    const dvp: *c.struct_vnode = @ptrCast(fp_ptr.f_vnode);

    vn_lock(dvp);
    if (dvp.v_type != c.VDIR) {
        vn_unlock(dvp);
        return ffi.prog.errno.EBADF;
    }
    _ = strlcpy(cwd, dvp.v_path, c.PATH_MAX);
    vn_unlock(dvp);
    return 0;
}
