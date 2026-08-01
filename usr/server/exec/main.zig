const ffi = @import("exec_ffi.zig");
const execve = @import("exec_execve.zig");
const elf = @import("exec_elf.zig");
const script = @import("exec_script.zig");
const cap = @import("exec_cap.zig");

pub export fn exec_null(msg: *ffi.Msg) callconv(.c) c_int {
    _ = msg;
    return 0;
}

pub export fn exec_boot(msg: *ffi.Msg) callconv(.c) c_int {
    if (ffi.task.prex.task_chkcap(msg.hdr.task, ffi.task.prex.CAP_PROTSERV) != 0) {
        return ffi.prog.errno.EPERM;
    }
    register_process();
    _ = ffi.prog.unistd.fslib_init();
    return 0;
}

pub export fn exec_debug(msg: *ffi.Msg) callconv(.c) c_int {
    _ = msg;
    return 0;
}

pub export fn exec_shutdown(msg: *ffi.Msg) callconv(.c) c_int {
    _ = msg;
    return 0;
}

fn register_process() void {
    var m: ffi.Msg = undefined;
    var obj: ffi.task.prex.object_t = undefined;

    if (ffi.task.prex.object_lookup(ffi.global.get_proc_obj_name(), &obj) != 0) {
        ffi.task.prex.sys_panic(ffi.global.get_no_proc_msg());
    }

    m.hdr.code = ffi.prog.ipc.proc.PS_REGISTER;
    _ = ffi.task.prex.msg_send(obj, @ptrCast(&m), @sizeOf(ffi.Msg));
}

pub export fn main(argc: c_int, argv: ?[*]?[*:0]u8) callconv(.c) c_int {
    _ = argc;
    _ = argv;

    _ = ffi.task.prex.thread_setpri(ffi.task.prex.thread_self(), ffi.task.prex.PRI_EXEC);

    cap.bind_cap(ffi.global.get_exec_path(), ffi.task.prex.task_self());

    ffi.global.setup_exec_exception();

    exec_init();

    var obj: ffi.task.prex.object_t = undefined;
    if (ffi.task.prex.object_create(ffi.global.get_exec_obj_name(), &obj) != 0) {
        ffi.task.prex.sys_panic(ffi.global.get_create_obj_fail_msg());
    }

    const msg_ptr = ffi.prog.stdlib.malloc(ffi.prog.ipc.exec.MAX_EXECMSG) orelse return 1;
    const msg: *ffi.Msg = @ptrCast(@alignCast(msg_ptr));

    while (true) {
        if (ffi.task.prex.msg_receive(obj, @ptrCast(msg), ffi.prog.ipc.exec.MAX_EXECMSG) != 0) continue;

        const err = ffi.global.dispatch_msg(msg.hdr.code, msg);
        msg.hdr.status = err;
        _ = ffi.task.prex.msg_reply(obj, @ptrCast(msg), ffi.prog.ipc.exec.MAX_EXECMSG);
    }
}

fn exec_init() void {
    const n = ffi.global.nloader_get();
    const table = ffi.global.loader_table_get();
    var i: c_int = 0;
    while (i < n) : (i += 1) {
        table[@intCast(i)].el_init.?();
    }
}

comptime {
    _ = execve;
    _ = elf;
    _ = script;
    _ = cap;
}
