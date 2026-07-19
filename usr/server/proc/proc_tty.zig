const std = @import("std");
const c = @cImport({
    @cInclude("sys/prex.h");
    @cInclude("ipc/proc.h");
    @cInclude("sys/list.h");
    @cInclude("unistd.h");
    @cInclude("errno.h");
    @cInclude("stdlib.h");
    @cInclude("signal.h");
    @cInclude("termios.h");
    @cInclude("usr/server/proc/proc.h");
});

extern fn get_ttydev() c.device_t;
extern fn set_ttydev(c.device_t) void;
extern fn setup_tty_exception() void;
extern fn get_tty_name() [*c]const u8;

const TIOCGPGRP = 0x40047477;
const TIOCSETSIGT = 0x800474c8;

fn tty_signal(sig: c_int) void {
    var pgid: c.pid_t = 0;
    if (c.device_ioctl(get_ttydev(), TIOCGPGRP, &pgid) != 0) {
        return;
    }
    _ = c.kill_pg(pgid, sig);
}

pub fn exception_handler(sig: c_int) callconv(.c) void {
    switch (sig) {
        c.SIGINT,
        c.SIGQUIT,
        c.SIGTSTP,
        c.SIGTTIN,
        c.SIGTTOU,
        c.SIGINFO,
        c.SIGWINCH,
        c.SIGIO,
        => {
            if (get_ttydev() != c.NODEV) {
                tty_signal(sig);
            }
        },
        else => {},
    }
    c.exception_return();
}

pub fn tty_init() callconv(.c) void {
    setup_tty_exception();

    var dev: c.device_t = 0;
    if (c.device_open(get_tty_name(), 0, &dev) != 0) {
        set_ttydev(c.NODEV);
    } else {
        set_ttydev(dev);
        var self = c.task_self();
        _ = c.device_ioctl(dev, TIOCSETSIGT, @ptrCast(&self));
    }
}

comptime {
    @export(&tty_init, .{ .name = "tty_init", .linkage = .strong });
    @export(&exception_handler, .{ .name = "exception_handler", .linkage = .strong });
}
