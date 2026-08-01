const ffi = @import("exec_ffi.zig");

pub fn bind_cap(path: [*c]const u8, task: ffi.task.prex.task_t) void {
    const map = ffi.global.cap_table_get();
    var cap: ffi.task.prex.cap_t = 0;

    var i: usize = 0;
    while (map[i].c_path != null) : (i += 1) {
        if (ffi.prog.string.strncmp(path, map[i].c_path, ffi.task.prex.PATH_MAX) == 0) {
            cap = map[i].c_capset;
            break;
        }
    }

    if (cap != 0) {
        const err = ffi.task.prex.task_setcap(task, cap);
        if (err != 0) {
            ffi.task.prex.sys_panic("exec: no SETPCAP capability");
        }
    }
}

pub export fn exec_bindcap(msg: *ffi.BindMsg) callconv(.c) c_int {
    const task = msg.hdr.task;
    const err = ffi.task.prex.task_chkcap(task, ffi.task.prex.CAP_PROTSERV);
    if (err != 0) {
        return ffi.prog.errno.EPERM;
    }

    bind_cap(&msg.path, task);
    return 0;
}
