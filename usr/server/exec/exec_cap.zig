const ffi = @import("exec_ffi.zig");

pub export fn bind_cap(path: [*c]const u8, task: ffi.raw.task_t) callconv(.c) void {
    const map = ffi.global.cap_table_get();
    var cap: ffi.raw.cap_t = 0;

    var i: usize = 0;
    while (map[i].c_path != null) : (i += 1) {
        if (ffi.raw.strncmp(path, map[i].c_path, ffi.raw.PATH_MAX) == 0) {
            cap = map[i].c_capset;
            break;
        }
    }

    if (cap != 0) {
        const err = ffi.raw.task_setcap(task, cap);
        if (err != 0) {
            ffi.raw.sys_panic("exec: no SETPCAP capability");
        }
    }
}

pub export fn exec_bindcap(msg: *ffi.BindMsg) callconv(.c) c_int {
    const task = msg.hdr.task;
    const err = ffi.raw.task_chkcap(task, ffi.raw.CAP_PROTSERV);
    if (err != 0) {
        return ffi.Errno.EPERM;
    }

    bind_cap(&msg.path, task);
    return 0;
}
