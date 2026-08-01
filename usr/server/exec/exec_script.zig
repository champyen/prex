const ffi = @import("exec_ffi.zig");

pub export fn script_load(exec: *ffi.Exec) callconv(.c) c_int {
    _ = exec;
    return 0;
}

pub export fn script_probe(exec: *ffi.Exec) callconv(.c) c_int {
    const hdrstr: [*]u8 = @ptrCast(exec.header orelse return ffi.PROBE_ERROR);

    // Check magic header
    if ((hdrstr[0] != '#') or (hdrstr[1] != '!')) {
        return ffi.PROBE_ERROR;
    }

    // Strip spaces before the interpreter name
    var i: usize = 2;
    while (hdrstr[i] == ' ' or hdrstr[i] == '\t') : (i += 1) {}
    if (hdrstr[i] == 0) {
        return ffi.PROBE_ERROR;
    }

    // Pick up interpreter name
    const name: [*]u8 = hdrstr + i;
    while (hdrstr[i] != 0 and hdrstr[i] != ' ' and hdrstr[i] != '\t') : (i += 1) {}
    const has_next = hdrstr[i] != 0;
    hdrstr[i] = 0;
    if (has_next) {
        i += 1;
    }

    const interp = ffi.global.get_script_interp();
    const intarg = ffi.global.get_script_intarg();
    const script = ffi.global.get_script_name();

    if (ffi.prog.string.strncmp(name, "/bin/sh", ffi.task.prex.PATH_MAX) == 0) {
        _ = ffi.prog.string.strlcpy(interp, "/boot/cmdbox", ffi.task.prex.PATH_MAX);
        _ = ffi.prog.string.strlcpy(intarg, "sh", ffi.task.prex.LINE_MAX);
        exec.xarg1 = @ptrCast(intarg);
        exec.xarg2 = @ptrCast(script);
    } else {
        _ = ffi.prog.string.strlcpy(interp, name, ffi.task.prex.PATH_MAX);
        exec.xarg1 = @ptrCast(intarg);
        exec.xarg2 = null;
    }
    _ = ffi.prog.string.strlcpy(script, exec.path, ffi.task.prex.LINE_MAX);
    exec.path = @ptrCast(interp);

    return ffi.PROBE_INDIRECT;
}

pub export fn script_init() callconv(.c) void {}
