/// main.zig - File system server IPC entry (Zig root)
///
/// Each fs_* handler is migrated incrementally from _main.c following
/// the MAAD per-function protocol. Until a handler is migrated here,
/// it is provided by _main.c (which is kept in the build during the
/// migration window and removed only after the full verification).
const ffi = @import("fs_ffi.zig");
const c = ffi.raw;
const prog = @import("prog");
const task = @import("task");

// unistd.h access mode bits (see include/unistd.h)
const R_OK: c_int = 0x04;
const W_OK: c_int = 0x02;

// fcntl.h open mode bits (see include/sys/fcntl.h)
const O_RDONLY: c_int = 0;
const O_WRONLY: c_int = 1;
const O_RDWR: c_int = 2;
const O_ACCMODE: c_int = 0x00000003;
const O_APPEND: c_int = 0x00000008;

// fcntl.h fcntl command + flag bits
const F_DUPFD: c_int = 0;
const F_GETFD: c_int = 1;
const F_SETFD: c_int = 2;
const F_GETFL: c_int = 3;
const F_SETFL: c_int = 4;
const FD_CLOEXEC: c_int = 1;

// stat.h file types + fcntl O_NONBLOCK
const S_IFIFO: c.mode_t = 0o010000;
const O_NONBLOCK: c_int = 0x00000004;

extern fn sprintf([*c]u8, [*c]const u8, ...) callconv(.c) c_int;

// ---------------------------------------------------------------------------
// Step 2.1: trivial handlers (single-call dispatch into sys_* / task_*)
// ---------------------------------------------------------------------------

pub export fn fs_sync(t: ?*c.struct_task, msg: [*c]c.struct_msg) callconv(.c) c_int {
    _ = t;
    _ = msg;
    return c.sys_sync();
}

pub export fn fs_getcwd(t: ?*c.struct_task, msg: [*c]c.struct_path_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    _ = ffi.prog.string.strlcpy(&msg[0].path, @ptrCast(&task_ptr.t_cwd), @sizeOf(@TypeOf(msg[0].path)));
    return 0;
}

pub export fn fs_isatty(t: ?*c.struct_task, msg: [*c]c.struct_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    const fd = msg[0].data[0];
    const fp_raw = c.task_getfp(task_ptr, fd);
    if (fp_raw == null) return prog.errno.EBADF;
    const fp: *c.struct_file = @ptrCast(fp_raw);
    const istty: c_int = if ((fp.f_vnode.?.*.v_flags & c.VISTTY) != 0) 1 else 0;
    msg[0].data[0] = istty;
    return 0;
}

pub export fn fs_lseek(t: ?*c.struct_task, msg: [*c]c.struct_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    const fp_raw = c.task_getfp(task_ptr, msg[0].data[0]);
    if (fp_raw == null) return prog.errno.EBADF;
    const offset: c.off_t = @bitCast(msg[0].data[1]);
    const whence = msg[0].data[2];
    var org: c.off_t = 0;
    const error_code = c.sys_lseek(fp_raw, offset, whence, &org);
    msg[0].data[0] = @as(c_int, @bitCast(org));
    return error_code;
}

pub export fn fs_readdir(t: ?*c.struct_task, msg: [*c]c.struct_dir_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    const fp_raw = c.task_getfp(task_ptr, msg[0].fd);
    if (fp_raw == null) return prog.errno.EBADF;
    return c.sys_readdir(fp_raw, &msg[0].dirent);
}

pub export fn fs_rewinddir(t: ?*c.struct_task, msg: [*c]c.struct_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    const fp_raw = c.task_getfp(task_ptr, msg[0].data[0]);
    if (fp_raw == null) return prog.errno.EBADF;
    return c.sys_rewinddir(fp_raw);
}

pub export fn fs_seekdir(t: ?*c.struct_task, msg: [*c]c.struct_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    const fp_raw = c.task_getfp(task_ptr, msg[0].data[0]);
    if (fp_raw == null) return prog.errno.EBADF;
    const loc: c_long = @bitCast(msg[0].data[1]);
    return c.sys_seekdir(fp_raw, loc);
}

pub export fn fs_telldir(t: ?*c.struct_task, msg: [*c]c.struct_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    const fp_raw = c.task_getfp(task_ptr, msg[0].data[0]);
    if (fp_raw == null) return prog.errno.EBADF;
    var loc: c_long = @bitCast(msg[0].data[1]);
    const error_code = c.sys_telldir(fp_raw, &loc);
    if (error_code != 0) return error_code;
    msg[0].data[0] = @as(c_int, @bitCast(loc));
    return 0;
}

