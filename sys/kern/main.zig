const std = @import("std");

const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});

extern fn wrap_get_version() callconv(.c) [*c]const u8;
extern fn wrap_get_machine() callconv(.c) [*c]const u8;
extern fn wrap_get_build_date() callconv(.c) [*c]const u8;
extern fn smp_init_early() callconv(.c) void;
extern fn smp_start_aps() callconv(.c) void;
extern fn smp_activate() callconv(.c) void;

fn main() callconv(.c) c_int {
    if (@hasDecl(c, "CONFIG_SMP")) {
        smp_init_early();
    }

    c.sched_lock();
    c.diag_init();
    _ = c.printf("Prex+ version %s for %s (%s)\n", wrap_get_version(), wrap_get_machine(), wrap_get_build_date());
    _ = c.printf("Copyright (c) 2005-2009 Kohsuke Ohtani\n");
    _ = c.printf("Copyright (c) 2021      Champ Yen (champ.yen@gmail.com)\n");

    c.page_init();
    c.kmem_init();

    c.machine_startup();

    c.vm_init();
    c.deadlock_init();
    c.task_init();
    c.thread_init();
    c.sched_init();
    c.exception_init();
    c.timer_init();
    c.object_init();
    c.msg_init();

    c.irq_init();
    c.clock_init();
    c.device_init();

    c.task_bootstrap();

    if (@hasDecl(c, "CONFIG_SMP")) {
        smp_start_aps();
        smp_activate();
    }

    c.sched_unlock();
    c.thread_idle();

    return 0;
}

comptime {
    @export(&main, .{ .name = "main", .linkage = .strong });
}
