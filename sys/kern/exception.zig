const std = @import("std");

const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});

extern fn hal_get_cpu_control() callconv(.c) ?*c.struct_cpu_control;

var EXC_DFL: ?*const fn (c_int) callconv(.c) void = undefined;

var exception_event: c.struct_event = undefined;

inline fn toReg(val: anytype) c.register_t {
    const T = @TypeOf(val);
    const u: usize = switch (@typeInfo(T)) {
        .pointer => @intFromPtr(val),
        .optional => if (val) |p| @intFromPtr(p) else 0,
        else => @intCast(val),
    };
    return @intCast(@as(isize, @bitCast(u)));
}

fn get_curthread() ?*c.struct_thread {
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        return @ptrCast(hal_get_cpu_control().?.active_thread);
    } else {
        const env = struct {
            extern var curthread: c.thread_t;
        };
        return @ptrCast(env.curthread);
    }
}

fn get_curtask() ?*c.struct_task {
    if (get_curthread()) |curr| {
        return @ptrCast(curr.task);
    }
    return null;
}

inline fn list_first(head: *c.struct_list) ?*c.struct_list {
    return @ptrCast(head.next);
}

inline fn list_next(node: *c.struct_list) ?*c.struct_list {
    return @ptrCast(node.next);
}

inline fn list_empty(head: *c.struct_list) bool {
    return head.next == @as(?*c.struct_list, @ptrCast(head));
}

pub fn exception_setup(handler: ?*const fn (c_int) callconv(.c) void) callconv(.c) c_int {
    const self = get_curtask() orelse return c.EINVAL;

    if (handler != EXC_DFL and !user_area(handler)) {
        return c.EFAULT;
    }
    if (handler == null) {
        return c.EINVAL;
    }

    c.sched_lock();
    if (self.handler != EXC_DFL and handler == EXC_DFL) {
        var n = list_first(&self.threads);
        while (n != null and n.? != @as(?*c.struct_list, @ptrCast(&self.threads))) {
            const s = c.splhigh();
            const t: *c.struct_thread = @fieldParentPtr("task_link", n.?);
            t.excbits = 0;
            _ = c.splx(s);

            if (t.slpevt == @as(?*c.struct_event, @ptrCast(&exception_event))) {
                c.sched_unsleep(t, c.SLP_BREAK);
            }
            n = list_next(n.?);
        }
    }
    self.handler = handler;
    c.sched_unlock();
    return 0;
}

pub fn exception_raise(task: c.task_t, excno: c_int) callconv(.c) c_int {
    var error_code: c_int = undefined;

    c.sched_lock();
    if (c.task_valid(task) == 0) {
        c.sched_unlock();
        return c.ESRCH;
    }
    if (task != @as(?*c.struct_task, @ptrCast(get_curtask())) and c.task_capable(c.CAP_KILL) == 0) {
        c.sched_unlock();
        return c.EPERM;
    }
    error_code = exception_post(task, excno);
    c.sched_unlock();
    return error_code;
}

pub fn exception_post(task: c.task_t, excno: c_int) callconv(.c) c_int {
    var t: ?*c.struct_thread = null;
    var found: c_int = 0;

    c.sched_lock();
    if (task.*.flags & c.TF_SYSTEM != 0) {
        c.sched_unlock();
        return c.EPERM;
    }

    if (task.*.handler == EXC_DFL or task.*.nthreads == 0 or excno < 0 or excno >= c.NEXC) {
        c.sched_unlock();
        return c.EINVAL;
    }

    var n = list_first(&task.*.threads);
    while (n != null and n.? != @as(?*c.struct_list, @ptrCast(&task.*.threads))) {
        const tmp: *c.struct_thread = @fieldParentPtr("task_link", n.?);
        if (tmp.slpevt == @as(?*c.struct_event, @ptrCast(&exception_event))) {
            t = tmp;
            found = 1;
            break;
        }
        n = list_next(n.?);
    }

    if (found == 0) {
        if (!list_empty(&task.*.threads)) {
            const first: *c.struct_thread = @fieldParentPtr("task_link", list_first(&task.*.threads).?);
            t = first;
        }
    }

    const s = c.splhigh();
    t.?.excbits |= @as(u32, 1) << @intCast(excno);
    _ = c.splx(s);

    c.sched_unsleep(t.?, c.SLP_INTR);

    c.sched_unlock();
    return 0;
}

