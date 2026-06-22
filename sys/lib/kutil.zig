const std = @import("std");
const c = @import("c").c;
const ffi = @import("../ffi.zig");
const smp = ffi.smp;
const thread = ffi.thread;
const kern = ffi.kern;
const hal = ffi.hal;

pub inline fn round_page(x: usize) usize {
    return (x + (hal.PAGE_SIZE - 1)) & ~@as(usize, hal.PAGE_SIZE - 1);
}

pub inline fn trunc_page(x: usize) usize {
    return x & ~@as(usize, hal.PAGE_SIZE - 1);
}

pub inline fn user_area(a: anytype) bool {
    const val = switch (@typeInfo(@TypeOf(a))) {
        .pointer => @intFromPtr(a),
        .optional => if (a) |p| @intFromPtr(p) else 0,
        else => a,
    };
    if (comptime @hasDecl(c, "CONFIG_MMU")) {
        return val < hal.USERLIMIT;
    } else {
        return true;
    }
}

pub inline fn kvtop(va: anytype) kern.Paddr {
    const u: usize = switch (@typeInfo(@TypeOf(va))) {
        .pointer => @intFromPtr(va),
        .optional => if (va) |p| @intFromPtr(p) else 0,
        else => @as(usize, @intCast(va)),
    };
    return u - hal.KERNOFFSET;
}

pub inline fn ptokv(pa: kern.Paddr) ?*anyopaque {
    return @ptrFromInt(pa + hal.KERNOFFSET);
}

pub inline fn get_curthread() ?*hal.Thread {
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        return @ptrCast(smp.get_cpu_control().*.active_thread);
    } else {
        return @ptrCast(thread.curthread);
    }
}

pub inline fn get_curtask() ?*hal.Task {
    if (get_curthread()) |curr| {
        return @ptrCast(curr.task);
    }
    return null;
}

pub inline fn cur_thread() *hal.Thread {
    return get_curthread().?;
}

pub inline fn cur_task() *hal.Task {
    return get_curtask().?;
}

pub inline fn toReg(val: anytype) kern.Register {
    const u: usize = switch (@typeInfo(@TypeOf(val))) {
        .pointer => @intFromPtr(val),
        .optional => if (val) |p| @intFromPtr(p) else 0,
        else => @intCast(val),
    };
    return @intCast(@as(isize, @bitCast(u)));
}

pub const list = @import("list.zig");