// ---------------------------------------------------------------------------
// Step 2.2: task_conv wrappers (path resolution + single sys_* call)
// ---------------------------------------------------------------------------

pub export fn fs_close(t: ?*c.struct_task, msg: [*c]c.struct_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    const fd = msg[0].data[0];
    if (fd >= c.OPEN_MAX) return prog.errno.EBADF;
    const fp = task_ptr.t_ofile[@intCast(fd)];
    if (fp == null) return prog.errno.EBADF;
    const error_code = c.sys_close(fp);
    if (error_code != 0) return error_code;
    task_ptr.t_ofile[@intCast(fd)] = null;
    task_ptr.t_nopens -= 1;
    return 0;
}

pub export fn fs_mknod(t: ?*c.struct_task, msg: [*c]c.struct_open_msg) callconv(.c) c_int {
    var path: [c.PATH_MAX]u8 = undefined;
    const error_code = c.task_conv(t, &msg[0].path, c.VWRITE, &path);
    if (error_code != 0) return error_code;
    return c.sys_mknod(&path, msg[0].mode);
}

pub export fn fs_mkdir(t: ?*c.struct_task, msg: [*c]c.struct_open_msg) callconv(.c) c_int {
    var path: [c.PATH_MAX]u8 = undefined;
    const error_code = c.task_conv(t, &msg[0].path, c.VWRITE, &path);
    if (error_code != 0) return error_code;
    return c.sys_mkdir(&path, msg[0].mode);
}

pub export fn fs_rmdir(t: ?*c.struct_task, msg: [*c]c.struct_path_msg) callconv(.c) c_int {
    var path: [c.PATH_MAX]u8 = undefined;
    const error_code = c.task_conv(t, &msg[0].path, c.VWRITE, &path);
    if (error_code != 0) return error_code;
    return c.sys_rmdir(&path);
}

pub export fn fs_link(_: ?*c.struct_task, _: [*c]c.struct_msg) callconv(.c) c_int {
    // XXX: not implemented
    return prog.errno.EPERM;
}

pub export fn fs_unlink(t: ?*c.struct_task, msg: [*c]c.struct_path_msg) callconv(.c) c_int {
    var path: [c.PATH_MAX]u8 = undefined;
    const error_code = c.task_conv(t, &msg[0].path, c.VWRITE, &path);
    if (error_code != 0) return error_code;
    return c.sys_unlink(&path);
}

pub export fn fs_stat(t: ?*c.struct_task, msg: [*c]c.struct_stat_msg) callconv(.c) c_int {
    var path: [c.PATH_MAX]u8 = undefined;
    const error_code = c.task_conv(t, &msg[0].path, 0, &path);
    if (error_code != 0) return error_code;
    return c.sys_stat(&path, &msg[0].st);
}

pub export fn fs_access(t: ?*c.struct_task, msg: [*c]c.struct_path_msg) callconv(.c) c_int {
    var path: [c.PATH_MAX]u8 = undefined;
    const mode = msg[0].data[0];
    var acc: c_int = 0;
    if ((mode & R_OK) != 0) acc |= c.VREAD;
    if ((mode & W_OK) != 0) acc |= c.VWRITE;
    const error_code = c.task_conv(t, &msg[0].path, acc, &path);
    if (error_code != 0) return error_code;
    return c.sys_access(&path, mode);
}

pub export fn fs_truncate(t: ?*c.struct_task, msg: [*c]c.struct_path_msg) callconv(.c) c_int {
    var path: [c.PATH_MAX]u8 = undefined;
    const error_code = c.task_conv(t, &msg[0].path, c.VWRITE, &path);
    if (error_code != 0) return error_code;
    const length: c.off_t = @bitCast(msg[0].data[0]);
    return c.sys_truncate(&path, length);
}

// ---------------------------------------------------------------------------
// Step 2.3: file-table handlers (fd allocation + task_getfp lookups)
// ---------------------------------------------------------------------------

pub export fn fs_ioctl(t: ?*c.struct_task, msg: [*c]c.struct_ioctl_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    const fp_raw = c.task_getfp(task_ptr, msg[0].fd);
    if (fp_raw == null) return prog.errno.EBADF;
    return c.sys_ioctl(fp_raw, msg[0].request, &msg[0].buf);
}

