const std = @import("std");

const c = @import("c").c;
const ffi = @import("ffi");
const hal = ffi.hal;
const lib = ffi.lib;
const smp = ffi.smp;
const sched = ffi.sched;
const page = ffi.page;
const kmem = ffi.kmem;
const vm = ffi.vm;
const deadlock = ffi.deadlock;
const task = ffi.task;
const thread = ffi.thread;
const timer = ffi.timer;
const object = ffi.object;
const msg = ffi.msg;
const irq = ffi.irq;
const device = ffi.device;
const exception = ffi.exception;

extern fn wrap_get_version() callconv(.c) [*c]const u8;
extern fn wrap_get_machine() callconv(.c) [*c]const u8;
extern fn wrap_get_build_date() callconv(.c) [*c]const u8;

fn main() callconv(.c) c_int {
    if (@hasDecl(c, "CONFIG_SMP")) {
        smp.init_early();
    }

    sched.lock();
    hal.diag_init();
    _ = lib.printf("Prex+ version %s for %s (%s)\n", wrap_get_version(), wrap_get_machine(), wrap_get_build_date());
    _ = lib.printf("Copyright (c) 2005-2009 Kohsuke Ohtani\n");
    _ = lib.printf("Copyright (c) 2021      Champ Yen (champ.yen@gmail.com)\n");

    page.init();
    kmem.init();

    hal.machine_startup();

    vm.init();
    deadlock.init();
    task.init();
    thread.init();
    sched.init();
    exception.init();
    timer.init();
    object.init();
    msg.init();

    irq.init();
    hal.clock_init();
    device.init();

    task.bootstrap();

    if (@hasDecl(c, "CONFIG_SMP")) {
        smp.start_aps();
        smp.activate();
    }

    sched.unlock();
    thread.idle();

    return 0;
}

comptime {
    @export(&main, .{ .name = "main", .linkage = .strong });
}
