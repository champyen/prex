const std = @import("std");

const c = @import("c").c;

const ffi = @import("ffi");
const kutil = ffi.kutil;
const hal = ffi.hal;
const sched = ffi.sched;
const smp = ffi.smp;
const thread = ffi.thread;

var EXC_DFL: ?*const fn (c_int) callconv(.c) void = undefined;

var exception_event: c.struct_event = undefined;




inline fn list_first(head: *c.struct_list) ?*c.struct_list {
    return @ptrCast(head.next);
}

inline fn list_next(node: *c.struct_list) ?*c.struct_list {
    return @ptrCast(node.next);
}

inline fn list_empty(head: *c.struct_list) bool {
    return head.next == @as(?*c.struct_list, @ptrCast(head));
}

pub fn setup(handler: ?*const fn (c_int) callconv(.c) void) callconv(.c) c_int {
    const self = kutil.get_curtask() orelse return c.EINVAL;

    if (handler != EXC_DFL and !kutil.user_area(handler)) {
        return c.EFAULT;
    }
    if (handler == null) {
        return c.EINVAL;
    }

    sched.lock();
    if (self.handler != EXC_DFL and handler == EXC_DFL) {
        var n = list_first(&self.threads);
        while (n != null and n.? != @as(?*c.struct_list, @ptrCast(&self.threads))) {
            const s = hal.splhigh();
            const t: *c.struct_thread = @fieldParentPtr("task_link", n.?);
            t.excbits = 0;
            _ = hal.splx(s);

            if (t.slpevt == @as(?*c.struct_event, @ptrCast(&exception_event))) {
                sched.unsleep(t, c.SLP_BREAK);
            }
            n = list_next(n.?);
        }
    }
    self.handler = handler;
    sched.unlock();
    return 0;
}

pub fn raise(task: c.task_t, excno: c_int) callconv(.c) c_int {
    var error_code: c_int = undefined;

    sched.lock();
    if (c.task_valid(task) == 0) {
        sched.unlock();
        return c.ESRCH;
    }
    if (task != @as(?*c.struct_task, @ptrCast(kutil.get_curtask())) and c.task_capable(c.CAP_KILL) == 0) {
        sched.unlock();
        return c.EPERM;
    }
    error_code = post(task, excno);
    sched.unlock();
    return error_code;
}

pub fn post(task: c.task_t, excno: c_int) callconv(.c) c_int {
    var t: ?*c.struct_thread = null;
    var found: c_int = 0;

    sched.lock();
    if (task.*.flags & c.TF_SYSTEM != 0) {
        sched.unlock();
        return c.EPERM;
    }

    if (task.*.handler == EXC_DFL or task.*.nthreads == 0 or excno < 0 or excno >= c.NEXC) {
        sched.unlock();
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

    const s = hal.splhigh();
    t.?.excbits |= @as(u32, 1) << @intCast(excno);
    _ = hal.splx(s);

    sched.unsleep(t.?, c.SLP_INTR);

    sched.unlock();
    return 0;
}

pub fn wait(excno: ?*c_int) callconv(.c) c_int {
    var i: c_int = 0;
    var rc: c_int = undefined;
    var s: c_int = undefined;

    if (kutil.get_curtask().?.handler == EXC_DFL) {
        return c.EINVAL;
    }

    i = 0;
    if (ffi.vm.copyout(@as(?*const anyopaque, @ptrCast(&i)), @as(?*anyopaque, @ptrCast(excno)), @sizeOf(c_int)) != 0) {
        return c.EFAULT;
    }

    sched.lock();

    rc = sched.tsleep(&exception_event, 0);
    if (rc == c.SLP_BREAK) {
        sched.unlock();
        return c.EINVAL;
    }
    s = hal.splhigh();
    var j: c_int = 0;
    while (j < c.NEXC) : (j += 1) {
        if (kutil.get_curthread().?.excbits & (@as(u32, 1) << @intCast(j)) != 0) {
            break;
        }
    }
    _ = hal.splx(s);
    sched.unlock();

    i = j;
    if (ffi.vm.copyout(@as(?*const anyopaque, @ptrCast(&i)), @as(?*anyopaque, @ptrCast(excno)), @sizeOf(c_int)) != 0) {
        return c.EFAULT;
    }
    return c.EINTR;
}

pub fn mark(excno: c_int) callconv(.c) void {
    const s = hal.splhigh();
    kutil.get_curthread().?.excbits |= @as(u32, 1) << @intCast(excno);
    _ = hal.splx(s);
}

pub fn deliver() callconv(.c) void {
    const self = kutil.get_curtask().?;
    var handler: ?*const fn (c_int) callconv(.c) void = undefined;
    var bitmap: u32 = undefined;
    var s: c_int = undefined;
    var excno: c_int = undefined;

    sched.lock();

    s = hal.splhigh();
    bitmap = kutil.get_curthread().?.excbits;
    _ = hal.splx(s);

    if (bitmap != 0) {
        excno = 0;
        while (excno < c.NEXC) : (excno += 1) {
            if (bitmap & (@as(u32, 1) << @intCast(excno)) != 0) {
                break;
            }
        }
        handler = self.handler;
        if (handler == EXC_DFL) {
            _ = ffi.task.terminate(self);
        }

        s = hal.splhigh();
        hal.context_save(&kutil.get_curthread().?.ctx);
        hal.context_set(&kutil.get_curthread().?.ctx, c.CTX_UENTRY, kutil.toReg(handler));
        hal.context_set(&kutil.get_curthread().?.ctx, c.CTX_UARG, kutil.toReg(excno));
        kutil.get_curthread().?.excbits &= ~(@as(u32, 1) << @intCast(excno));
        _ = hal.splx(s);
    }
    sched.unlock();
}

pub fn @"return"() callconv(.c) void {
    const s = hal.splhigh();
    hal.context_restore(&kutil.get_curthread().?.ctx);
    _ = hal.splx(s);
}

pub fn init() callconv(.c) void {
    @as(*usize, @ptrCast(&EXC_DFL)).* = @as(usize, @bitCast(@as(isize, -1)));
    c.event_init(@as(?*anyopaque, @ptrCast(&exception_event)), "exception");
}


comptime {
    if (@import("root") == @This()) {
        @export(&setup, .{ .name = "exception_setup", .linkage = .strong });
        @export(&raise, .{ .name = "exception_raise", .linkage = .strong });
        @export(&post, .{ .name = "exception_post", .linkage = .strong });
        @export(&wait, .{ .name = "exception_wait", .linkage = .strong });
        @export(&mark, .{ .name = "exception_mark", .linkage = .strong });
        @export(&deliver, .{ .name = "exception_deliver", .linkage = .strong });
        @export(&@"return", .{ .name = "exception_return", .linkage = .strong });
        @export(&init, .{ .name = "exception_init", .linkage = .strong });
    }
}
