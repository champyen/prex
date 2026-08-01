const ffi = @import("exec_ffi.zig");
const c = ffi.raw;
const builtin = @import("builtin");

const is_riscv = builtin.cpu.arch == .riscv32 or builtin.cpu.arch == .riscv64;
const is_arm = builtin.cpu.arch == .arm;

const HEADER_SIZE: c_int = 512;
const MAX_PATH: comptime_int = @intCast(c.PATH_MAX);

extern fn bind_cap(path: [*c]const u8, task: c.task_t) callconv(.c) void;

inline fn spAlign(p: usize) usize {
    if (is_riscv) {
        return p & ~@as(usize, 15);
    } else {
        return p & ~@as(usize, @intCast(c._ALIGNBYTES));
    }
}

fn convPath(cwd: [*c]const u8, path: [*c]u8, full: [*c]u8) c_int {
    // NUL-terminate for safety
    path[MAX_PATH - 1] = 0;

    const len: usize = c.strlen(path);
    if (len >= MAX_PATH) return c.ENAMETOOLONG;
    if (c.strlen(cwd) + len >= MAX_PATH) return c.ENAMETOOLONG;

    var src: [*]u8 = path;
    var tgt: [*]u8 = full;
    const end: [*]u8 = src + len;

    if (path[0] == '/') {
        tgt[0] = src[0];
        tgt += 1;
        src += 1;
    } else {
        _ = c.strlcpy(full, cwd, MAX_PATH);
        const cwd_len = c.strlen(cwd);
        tgt += cwd_len;
        if (cwd_len > 1 and path[0] != '.') {
            tgt[0] = '/';
            tgt += 1;
        }
    }

    while (src[0] != 0) {
        var p: [*]u8 = src;
        while (p[0] != '/' and p[0] != 0) : (p += 1) {}
        const saved = p[0];
        p[0] = 0;

        if (c.strcmp(@ptrCast(src), "..") == 0) {
            if (@intFromPtr(tgt) > @intFromPtr(full) + 1) {
                tgt -= 1;
                while (@intFromPtr(tgt) > @intFromPtr(full) and (tgt - 1)[0] != '/') {
                    tgt -= 1;
                }
            }
        } else if (c.strcmp(@ptrCast(src), ".") == 0) {
            // Ignore "."
        } else {
            while (src[0] != 0) {
                tgt[0] = src[0];
                tgt += 1;
                src += 1;
            }
        }

        p[0] = saved;

        if (@intFromPtr(p) == @intFromPtr(end)) break;
        if (@intFromPtr(tgt) > @intFromPtr(full) and (tgt - 1)[0] != '/') {
            tgt[0] = '/';
            tgt += 1;
        }
        src = p + 1;
    }
    tgt[0] = 0;
    return 0;
}

/// FFI wrapper for the C build_args implementation in exec_globals.c.
/// The C version is used because the Zig compiler inserts additional safety
/// padding for the out-of-bounds write `argv[argc+1] = NULL` (a deliberate
/// C-ABI trick shared with envp[0]). To preserve binary compatibility with
/// the existing C-compiled executables, we call the C implementation directly.
fn buildArgs(
    task: c.task_t,
    stack: ?*anyopaque,
    path: [*c]const u8,
    msg: *ffi.ExecMsg,
    xarg1: ?[*c]const u8,
    xarg2: ?[*c]const u8,
    new_sp: *?*anyopaque,
) c_int {
    const xa1: [*c]u8 = if (xarg1) |p| @constCast(p) else @ptrFromInt(0);
    const xa2: [*c]u8 = if (xarg2) |p| @constCast(p) else @ptrFromInt(0);
    return ffi.global.build_args(
        task,
        stack,
        @constCast(path),
        msg,
        xa1,
        xa2,
        new_sp,
    );
}

fn notifyServer(org_task: c.task_t, new_task: c.task_t, stack: ?*anyopaque) void {
    var m: ffi.Msg = undefined;
    var fsobj: c.object_t = undefined;
    var procobj: c.object_t = undefined;

    if (c.object_lookup(ffi.global.get_fs_obj_name(), &fsobj) != 0) return;
    if (c.object_lookup(ffi.global.get_proc_obj_name(), &procobj) != 0) return;

    // Notify to file system server
    while (true) {
        m.hdr.code = c.FS_EXEC;
        m.data[0] = @bitCast(@as(u32, @truncate(org_task)));
        m.data[1] = @bitCast(@as(u32, @truncate(new_task)));
        const err = c.msg_send(fsobj, @ptrCast(&m), @sizeOf(ffi.Msg));
        if (err != c.EINTR) break;
    }

    // Notify to process server
    while (true) {
        m.hdr.code = c.PS_EXEC;
        m.data[0] = @bitCast(@as(u32, @truncate(org_task)));
        m.data[1] = @bitCast(@as(u32, @truncate(new_task)));
        m.data[2] = @bitCast(@as(u32, @truncate(@intFromPtr(stack))));
        const err = c.msg_send(procobj, @ptrCast(&m), @sizeOf(ffi.Msg));
        if (err != c.EINTR) break;
    }
}