pub export fn fs_fsync(t: ?*c.struct_task, msg: [*c]c.struct_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    const fp_raw = c.task_getfp(task_ptr, msg[0].data[0]);
    if (fp_raw == null) return prog.errno.EBADF;
    return c.sys_fsync(fp_raw);
}

pub export fn fs_fstat(t: ?*c.struct_task, msg: [*c]c.struct_stat_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    const fp_raw = c.task_getfp(task_ptr, msg[0].fd);
    if (fp_raw == null) return prog.errno.EBADF;
    return c.sys_fstat(fp_raw, &msg[0].st);
}

pub export fn fs_closedir(t: ?*c.struct_task, msg: [*c]c.struct_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    const fd = msg[0].data[0];
    if (fd >= c.OPEN_MAX) return prog.errno.EBADF;
    const fp = task_ptr.t_ofile[@intCast(fd)];
    if (fp == null) return prog.errno.EBADF;
    const error_code = c.sys_closedir(fp);
    if (error_code != 0) return error_code;
    task_ptr.t_ofile[@intCast(fd)] = null;
    return 0;
}

pub export fn fs_opendir(t: ?*c.struct_task, msg: [*c]c.struct_open_msg) callconv(.c) c_int {
    var path: [c.PATH_MAX]u8 = undefined;
    const task_ptr = t orelse return prog.errno.EINVAL;
    const fd = c.task_newfd(task_ptr);
    if (fd == -1) return prog.errno.EMFILE;

    const conv_err = c.task_conv(t, &msg[0].path, c.VREAD, &path);
    if (conv_err != 0) return conv_err;

    var fp: c.file_t = null;
    const open_err = c.sys_opendir(&path, &fp);
    if (open_err != 0) return open_err;

    task_ptr.t_ofile[@intCast(fd)] = fp;
    msg[0].fd = fd;
    return 0;
}

pub export fn fs_open(t: ?*c.struct_task, msg: [*c]c.struct_open_msg) callconv(.c) c_int {
    var path: [c.PATH_MAX]u8 = undefined;
    const task_ptr = t orelse return prog.errno.EINVAL;
    const fd = c.task_newfd(task_ptr);
    if (fd == -1) return prog.errno.EMFILE;

    var acc: c_int = 0;
    switch (msg[0].flags & O_ACCMODE) {
        O_RDONLY => acc = c.VREAD,
        O_WRONLY => acc = c.VWRITE,
        O_RDWR => acc = c.VREAD | c.VWRITE,
        else => {},
    }
    const conv_err = c.task_conv(t, &msg[0].path, acc, &path);
    if (conv_err != 0) return conv_err;

    var fp: c.file_t = null;
    const open_err = c.sys_open(&path, msg[0].flags, msg[0].mode, &fp);
    if (open_err != 0) return open_err;

    task_ptr.t_ofile[@intCast(fd)] = fp;
    task_ptr.t_nopens += 1;
    msg[0].fd = fd;
    return 0;
}

// ---------------------------------------------------------------------------
// Step 2.4: vm_map handlers (cross-address-space buffer mapping)
// ---------------------------------------------------------------------------

pub export fn fs_read(t: ?*c.struct_task, msg: [*c]c.struct_io_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    const fp_raw = c.task_getfp(task_ptr, msg[0].fd);
    if (fp_raw == null) return prog.errno.EBADF;
    var buf: ?*anyopaque = null;
    const map_err = c.vm_map(msg[0].hdr.task, msg[0].buf, msg[0].size, &buf);
    if (map_err != 0) return map_err;

    var bytes: usize = 0;
    const read_err = c.sys_read(fp_raw, buf, msg[0].size, &bytes);
    msg[0].size = bytes;
    _ = c.vm_free(c.task_self(), buf);
    return read_err;
}

pub export fn fs_write(t: ?*c.struct_task, msg: [*c]c.struct_io_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    const fp_raw = c.task_getfp(task_ptr, msg[0].fd);
    if (fp_raw == null) return prog.errno.EBADF;
    var buf: ?*anyopaque = null;
    const map_err = c.vm_map(msg[0].hdr.task, msg[0].buf, msg[0].size, &buf);
    if (map_err != 0) return map_err;

    var bytes: usize = 0;
    const write_err = c.sys_write(fp_raw, buf, msg[0].size, &bytes);
    msg[0].size = bytes;
    _ = c.vm_free(c.task_self(), buf);
    return write_err;
}

