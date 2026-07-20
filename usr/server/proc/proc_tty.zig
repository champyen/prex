const ffi = @import("ffi.zig");
const prog = @import("prog");
const task = @import("task");
const sig_ops = @import("proc_sig.zig");

fn tty_signal(sig: c_int) void {
    var pgid: task.prex.pid_t = 0;
    if (task.prex.device_ioctl(ffi.global.get_ttydev(), prog.termios.TIOCGPGRP, &pgid) != 0) {
        return;
    }
    _ = sig_ops.kill_pg(pgid, sig) catch {};
}

pub fn exception_handler(sig: c_int) callconv(.c) void {
    switch (sig) {
        prog.signal.SIGINT,
        prog.signal.SIGQUIT,
        prog.signal.SIGTSTP,
        prog.signal.SIGTTIN,
        prog.signal.SIGTTOU,
        prog.signal.SIGINFO,
        prog.signal.SIGWINCH,
        prog.signal.SIGIO,
        => {
            if (ffi.global.get_ttydev() != task.prex.NODEV) {
                tty_signal(sig);
            }
        },
        else => {},
    }
    task.prex.exception_return();
}

pub fn tty_init() void {
    ffi.global.setup_tty_exception();

    var dev: task.prex.device_t = 0;
    if (task.prex.device_open(ffi.global.get_tty_name(), 0, &dev) != 0) {
        ffi.global.set_ttydev(task.prex.NODEV);
    } else {
        ffi.global.set_ttydev(dev);
        var self = task.prex.task_self();
        _ = task.prex.device_ioctl(dev, prog.termios.TIOCSETSIGT, @ptrCast(&self));
    }
}

comptime {
    @export(&exception_handler, .{ .name = "exception_handler", .linkage = .strong });
}
