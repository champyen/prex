const std = @import("std");
const builtin = @import("builtin");

const c = @import("c").c;

var sem_list: ?*c.struct_sem = null;

const ffi = @import("ffi");
const kutil = ffi.kutil;
const smp = ffi.smp;
const kmem = ffi.kmem;
const sched = ffi.sched;
const thread = ffi.thread;



inline fn list_init(head: *c.struct_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

inline fn list_insert(prev: *c.struct_list, node: *c.struct_list) void {
    node.prev = @ptrCast(prev);
    node.next = prev.next;
    prev.next.?.*.prev = @ptrCast(node);
    prev.next = @ptrCast(node);
}

inline fn list_remove(node: *c.struct_list) void {
    node.prev.?.*.next = node.next;
    node.next.?.*.prev = node.prev;
}

inline fn list_empty(head: *c.struct_list) bool {
    return head.next == @as(?*c.struct_list, @ptrCast(head));
}

inline fn list_first(head: *c.struct_list) *c.struct_list {
    return @ptrCast(head.next.?);
}

inline fn list_next(node: *c.struct_list) *c.struct_list {
    return @ptrCast(node.next.?);
}

fn valid(s: c.sem_t) bool {
    var tmp = sem_list;
    while (tmp) |current| {
        if (current == s) {
            return true;
        }
        tmp = current.*.next;
    }
    return false;
}

fn reference(s: c.sem_t) void {
    s.*.refcnt += 1;
}

fn release(s: c.sem_t) void {
    s.*.refcnt -= 1;
    if (s.*.refcnt > 0) {
        return;
    }
    list_remove(&s.*.task_link);
    s.*.owner.*.nsyncs -= 1;

    var sp: *?*c.struct_sem = &sem_list;
    while (sp.*) |current| {
        if (current == s) {
            sp.* = current.*.next;
            break;
        }
        sp = @ptrCast(&current.*.next);
    }
    kmem.free(s);
}

fn copyin(usp: ?*c.sem_t, ksp: ?*c.sem_t) c_int {
    var s: c.sem_t = undefined;
    if (ffi.hal.copyin(@as(?*const anyopaque, @ptrCast(usp)), @as(?*anyopaque, @ptrCast(&s)), @sizeOf(c.sem_t)) != 0 or !valid(s)) {
        return c.EINVAL;
    }
    ksp.?.* = s;
    return 0;
}

pub fn init(sp: ?*c.sem_t, value: c_uint) callconv(.c) c_int {
    const self = kutil.cur_task();
    if (self.*.nsyncs >= c.MAXSYNCS) {
        return c.EAGAIN;
    }
    if (value > c.MAXSEMVAL) {
        return c.EINVAL;
    }

    var s: c.sem_t = undefined;
    if (ffi.hal.copyin(@as(?*const anyopaque, @ptrCast(sp)), @as(?*anyopaque, @ptrCast(&s)), @sizeOf(c.sem_t)) != 0) {
        return c.EFAULT;
    }

    sched.lock();
    if (s != null and valid(s)) {
        if (s.*.owner != self) {
            sched.unlock();
            return c.EINVAL;
        }
        if (!ffi.queue.empty(&s.*.event.sleepq)) {
            sched.unlock();
            return c.EBUSY;
        }
        s.*.value = value;
    } else {
        const mem = kmem.alloc(@sizeOf(c.struct_sem)) orelse {
            sched.unlock();
            return c.ENOSPC;
        };
        s = @ptrCast(@alignCast(mem));
        if (ffi.hal.copyout(@as(?*const anyopaque, @ptrCast(&s)), @as(?*anyopaque, @ptrCast(sp)), @sizeOf(c.sem_t)) != 0) {
            kmem.free(s);
            sched.unlock();
            return c.EFAULT;
        }
        c.event_init(&s.*.event, "semaphore");
        s.*.owner = self;
        s.*.refcnt = 1;
        s.*.value = value;

        list_insert(&self.*.sems, &s.*.task_link);
        self.*.nsyncs += 1;
        s.*.next = sem_list;
        sem_list = s;
    }
    sched.unlock();
    return 0;
}

pub fn destroy(sp: ?*c.sem_t) callconv(.c) c_int {
    var s: c.sem_t = undefined;

    sched.lock();
    if (copyin(sp, &s) != 0 or s.*.owner != kutil.cur_task()) {
        sched.unlock();
        return c.EINVAL;
    }
    if (!ffi.queue.empty(&s.*.event.sleepq) or s.*.value == 0) {
        sched.unlock();
        return c.EBUSY;
    }
    release(s);
    sched.unlock();
    return 0;
}

pub fn wait(sp: ?*c.sem_t, timeout: c_ulong) callconv(.c) c_int {
    var s: c.sem_t = undefined;
    var error_code: c_int = 0;

    sched.lock();
    if (copyin(sp, &s) != 0) {
        sched.unlock();
        return c.EINVAL;
    }
    reference(s);

    while (s.*.value == 0) {
        ffi.deadlock.sleep(@ptrCast(s), "semaphore");
        const rc = sched.tsleep(&s.*.event, @intCast(timeout));
        ffi.deadlock.stop_sleep();
        if (rc == c.SLP_TIMEOUT) {
            error_code = c.ETIMEDOUT;
            break;
        }
        if (rc == c.SLP_INTR) {
            error_code = c.EINTR;
            break;
        }
    }
    if (error_code == 0) {
        s.*.value -= 1;
    }

    release(s);
    sched.unlock();
    return error_code;
}

pub fn tryWait(sp: ?*c.sem_t) callconv(.c) c_int {
    var s: c.sem_t = undefined;

    sched.lock();
    if (copyin(sp, &s) != 0) {
        sched.unlock();
        return c.EINVAL;
    }
    if (s.*.value == 0) {
        sched.unlock();
        return c.EAGAIN;
    }
    s.*.value -= 1;
    sched.unlock();
    return 0;
}

pub fn post(sp: ?*c.sem_t) callconv(.c) c_int {
    var s: c.sem_t = undefined;

    sched.lock();
    if (copyin(sp, &s) != 0) {
        sched.unlock();
        return c.EINVAL;
    }
    if (s.*.value >= c.MAXSEMVAL) {
        sched.unlock();
        return c.ERANGE;
    }
    s.*.value += 1;
    if (s.*.value > 0) {
        _ = sched.wakeone(&s.*.event);
    }

    sched.unlock();
    return 0;
}

pub fn postKernel(s: c.sem_t) callconv(.c) c_int {
    sched.lock();
    if (!valid(s)) {
        sched.unlock();
        return c.EINVAL;
    }
    if (s.*.value >= c.MAXSEMVAL) {
        sched.unlock();
        return c.ERANGE;
    }
    s.*.value += 1;
    if (s.*.value > 0) {
        _ = sched.wakeone(&s.*.event);
    }

    sched.unlock();
    return 0;
}

pub fn getValue(sp: ?*c.sem_t, value: ?*c_uint) callconv(.c) c_int {
    var s: c.sem_t = undefined;

    sched.lock();
    if (copyin(sp, &s) != 0) {
        sched.unlock();
        return c.EINVAL;
    }
    if (ffi.hal.copyout(@as(?*const anyopaque, @ptrCast(&s.*.value)), @as(?*anyopaque, @ptrCast(value)), @sizeOf(@TypeOf(s.*.value))) != 0) {
        sched.unlock();
        return c.EFAULT;
    }
    sched.unlock();
    return 0;
}

pub fn cleanup(task: c.task_t) callconv(.c) void {
    const head = &task.*.sems;
    var n = list_first(head);
    while (n != @as(*c.struct_list, @ptrCast(head))) {
        const next = list_next(n);
        const s: *c.struct_sem = @fieldParentPtr("task_link", n);
        release(@ptrCast(s));
        n = next;
    }
}

comptime {
    if (@import("root") == @This()) {
        @export(&init, .{ .name = "sem_init", .linkage = .strong });
        @export(&destroy, .{ .name = "sem_destroy", .linkage = .strong });
        @export(&wait, .{ .name = "sem_wait", .linkage = .strong });
        @export(&tryWait, .{ .name = "sem_trywait", .linkage = .strong });
        @export(&post, .{ .name = "sem_post", .linkage = .strong });
        @export(&postKernel, .{ .name = "ksem_post", .linkage = .strong });
        @export(&getValue, .{ .name = "sem_getvalue", .linkage = .strong });
        @export(&cleanup, .{ .name = "sem_cleanup", .linkage = .strong });
    }
}