// ---------------------------------------------------------------------------
// Step 2.5: dir handlers (cwd mutation + sys_rename)
// ---------------------------------------------------------------------------

pub export fn fs_chdir(t: ?*c.struct_task, msg: [*c]c.struct_path_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    var path: [c.PATH_MAX]u8 = undefined;
    const conv_err = c.task_conv(t, &msg[0].path, c.VREAD, &path);
    if (conv_err != 0) return conv_err;

    // Verify directory exists by opening it as a directory
    var fp: c.file_t = null;
    const open_err = c.sys_opendir(&path, &fp);
    if (open_err != 0) return open_err;

    // Release previous cwd fp if any
    if (task_ptr.t_cwdfp) |old_fp| {
        _ = c.sys_closedir(old_fp);
    }
    task_ptr.t_cwdfp = fp;
    _ = ffi.prog.string.strlcpy(@ptrCast(&task_ptr.t_cwd), @ptrCast(&path), @sizeOf(@TypeOf(task_ptr.t_cwd)));
    return 0;
}

pub export fn fs_fchdir(t: ?*c.struct_task, msg: [*c]c.struct_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    const fd = msg[0].data[0];
    const fp_raw = c.task_getfp(task_ptr, fd);
    if (fp_raw == null) return prog.errno.EBADF;

    if (task_ptr.t_cwdfp) |old_fp| {
        _ = c.sys_closedir(old_fp);
    }
    task_ptr.t_cwdfp = fp_raw;
    return c.sys_fchdir(fp_raw, &task_ptr.t_cwd);
}

pub export fn fs_rename(t: ?*c.struct_task, msg: [*c]c.struct_path_msg) callconv(.c) c_int {
    var src: [c.PATH_MAX]u8 = undefined;
    var dest: [c.PATH_MAX]u8 = undefined;
    const src_err = c.task_conv(t, &msg[0].path, c.VREAD, &src);
    if (src_err != 0) return src_err;
    const dest_err = c.task_conv(t, &msg[0].path2, c.VWRITE, &dest);
    if (dest_err != 0) return dest_err;
    return c.sys_rename(&src, &dest);
}

// ---------------------------------------------------------------------------
// Step 2.6: vref handlers (fd duplication + fcntl flags)
// ---------------------------------------------------------------------------

pub export fn fs_dup(t: ?*c.struct_task, msg: [*c]c.struct_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    const old_fd = msg[0].data[0];
    const fp_raw = c.task_getfp(task_ptr, old_fd);
    if (fp_raw == null) return prog.errno.EBADF;
    const fp: *c.struct_file = @ptrCast(fp_raw);

    const new_fd = c.task_newfd(task_ptr);
    if (new_fd == -1) return prog.errno.EMFILE;

    task_ptr.t_ofile[@intCast(new_fd)] = fp_raw;
    c.vref(fp.f_vnode);
    fp.f_count += 1;
    msg[0].data[0] = new_fd;
    return 0;
}

pub export fn fs_dup2(t: ?*c.struct_task, msg: [*c]c.struct_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    const old_fd = msg[0].data[0];
    const new_fd = msg[0].data[1];
    if (old_fd >= c.OPEN_MAX or new_fd >= c.OPEN_MAX) return prog.errno.EBADF;
    const fp_raw = task_ptr.t_ofile[@intCast(old_fd)];
    if (fp_raw == null) return prog.errno.EBADF;
    const fp: *c.struct_file = @ptrCast(fp_raw);

    // Close previous occupant of new_fd slot, if any.
    if (task_ptr.t_ofile[@intCast(new_fd)]) |org| {
        _ = c.sys_close(org);
    }
    task_ptr.t_ofile[@intCast(new_fd)] = fp_raw;
    c.vref(fp.f_vnode);
    fp.f_count += 1;
    msg[0].data[0] = new_fd;
    return 0;
}