noinline fn readHeader(path: [*c]const u8) c_int {
    const fd = c.open(path, c.O_RDONLY);
    if (fd == -1) return c.ENOENT;

    var st: c.struct_stat = undefined;
    if (c.fstat(fd, &st) == -1) {
        _ = c.close(fd);
        return c.EIO;
    }
    if ((st.st_mode & 0xF000) != 0x8000) {
        _ = c.close(fd);
        return c.EACCES; // must be regular file
    }

    ffi.global.hdrbuf_zero();
    const buf = ffi.global.hdrbuf_get();
    if (c.read(fd, buf, HEADER_SIZE) == -1) {
        _ = c.close(fd);
        return c.EIO;
    }
    _ = c.close(fd);
    return 0;
}

pub export fn exec_execve(msg: *ffi.ExecMsg) callconv(.c) c_int {
    var ldr: ?*ffi.ExecLoader = null;
    var error_code: c_int = 0;
    const old_task: c.task_t = msg.hdr.task;
    var new_task: c.task_t = undefined;
    var t: c.thread_t = undefined;
    var stack: ?*anyopaque = undefined;
    var sp: ?*anyopaque = undefined;
    var path: [MAX_PATH]u8 = undefined;
    var exec: ffi.Exec = undefined;
    var rc: c_int = 0;

    // Make it full path
    error_code = convPath(@ptrCast(&msg.cwd), @ptrCast(&msg.path), @ptrCast(&path));
    if (error_code != 0) return error_code;

    // Check permission
    if (c.access(@ptrCast(&path), c.X_OK) == -1) {
        return c.errno;
    }

    exec.path = @ptrCast(&path);
    exec.header = ffi.global.hdrbuf_get();
    exec.xarg1 = null;
    exec.xarg2 = null;

    // Indirect exec loop (handles #! script interpreters)
    var attempts: u32 = 0;
    while (true) : (attempts += 1) {
        if (attempts > 10) return c.ENOEXEC;

        // Read file header
        error_code = readHeader(exec.path);
        if (error_code != 0) return error_code;

        // Find file loader
        rc = c.PROBE_ERROR;
        const loader_table = ffi.global.loader_table_get();
        const nloader = ffi.global.nloader_get();
        var i: c_int = 0;
        while (i < nloader) : (i += 1) {
            ldr = &loader_table[@intCast(i)];
            rc = ldr.?.el_probe.?(&exec);
            if (rc != c.PROBE_ERROR) break;
        }
        if (rc == c.PROBE_ERROR) return c.ENOEXEC;

        // Check file header again if indirect case
        if (rc == c.PROBE_INDIRECT) continue;
        break;
    }

    // Check file permission
    if (c.access(exec.path, c.X_OK) == -1) {
        return c.errno;
    }

    // Suspend old task
    error_code = c.task_suspend(old_task);
    if (error_code != 0) return error_code;

    // Create new task
    error_code = c.task_create(old_task, c.VM_NEW, &new_task);
    if (error_code != 0) return error_code;

    if (exec.path[0] != 0) {
        _ = c.task_setname(new_task, c.basename(exec.path));
    }

    // Bind capabilities
    bind_cap(exec.path, new_task);

    error_code = c.thread_create(new_task, &t);
    if (error_code != 0) {
        _ = c.task_terminate(new_task);
        return error_code;
    }

    // Allocate stack and build arguments on it
    error_code = c.vm_allocate(new_task, &stack, c.DFLSTKSZ, 1);
    if (error_code != 0) {
        _ = c.thread_terminate(t);
        _ = c.task_terminate(new_task);
        return error_code;
    }
    error_code = buildArgs(new_task, stack, exec.path, msg, exec.xarg1, exec.xarg2, &sp);
    if (error_code != 0) {
        _ = c.vm_free(new_task, stack);
        _ = c.thread_terminate(t);
        _ = c.task_terminate(new_task);
        return error_code;
    }

    // Load file image
    exec.task = new_task;
    error_code = ldr.?.el_load.?(&exec);
    if (error_code != 0) {
        _ = c.vm_free(new_task, stack);
        _ = c.thread_terminate(t);
        _ = c.task_terminate(new_task);
        return error_code;
    }

    if (is_arm) {
        const gp: ?*anyopaque = if (comptime @hasField(ffi.Exec, "gp")) exec.gp else null;
        error_code = c.thread_setup(t, @ptrFromInt(@as(usize, exec.entry)), sp, gp);
    } else {
        error_code = c.thread_load(t, @ptrFromInt(@as(usize, exec.entry)), sp);
    }
    if (error_code != 0) {
        _ = c.vm_free(new_task, stack);
        _ = c.thread_terminate(t);
        _ = c.task_terminate(new_task);
        return error_code;
    }

    // Notify to servers
    notifyServer(old_task, new_task, stack);

    // Terminate old task
    _ = c.task_terminate(old_task);

    // Set him running
    _ = c.thread_setpri(t, c.PRI_DEFAULT);
    _ = c.thread_resume(t);

    return 0;
}
