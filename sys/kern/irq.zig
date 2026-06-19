const std = @import("std");

const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});

var IST_NONE: ?*const fn (?*anyopaque) callconv(.c) void = undefined;

var irq_table = std.mem.zeroes([c.MAXIRQS]?*c.struct_irq);

inline fn ISTPRI(pri: c_int) c_int {
    return c.PRI_IST + (c.IPL_HIGH - pri);
}

fn irq_thread(arg: ?*anyopaque) callconv(.c) void {
    const irq: *c.struct_irq = @ptrCast(@alignCast(arg.?));
    const fn_ptr = irq.ist;
    const data = irq.data;

    _ = c.splhigh();

    while (true) {
        if (irq.istreq <= 0) {
            _ = c.sched_sleep(@as(?*c.struct_event, @ptrCast(&irq.istevt)));
        }
        irq.istreq -= 1;
        std.debug.assert(irq.istreq >= 0);

        _ = c.spl0();
        fn_ptr.?(data);
        _ = c.splhigh();
    }
}

pub fn irq_attach(vector: c_int, pri: c_int, shared: c_int, isr: ?*const fn (?*anyopaque) callconv(.c) c_int, ist: ?*const fn (?*anyopaque) callconv(.c) void, data: ?*anyopaque) callconv(.c) ?*c.struct_irq {
    std.debug.assert(isr != null);

    c.sched_lock();
    const irq_mem = c.kmem_alloc(@sizeOf(c.struct_irq));
    if (irq_mem == null) {
        @panic("irq_attach");
    }
    const irq: *c.struct_irq = @ptrCast(@alignCast(irq_mem));

    _ = c.memset(irq, 0, @sizeOf(c.struct_irq));
    irq.vector = vector;
    irq.priority = pri;
    irq.isr = isr;
    irq.ist = ist;
    irq.data = data;

    if (ist != IST_NONE) {
        irq.thread = c.kthread_create(irq_thread, irq, ISTPRI(pri));
        if (irq.thread == null) {
            @panic("irq_attach");
        }
        c.event_init(@as(?*anyopaque, @ptrCast(&irq.istevt)), "interrupt");
    }
    irq_table[@intCast(vector)] = irq;
    const mode: c_int = if (shared != 0) c.IMODE_LEVEL else c.IMODE_EDGE;
    c.interrupt_setup(vector, mode);
    c.interrupt_unmask(vector, pri);

    c.sched_unlock();
    return irq;
}

pub fn irq_detach(irq: ?*c.struct_irq) callconv(.c) void {
    std.debug.assert(irq != null);
    std.debug.assert(irq.?.vector < c.MAXIRQS);

    c.interrupt_mask(irq.?.vector);
    irq_table[@intCast(irq.?.vector)] = null;
    if (irq.?.thread != null) {
        c.kthread_terminate(irq.?.thread);
    }

    c.kmem_free(irq);
}

pub fn irq_handler(vector: c_int) callconv(.c) void {
    const irq = irq_table[@intCast(vector)] orelse {
        return;
    };
    std.debug.assert(irq.isr != null);

    irq.count +%= 1;

    const rc = irq.isr.?(irq.data);

    if (rc == c.INT_CONTINUE) {
        std.debug.assert(irq.ist != IST_NONE);
        irq.istreq += 1;
        c.sched_wakeup(@as(?*c.struct_event, @ptrCast(&irq.istevt)));
        std.debug.assert(irq.istreq != 0);
    }
}

pub fn irq_info(info: ?*c.struct_irqinfo) callconv(.c) c_int {
    var vec = info.?.cookie;

    while (vec < c.MAXIRQS) {
        if (irq_table[@intCast(vec)] != null) {
            break;
        }
        vec += 1;
    }
    if (vec >= c.MAXIRQS) {
        return c.ESRCH;
    }

    const irq = irq_table[@intCast(vec)].?;
    info.?.vector = irq.vector;
    info.?.count = irq.count;
    info.?.priority = irq.priority;
    info.?.istreq = irq.istreq;
    info.?.thread = irq.thread;
    info.?.cookie = vec + 1;
    return 0;
}

pub fn irq_init() callconv(.c) void {
    @as(*usize, @ptrCast(&IST_NONE)).* = @as(usize, @bitCast(@as(isize, -1)));
    c.interrupt_init();
    _ = c.spl0();
}

comptime {
    @export(&irq_attach, .{ .name = "irq_attach", .linkage = .strong });
    @export(&irq_detach, .{ .name = "irq_detach", .linkage = .strong });
    @export(&irq_handler, .{ .name = "irq_handler", .linkage = .strong });
    @export(&irq_info, .{ .name = "irq_info", .linkage = .strong });
    @export(&irq_init, .{ .name = "irq_init", .linkage = .strong });
}
