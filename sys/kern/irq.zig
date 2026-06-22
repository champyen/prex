const std = @import("std");
const ffi = @import("ffi");
const hal = ffi.hal;
const kern = ffi.kern;
const lib = ffi.lib;

const c = @import("c").c;

const sched = ffi.sched;
const kmem = ffi.kmem;
const thread = ffi.thread;

var IST_NONE: ?*const fn (?*anyopaque) callconv(.c) void = undefined;

var irq_table = std.mem.zeroes([hal.MAXIRQS]?*kern.IRQ);

inline fn ISTPRI(pri: c_int) c_int {
    return hal.PRI_IST + (hal.IPL_HIGH - pri);
}

fn irq_thread(arg: ?*anyopaque) callconv(.c) void {
    const irq: *kern.IRQ = @ptrCast(@alignCast(arg.?));
    const fn_ptr = irq.ist;
    const data = irq.data;

    _ = hal.splhigh();

    while (true) {
        if (irq.istreq <= 0) {
            _ = sched.tsleep(&irq.istevt, 0);
        }
        irq.istreq -= 1;
        std.debug.assert(irq.istreq >= 0);

        _ = hal.spl0();
        fn_ptr.?(data);
        _ = hal.splhigh();
    }
}

pub fn attach(vector: c_int, pri: c_int, shared: c_int, isr: ?*const fn (?*anyopaque) callconv(.c) c_int, ist: ?*const fn (?*anyopaque) callconv(.c) void, data: ?*anyopaque) callconv(.c) ?*kern.IRQ {
    std.debug.assert(isr != null);

    sched.lock();
    const irq_mem = kmem.alloc(@sizeOf(kern.IRQ));
    if (irq_mem == null) {
        @panic("irq_attach");
    }
    const irq: *kern.IRQ = @ptrCast(@alignCast(irq_mem));

    _ = lib.memset(irq, 0, @sizeOf(kern.IRQ));
    irq.vector = vector;
    irq.priority = pri;
    irq.isr = isr;
    irq.ist = ist;
    irq.data = data;

    if (ist != IST_NONE) {
        irq.thread = thread.kcreate(irq_thread, irq, ISTPRI(pri));
        if (irq.thread == null) {
            @panic("irq_attach");
        }
        c.event_init(@as(?*anyopaque, @ptrCast(&irq.istevt)), "interrupt");
    }
    irq_table[@intCast(vector)] = irq;
    const mode: c_int = if (shared != 0) hal.IMODE_LEVEL else hal.IMODE_EDGE;
    hal.interrupt_setup(vector, mode);
    hal.interrupt_unmask(vector, pri);

    sched.unlock();
    return irq;
}

pub fn detach(irq: ?*kern.IRQ) callconv(.c) void {
    std.debug.assert(irq != null);
    std.debug.assert(irq.?.vector < hal.MAXIRQS);

    hal.interrupt_mask(irq.?.vector);
    irq_table[@intCast(irq.?.vector)] = null;
    if (irq.?.thread != null) {
        _ = thread.kterminate(irq.?.thread);
    }

    kmem.free(irq);
}

pub fn handler(vector: c_int) callconv(.c) void {
    const irq = irq_table[@intCast(vector)] orelse {
        return;
    };
    std.debug.assert(irq.isr != null);

    irq.count +%= 1;

    const rc = irq.isr.?(irq.data);

    if (rc == hal.INT_CONTINUE) {
        std.debug.assert(irq.ist != IST_NONE);
        irq.istreq += 1;
        sched.wakeup(&irq.istevt);
        std.debug.assert(irq.istreq != 0);
    }
}

pub fn info(irq_info_ptr: ?*hal.IrqInfo) callconv(.c) c_int {
    var vec = irq_info_ptr.?.cookie;

    while (vec < hal.MAXIRQS) {
        if (irq_table[@intCast(vec)] != null) {
            break;
        }
        vec += 1;
    }
    if (vec >= hal.MAXIRQS) {
        return kern.Errno.ESRCH;
    }

    const irq = irq_table[@intCast(vec)].?;
    irq_info_ptr.?.vector = irq.vector;
    irq_info_ptr.?.count = irq.count;
    irq_info_ptr.?.priority = irq.priority;
    irq_info_ptr.?.istreq = irq.istreq;
    irq_info_ptr.?.thread = irq.thread;
    irq_info_ptr.?.cookie = vec + 1;
    return 0;
}

pub fn init() callconv(.c) void {
    @as(*usize, @ptrCast(&IST_NONE)).* = @as(usize, @bitCast(@as(isize, -1)));
    hal.interrupt_init();
    _ = hal.spl0();
}

comptime {
    if (@import("root") == @This()) {
        @export(&attach, .{ .name = "irq_attach", .linkage = .strong });
        @export(&detach, .{ .name = "irq_detach", .linkage = .strong });
        @export(&handler, .{ .name = "irq_handler", .linkage = .strong });
        @export(&info, .{ .name = "irq_info", .linkage = .strong });
        @export(&init, .{ .name = "irq_init", .linkage = .strong });
    }
}