pub fn exception_wait(excno: ?*c_int) callconv(.c) c_int {
    var i: c_int = 0;
    var rc: c_int = undefined;
    var s: c_int = undefined;

    if (get_curtask().?.handler == EXC_DFL) {
        return c.EINVAL;
    }

    i = 0;
    if (c.copyout(@as(?*const anyopaque, @ptrCast(&i)), @as(?*anyopaque, @ptrCast(excno)), @sizeOf(c_int)) != 0) {
        return c.EFAULT;
    }

    c.sched_lock();

    rc = c.sched_sleep(&exception_event);
    if (rc == c.SLP_BREAK) {
        c.sched_unlock();
        return c.EINVAL;
    }
    s = c.splhigh();
    var j: c_int = 0;
    while (j < c.NEXC) : (j += 1) {
        if (get_curthread().?.excbits & (@as(u32, 1) << @intCast(j)) != 0) {
            break;
        }
    }
    _ = c.splx(s);
    c.sched_unlock();

    i = j;
    if (c.copyout(@as(?*const anyopaque, @ptrCast(&i)), @as(?*anyopaque, @ptrCast(excno)), @sizeOf(c_int)) != 0) {
        return c.EFAULT;
    }
    return c.EINTR;
}

pub fn exception_mark(excno: c_int) callconv(.c) void {
    const s = c.splhigh();
    get_curthread().?.excbits |= @as(u32, 1) << @intCast(excno);
    _ = c.splx(s);
}

pub fn exception_deliver() callconv(.c) void {
    const self = get_curtask().?;
    var handler: ?*const fn (c_int) callconv(.c) void = undefined;
    var bitmap: u32 = undefined;
    var s: c_int = undefined;
    var excno: c_int = undefined;

    c.sched_lock();

    s = c.splhigh();
    bitmap = get_curthread().?.excbits;
    _ = c.splx(s);

    if (bitmap != 0) {
        excno = 0;
        while (excno < c.NEXC) : (excno += 1) {
            if (bitmap & (@as(u32, 1) << @intCast(excno)) != 0) {
                break;
            }
        }
        handler = self.handler;
        if (handler == EXC_DFL) {
            _ = c.task_terminate(self);
        }

        s = c.splhigh();
        c.context_save(&get_curthread().?.ctx);
        c.context_set(&get_curthread().?.ctx, c.CTX_UENTRY, toReg(handler));
        c.context_set(&get_curthread().?.ctx, c.CTX_UARG, toReg(excno));
        get_curthread().?.excbits &= ~(@as(u32, 1) << @intCast(excno));
        _ = c.splx(s);
    }
    c.sched_unlock();
}

pub fn exception_return() callconv(.c) void {
    const s = c.splhigh();
    c.context_restore(&get_curthread().?.ctx);
    _ = c.splx(s);
}

pub fn exception_init() callconv(.c) void {
    @as(*usize, @ptrCast(&EXC_DFL)).* = @as(usize, @bitCast(@as(isize, -1)));
    c.event_init(@as(?*anyopaque, @ptrCast(&exception_event)), "exception");
}

fn user_area(a: anytype) bool {
    const val = switch (@typeInfo(@TypeOf(a))) {
        .pointer => @intFromPtr(a),
        .optional => if (a) |p| @intFromPtr(p) else 0,
        else => a,
    };
    if (comptime @hasDecl(c, "CONFIG_MMU")) {
        return val < c.USERLIMIT;
    } else {
        return true;
    }
}

comptime {
    @export(&exception_setup, .{ .name = "exception_setup", .linkage = .strong });
    @export(&exception_raise, .{ .name = "exception_raise", .linkage = .strong });
    @export(&exception_post, .{ .name = "exception_post", .linkage = .strong });
    @export(&exception_wait, .{ .name = "exception_wait", .linkage = .strong });
    @export(&exception_mark, .{ .name = "exception_mark", .linkage = .strong });
    @export(&exception_deliver, .{ .name = "exception_deliver", .linkage = .strong });
    @export(&exception_return, .{ .name = "exception_return", .linkage = .strong });
    @export(&exception_init, .{ .name = "exception_init", .linkage = .strong });
}
