const ffi = @import("exec_ffi.zig");

pub export fn exec_null(msg: *ffi.Msg) callconv(.c) c_int {
    _ = msg;
    return 0;
}

pub export fn exec_boot(msg: *ffi.Msg) callconv(.c) c_int {
    if (ffi.raw.task_chkcap(msg.hdr.task, ffi.raw.CAP_PROTSERV) != 0) {
        return ffi.Errno.EPERM;
    }
    register_process();
    _ = ffi.raw.fslib_init();
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
    var obj: ffi.raw.object_t = undefined;

    if (ffi.raw.object_lookup(ffi.global.get_proc_obj_name(), &obj) != 0) {
        ffi.raw.sys_panic(ffi.global.get_no_proc_msg());
    }

    m.hdr.code = ffi.raw.PS_REGISTER;
    _ = ffi.raw.msg_send(obj, @ptrCast(&m), @sizeOf(ffi.Msg));
}

pub export fn main(argc: c_int, argv: ?[*]?[*:0]u8) callconv(.c) c_int {
    _ = argc;
    _ = argv;

    _ = ffi.raw.thread_setpri(ffi.raw.thread_self(), ffi.raw.PRI_EXEC);

    ffi.raw.bind_cap(@constCast(ffi.global.get_exec_path()), ffi.raw.task_self());

    ffi.global.setup_exec_exception();

    exec_init();

    var obj: ffi.raw.object_t = undefined;
    if (ffi.raw.object_create(ffi.global.get_exec_obj_name(), &obj) != 0) {
        ffi.raw.sys_panic(ffi.global.get_create_obj_fail_msg());
    }

    const msg_ptr = ffi.raw.malloc(ffi.raw.MAX_EXECMSG) orelse return 1;
    const msg: *ffi.Msg = @ptrCast(@alignCast(msg_ptr));

    while (true) {
        if (ffi.raw.msg_receive(obj, @ptrCast(msg), ffi.raw.MAX_EXECMSG) != 0) continue;

        const err = ffi.global.dispatch_msg(msg.hdr.code, msg);
        msg.hdr.status = err;
        _ = ffi.raw.msg_reply(obj, @ptrCast(msg), ffi.raw.MAX_EXECMSG);
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
