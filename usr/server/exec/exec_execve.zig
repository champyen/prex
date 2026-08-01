const ffi = @import("exec_ffi.zig");
const elf = @import("exec_elf.zig");
const cap = @import("exec_cap.zig");
const builtin = @import("builtin");

const is_riscv = builtin.cpu.arch == .riscv32 or builtin.cpu.arch == .riscv64;
const is_arm = builtin.cpu.arch == .arm;

const MAX_PATH: comptime_int = @intCast(ffi.task.prex.PATH_MAX);

/// Wrap a kernel syscall failure (nonzero errno) as a Zig error, so the
/// exported entry point can convert it back via toCError().
fn checkErrno(val: c_int) !void {
    if (val != 0) return ffi.fromCError(val);
}

inline fn spAlign(p: usize) usize {
    if (is_riscv) {
        return p & ~@as(usize, 15);
    } else {
        return p & ~@as(usize, @intCast(ffi.task.prex._ALIGNBYTES));
    }
}

fn convPath(cwd: [*c]const u8, path: [*c]u8, full: [*c]u8) elf.ExecError!void {
    // NUL-terminate for safety
    path[MAX_PATH - 1] = 0;

    const len: usize = ffi.prog.string.strlen(path);
    if (len >= MAX_PATH) return error.NameTooLong;
    if (ffi.prog.string.strlen(cwd) + len >= MAX_PATH) return error.NameTooLong;

    var src: [*]u8 = path;
    var tgt: [*]u8 = full;
    const end: [*]u8 = src + len;

    if (path[0] == '/') {
        tgt[0] = src[0];
        tgt += 1;
        src += 1;
    } else {
        _ = ffi.prog.string.strlcpy(full, cwd, MAX_PATH);
        const cwd_len = ffi.prog.string.strlen(cwd);
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

        if (ffi.prog.string.strcmp(@ptrCast(src), "..") == 0) {
            if (@intFromPtr(tgt) > @intFromPtr(full) + 1) {
                tgt -= 1;
                while (@intFromPtr(tgt) > @intFromPtr(full) and (tgt - 1)[0] != '/') {
                    tgt -= 1;
                }
            }
        } else if (ffi.prog.string.strcmp(@ptrCast(src), ".") == 0) {
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
}

/// FFI wrapper for the C build_args implementation in exec_globals.c.
/// The C version is used because the Zig compiler inserts additional safety
/// padding for the out-of-bounds write `argv[argc+1] = NULL` (a deliberate
/// C-ABI trick shared with envp[0]). To preserve binary compatibility with
/// the existing C-compiled executables, we call the C implementation directly.
fn buildArgs(
    task: ffi.task.prex.task_t,
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

fn notifyServer(org_task: ffi.task.prex.task_t, new_task: ffi.task.prex.task_t, stack: ?*anyopaque) void {
    var m: ffi.Msg = undefined;
    var fsobj: ffi.task.prex.object_t = undefined;
    var procobj: ffi.task.prex.object_t = undefined;

    if (ffi.task.prex.object_lookup(ffi.global.get_fs_obj_name(), &fsobj) != 0) return;
    if (ffi.task.prex.object_lookup(ffi.global.get_proc_obj_name(), &procobj) != 0) return;

    // Notify to file system server
    while (true) {
        m.hdr.code = ffi.prog.ipc.fs.FS_EXEC;
        m.data[0] = @bitCast(@as(u32, @truncate(org_task)));
        m.data[1] = @bitCast(@as(u32, @truncate(new_task)));
        const err = ffi.task.prex.msg_send(fsobj, @ptrCast(&m), @sizeOf(ffi.Msg));
        if (err != ffi.prog.errno.EINTR) break;
    }

    // Notify to process server
    while (true) {
        m.hdr.code = ffi.prog.ipc.proc.PS_EXEC;
        m.data[0] = @bitCast(@as(u32, @truncate(org_task)));
        m.data[1] = @bitCast(@as(u32, @truncate(new_task)));
        m.data[2] = @bitCast(@as(u32, @truncate(@intFromPtr(stack))));
        const err = ffi.task.prex.msg_send(procobj, @ptrCast(&m), @sizeOf(ffi.Msg));
        if (err != ffi.prog.errno.EINTR) break;
    }
}

fn doExecve(msg: *ffi.ExecMsg) !void {
    const old_task: ffi.task.prex.task_t = msg.hdr.task;
    var new_task: ffi.task.prex.task_t = undefined;
    var t: ffi.task.prex.thread_t = undefined;
    var stack: ?*anyopaque = undefined;
    var sp: ?*anyopaque = undefined;
    var path: [MAX_PATH]u8 = undefined;
    var exec: ffi.Exec = undefined;

    // Make it full path
    try convPath(@ptrCast(&msg.cwd), @ptrCast(&msg.path), @ptrCast(&path));

    // Check permission
    if (ffi.prog.unistd.access(@ptrCast(&path), ffi.prog.unistd.X_OK) == -1) {
        return ffi.fromCError(ffi.prog.errno.errno);
    }

    exec.init(@ptrCast(&path), null);

    // Read file header and find the matching loader (follows #! interpreters)
    const ldr = try exec.findLoader();

    // Check file permission again (the loader may have rewritten the path)
    if (ffi.prog.unistd.access(exec.path, ffi.prog.unistd.X_OK) == -1) {
        return ffi.fromCError(ffi.prog.errno.errno);
    }

    // Suspend old task
    try checkErrno(ffi.task.prex.task_suspend(old_task));

    // Create new task
    try checkErrno(ffi.task.prex.task_create(old_task, ffi.task.prex.VM_NEW, &new_task));
    errdefer _ = ffi.task.prex.task_terminate(new_task);

    if (exec.path[0] != 0) {
        _ = ffi.task.prex.task_setname(new_task, ffi.libgen.basename(exec.path));
    }

    // Bind capabilities
    cap.bind_cap(exec.path, new_task);

    try checkErrno(ffi.task.prex.thread_create(new_task, &t));
    errdefer _ = ffi.task.prex.thread_terminate(t);

    // Allocate stack and build arguments on it
    try checkErrno(ffi.task.prex.vm_allocate(new_task, &stack, ffi.task.prex.DFLSTKSZ, 1));
    errdefer _ = ffi.task.prex.vm_free(new_task, stack);

    try checkErrno(buildArgs(new_task, stack, exec.path, msg, exec.xarg1, exec.xarg2, &sp));

    // Load file image
    exec.task = new_task;
    try exec.load(ldr);

    if (comptime is_arm) {
        try checkErrno(ffi.task.prex.thread_setup(t, @ptrFromInt(@as(usize, exec.entry)), sp, exec.gp));
    } else {
        try checkErrno(ffi.task.prex.thread_load(t, @ptrFromInt(@as(usize, exec.entry)), sp));
    }

    // Notify to servers
    notifyServer(old_task, new_task, stack);

    // Terminate old task
    _ = ffi.task.prex.task_terminate(old_task);

    // Set him running
    _ = ffi.task.prex.thread_setpri(t, ffi.task.prex.PRI_DEFAULT);
    _ = ffi.task.prex.thread_resume(t);
}

pub export fn exec_execve(msg: *ffi.ExecMsg) callconv(.c) c_int {
    return ffi.catchToCError(doExecve(msg));
}