pub export fn fs_fcntl(t: ?*c.struct_task, msg: [*c]c.struct_fcntl_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    const fp_raw = c.task_getfp(task_ptr, msg[0].fd);
    if (fp_raw == null) return prog.errno.EBADF;
    const fp: *c.struct_file = @ptrCast(fp_raw);

    const arg = msg[0].arg;
    switch (msg[0].cmd) {
        F_DUPFD => {
            if (arg >= c.OPEN_MAX) return prog.errno.EINVAL;
            const new_fd = c.task_newfd(task_ptr);
            if (new_fd == -1) return prog.errno.EMFILE;
            task_ptr.t_ofile[@intCast(new_fd)] = fp_raw;
            c.vref(fp.f_vnode);
            fp.f_count += 1;
            msg[0].arg = new_fd;
        },
        F_GETFD => {
            msg[0].arg = fp.f_flags & FD_CLOEXEC;
        },
        F_SETFD => {
            fp.f_flags = (fp.f_flags & ~@as(c_int, @bitCast(FD_CLOEXEC))) | (arg & FD_CLOEXEC);
            msg[0].arg = 0;
        },
        F_GETFL => {
            msg[0].arg = fp.f_flags;
        },
        F_SETFL => {
            fp.f_flags = (fp.f_flags & ~O_APPEND) | (arg & O_APPEND);
            msg[0].arg = 0;
        },
        else => {
            msg[0].arg = -1;
        },
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Step 2.7: fs_pipe (FIFO-based pipe)
// ---------------------------------------------------------------------------

pub export fn fs_pipe(t: ?*c.struct_task, msg: [*c]c.struct_msg) callconv(.c) c_int {
    if (!@hasDecl(c, "CONFIG_FIFOFS")) return prog.errno.ENOSYS;

    const task_ptr = t orelse return prog.errno.EINVAL;
    // Allocate rfd and wfd up front; we'll create the fifo node and open it,
    // then bind the resulting file pointers to the slots.
    const rfd = c.task_newfd(task_ptr);
    if (rfd == -1) return prog.errno.EMFILE;
    const wfd = c.task_newfd(task_ptr);
    if (wfd == -1) {
        task_ptr.t_ofile[@intCast(rfd)] = null;
        return prog.errno.EMFILE;
    }

    var path: [c.PATH_MAX]u8 = undefined;
    _ = sprintf(&path, "/mnt/fifo/pipe-%x-%d", @as(c_uint, @intCast(task_ptr.t_taskid)), rfd);

    var err = c.sys_mknod(&path, S_IFIFO);
    if (err != 0) {
        task_ptr.t_ofile[@intCast(rfd)] = null;
        task_ptr.t_ofile[@intCast(wfd)] = null;
        return err;
    }

    var rfp: c.file_t = null;
    err = c.sys_open(&path, O_RDONLY | O_NONBLOCK, 0, &rfp);
    if (err != 0) {
        task_ptr.t_ofile[@intCast(rfd)] = null;
        task_ptr.t_ofile[@intCast(wfd)] = null;
        return err;
    }

    var wfp: c.file_t = null;
    err = c.sys_open(&path, O_WRONLY | O_NONBLOCK, 0, &wfp);
    if (err != 0) {
        _ = c.sys_close(rfp);
        task_ptr.t_ofile[@intCast(rfd)] = null;
        task_ptr.t_ofile[@intCast(wfd)] = null;
        return err;
    }

    task_ptr.t_ofile[@intCast(rfd)] = rfp;
    task_ptr.t_ofile[@intCast(wfd)] = wfp;
    task_ptr.t_nopens += 2;
    msg[0].data[0] = rfd;
    msg[0].data[1] = wfd;
    return 0;
}

// ---------------------------------------------------------------------------
// Step 2.8: task lifecycle (register / fork / exec / exit)
// ---------------------------------------------------------------------------

pub export fn fs_register(_: ?*c.struct_task, msg: [*c]c.struct_msg) callconv(.c) c_int {
    var tmp: ?*c.struct_task = null;
    return c.task_alloc(msg[0].hdr.task, &tmp);
}

pub export fn fs_exec(t: ?*c.struct_task, msg: [*c]c.struct_msg) callconv(.c) c_int {
    _ = t;
    const old_id: c.task_t = @bitCast(msg[0].data[0]);
    const new_id: c.task_t = @bitCast(msg[0].data[1]);

    const target_opt = c.task_lookup(old_id);
    const target_ptr = target_opt orelse return prog.errno.EINVAL;

    c.task_setid(target_ptr, new_id);

    var fd: c_int = 0;
    while (fd < c.OPEN_MAX) : (fd += 1) {
        const fp_raw = target_ptr[0].t_ofile[@intCast(fd)];
        if (fp_raw) |raw| {
            const fp: *c.struct_file = @ptrCast(raw);
            if (fp.f_vnode.?.*.v_type == c.VDIR) {
                _ = c.sys_close(fp_raw);
                target_ptr[0].t_ofile[@intCast(fd)] = null;
            }
        }
    }
    c.task_unlock(target_ptr);
    return 0;
}

pub export fn fs_fork(t: ?*c.struct_task, msg: [*c]c.struct_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    const child_taskid: c.task_t = @bitCast(msg[0].data[0]);
    var newtask: ?*c.struct_task = null;
    const err = c.task_alloc(child_taskid, &newtask);
    if (err != 0) return err;
    const new_ptr = newtask.?;

    new_ptr.t_cwdfp = task_ptr.t_cwdfp;
    _ = ffi.prog.string.strlcpy(@ptrCast(&new_ptr.t_cwd), @ptrCast(&task_ptr.t_cwd), @sizeOf(@TypeOf(new_ptr.t_cwd)));

    var i: c_int = 0;
    while (i < c.OPEN_MAX) : (i += 1) {
        const fp_raw = task_ptr.t_ofile[@intCast(i)];
        new_ptr.t_ofile[@intCast(i)] = fp_raw;
        if (fp_raw) |raw| {
            const fp: *c.struct_file = @ptrCast(raw);
            c.vref(fp.f_vnode);
            fp.f_count += 1;
        }
    }
    if (new_ptr.t_cwdfp) |cwdfp| {
        const cwd_file: *c.struct_file = @ptrCast(cwdfp);
        cwd_file.f_count += 1;
        c.vref(cwd_file.f_vnode);
    }
    return 0;
}

pub export fn fs_exit(t: ?*c.struct_task, _: [*c]c.struct_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    var fd: c_int = 0;
    while (fd < c.OPEN_MAX) : (fd += 1) {
        const fp_raw = task_ptr.t_ofile[@intCast(fd)];
        if (fp_raw != null) {
            _ = c.sys_close(fp_raw);
        }
    }
    if (task_ptr.t_cwdfp) |cwd| {
        _ = c.sys_close(cwd);
    }
    c.task_free(task_ptr);
    return 0;
}

// ---------------------------------------------------------------------------
// Step 2.9: poll handlers (select/poll multiplexing)
// ---------------------------------------------------------------------------

pub export fn fs_poll_register(t: ?*c.struct_task, msg: [*c]c.struct_fs_poll_msg) callconv(.c) c_int {
    return c.sys_poll_register(t, msg[0].sem_id, msg[0].nfds, &msg[0].fds);
}

pub export fn fs_poll_deregister(t: ?*c.struct_task, msg: [*c]c.struct_fs_poll_msg) callconv(.c) c_int {
    return c.sys_poll_deregister(t, msg[0].sem_id);
}

pub export fn fs_poll_query(t: ?*c.struct_task, msg: [*c]c.struct_fs_poll_msg) callconv(.c) c_int {
    const ready = c.sys_poll_query(t, msg[0].nfds, &msg[0].fds);
    if (ready < 0) return -ready;
    msg[0].nfds_ready = ready;
    msg[0].hdr.status = 0;
    return 0;
}

pub export fn fs_ftruncate(t: ?*c.struct_task, msg: [*c]c.struct_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    const fp_raw = c.task_getfp(task_ptr, msg[0].data[0]);
    if (fp_raw == null) return prog.errno.EBADF;
    const length: c.off_t = @bitCast(msg[0].data[1]);
    return c.sys_ftruncate(fp_raw, length);
}

pub export fn fs_mount(t: ?*c.struct_task, msg: [*c]c.struct_mount_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    if (c.task_chkcap(task_ptr.t_taskid, c.CAP_DISKADMIN) != 0) return prog.errno.EPERM;
    return c.sys_mount(&msg[0].dev, &msg[0].dir, &msg[0].fs, msg[0].flags, &msg[0].data);
}

pub export fn fs_umount(t: ?*c.struct_task, msg: [*c]c.struct_path_msg) callconv(.c) c_int {
    const task_ptr = t orelse return prog.errno.EINVAL;
    if (c.task_chkcap(task_ptr.t_taskid, c.CAP_DISKADMIN) != 0) return prog.errno.EPERM;
    return c.sys_umount(&msg[0].path);
}

// ---------------------------------------------------------------------------
// Step 2.10: structural code (boot, shutdown, debug, init, main)
// ---------------------------------------------------------------------------

pub export fn fs_boot(_: ?*c.struct_task, msg: [*c]c.struct_msg) callconv(.c) c_int {
    if (c.task_chkcap(msg[0].hdr.task, c.CAP_PROTSERV) != 0) return prog.errno.EPERM;

    var execobj: c.object_t = undefined;
    if (c.object_lookup("!exec", &execobj) != 0) c.sys_panic("fs: no exec found");
    var bm: c.struct_bind_msg = std.mem.zeroes(c.struct_bind_msg);
    bm.hdr.code = c.EXEC_BINDCAP;
    const src = "/boot/fs";
    @memcpy(bm.path[0..src.len], src);
    bm.path[src.len] = 0;
    _ = c.msg_send(execobj, &bm, @sizeOf(c.struct_bind_msg));

    var procobj: c.object_t = undefined;
    if (c.object_lookup("!proc", &procobj) != 0) c.sys_panic("fs: no proc found");
    var m: c.struct_msg = std.mem.zeroes(c.struct_msg);
    m.hdr.code = c.PS_REGISTER;
    _ = c.msg_send(procobj, &m, @sizeOf(c.struct_msg));

    return 0;
}

pub export fn fs_shutdown(_: ?*c.struct_task, _: [*c]c.struct_msg) callconv(.c) c_int {
    return 0;
}

pub export fn fs_noop() callconv(.c) c_int {
    return 0;
}

pub export fn fs_debug(_: ?*c.struct_task, _: [*c]c.struct_msg) callconv(.c) c_int {
    c.dprintf("<File System Server>\n");
    if (@hasDecl(c, "task_dump")) c.task_dump();
    if (@hasDecl(c, "vnode_dump")) c.vnode_dump();
    if (@hasDecl(c, "mount_dump")) c.mount_dump();
    return 0;
}

const vfs_conf = @import("vfs_conf.zig");
extern fn get_vfssw() callconv(.c) [*c]const c.struct_vfssw;

export fn vfs_init() void {
    c.task_init();
    c.bio_init();
    c.vnode_init();

    var entry: [*c]const c.struct_vfssw = get_vfssw();
    while (entry[0].vs_name != null) {
        const init_fn = entry[0].vs_init orelse {
            entry += 1;
            continue;
        };
        _ = init_fn();
        entry += 1;
    }

    var msg: c.struct_msg = std.mem.zeroes(c.struct_msg);
    msg.hdr.task = c.task_self();
    _ = fs_register(null, &msg);
}

export fn run_thread(entry: *const fn () callconv(.c) void) callconv(.c) c_int {
    const self: c.task_t = c.task_self();
    var t: c.thread_t = 0;
    var err: c_int = c.thread_create(self, &t);
    if (err != 0) return err;
    var stack: [*c]u8 = undefined;
    err = c.vm_allocate(self, @ptrCast(&stack), c.DFLSTKSZ, 1);
    if (err != 0) return err;

    // sp = (void*)((u_long)stack + DFLSTKSZ - sizeof(u_long) * 3)
    const stack_ulong: usize = @intFromPtr(stack);
    const sp_addr: usize = stack_ulong + c.DFLSTKSZ - @sizeOf(usize) * 3;
    const sp: [*c]u8 = @ptrFromInt(sp_addr);
    const entry_fn: *const fn () callconv(.c) void = entry;
    err = c.thread_load(t, entry_fn, sp);
    if (err != 0) return err;
    return c.thread_resume(t);
}

export fn exception_handler(_: c_int) callconv(.c) void {
    c.exception_return();
}

// Dispatcher loop — provided by _main.c (fs_thread). Declared extern here.
extern fn fs_thread() callconv(.c) void;

pub export fn main(_: c_int, _: [*c][*c]u8) callconv(.c) c_int {
    _ = c.sys_log("Starting file system server\n");
    _ = c.thread_setpri(c.thread_self(), c.PRI_FS);
    _ = c.exception_setup(exception_handler);
    vfs_init();

    const fsobj_ptr = get_fsobj();
    if (c.object_create("!fs", fsobj_ptr) != 0)
        c.sys_panic("VFS: fail to create object");

    var i: c_int = c.CONFIG_FS_THREADS;
    while (i - 1 > 0) : (i -= 1) {
        if (run_thread(fs_thread) != 0) {
            c.sys_panic("VFS: failed to create thread");
            return 0;
        }
    }
    fs_thread();
    c.sys_panic("VFS: exit!");
    return 0;
}

const std = @import("std");

extern fn get_fsobj() callconv(.c) *c.object_t;
