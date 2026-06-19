const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});

var sem_list: ?*c.struct_sem = null;

extern fn hal_get_cpu_control() callconv(.c) ?*c.struct_cpu_control;

inline fn get_curthread() *c.struct_thread {
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        return @ptrCast(hal_get_cpu_control().?.*.active_thread.?);
    } else {
        const env = struct {
            extern var curthread: c.thread_t;
        };
        return @ptrCast(env.curthread.?);
    }
}

inline fn get_curtask() *c.struct_task {
    return @ptrCast(get_curthread().*.task.?);
}

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

fn sem_valid(s: c.sem_t) bool {
    var tmp = sem_list;
    while (tmp) |current| {
        if (current == s) {
            return true;
        }
        tmp = current.*.next;
    }
    return false;
}

fn sem_reference(s: c.sem_t) void {
    s.*.refcnt += 1;
}

fn sem_release(s: c.sem_t) void {
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
    c.kmem_free(s);
}

fn sem_copyin(usp: ?*c.sem_t, ksp: ?*c.sem_t) c_int {
    var s: c.sem_t = undefined;
    if (c.copyin(@as(?*const anyopaque, @ptrCast(usp)), @as(?*anyopaque, @ptrCast(&s)), @sizeOf(c.sem_t)) != 0 or !sem_valid(s)) {
        return c.EINVAL;
    }
    ksp.?.* = s;
    return 0;
}

pub fn sem_init(sp: ?*c.sem_t, value: c_uint) callconv(.c) c_int {
    const self = get_curtask();
    if (self.*.nsyncs >= c.MAXSYNCS) {
        return c.EAGAIN;
    }
    if (value > c.MAXSEMVAL) {
        return c.EINVAL;
    }

    var s: c.sem_t = undefined;
    if (c.copyin(@as(?*const anyopaque, @ptrCast(sp)), @as(?*anyopaque, @ptrCast(&s)), @sizeOf(c.sem_t)) != 0) {
        return c.EFAULT;
    }

    c.sched_lock();
    if (s != null and sem_valid(s)) {
        if (s.*.owner != self) {
            c.sched_unlock();
            return c.EINVAL;
        }
        if (!c.queue_empty(&s.*.event.sleepq)) {
            c.sched_unlock();
            return c.EBUSY;
        }
        s.*.value = value;
    } else {
        const mem = c.kmem_alloc(@sizeOf(c.struct_sem)) orelse {
            c.sched_unlock();
            return c.ENOSPC;
        };
        s = @ptrCast(@alignCast(mem));
        if (c.copyout(@as(?*const anyopaque, @ptrCast(&s)), @as(?*anyopaque, @ptrCast(sp)), @sizeOf(c.sem_t)) != 0) {
            c.kmem_free(s);
            c.sched_unlock();
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
    c.sched_unlock();
    return 0;
}

pub fn sem_destroy(sp: ?*c.sem_t) callconv(.c) c_int {
    var s: c.sem_t = undefined;

    c.sched_lock();
    if (sem_copyin(sp, &s) != 0 or s.*.owner != get_curtask()) {
        c.sched_unlock();
        return c.EINVAL;
    }
    if (!c.queue_empty(&s.*.event.sleepq) or s.*.value == 0) {
        c.sched_unlock();
        return c.EBUSY;
    }
    sem_release(s);
    c.sched_unlock();
    return 0;
}

pub fn sem_wait(sp: ?*c.sem_t, timeout: c_ulong) callconv(.c) c_int {
    var s: c.sem_t = undefined;
    var error_code: c_int = 0;

    c.sched_lock();
    if (sem_copyin(sp, &s) != 0) {
        c.sched_unlock();
        return c.EINVAL;
    }
    sem_reference(s);

    while (s.*.value == 0) {
        c.deadlock_sleep(@ptrCast(s), "semaphore");
        const rc = c.sched_tsleep(&s.*.event, timeout);
        c.deadlock_stop_sleep();
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

    sem_release(s);
    c.sched_unlock();
    return error_code;
}

pub fn sem_trywait(sp: ?*c.sem_t) callconv(.c) c_int {
    var s: c.sem_t = undefined;

    c.sched_lock();
    if (sem_copyin(sp, &s) != 0) {
        c.sched_unlock();
        return c.EINVAL;
    }
    if (s.*.value == 0) {
        c.sched_unlock();
        return c.EAGAIN;
    }
    s.*.value -= 1;
    c.sched_unlock();
    return 0;
}

pub fn sem_post(sp: ?*c.sem_t) callconv(.c) c_int {
    var s: c.sem_t = undefined;

    c.sched_lock();
    if (sem_copyin(sp, &s) != 0) {
        c.sched_unlock();
        return c.EINVAL;
    }
    if (s.*.value >= c.MAXSEMVAL) {
        c.sched_unlock();
        return c.ERANGE;
    }
    s.*.value += 1;
    if (s.*.value > 0) {
        _ = c.sched_wakeone(&s.*.event);
    }

    c.sched_unlock();
    return 0;
}

pub fn ksem_post(s: c.sem_t) callconv(.c) c_int {
    c.sched_lock();
    if (!sem_valid(s)) {
        c.sched_unlock();
        return c.EINVAL;
    }
    if (s.*.value >= c.MAXSEMVAL) {
        c.sched_unlock();
        return c.ERANGE;
    }
    s.*.value += 1;
    if (s.*.value > 0) {
        _ = c.sched_wakeone(&s.*.event);
    }

    c.sched_unlock();
    return 0;
}

pub fn sem_getvalue(sp: ?*c.sem_t, value: ?*c_uint) callconv(.c) c_int {
    var s: c.sem_t = undefined;

    c.sched_lock();
    if (sem_copyin(sp, &s) != 0) {
        c.sched_unlock();
        return c.EINVAL;
    }
    if (c.copyout(@as(?*const anyopaque, @ptrCast(&s.*.value)), @as(?*anyopaque, @ptrCast(value)), @sizeOf(@TypeOf(s.*.value))) != 0) {
        c.sched_unlock();
        return c.EFAULT;
    }
    c.sched_unlock();
    return 0;
}

pub fn sem_cleanup(task: c.task_t) callconv(.c) void {
    const head = &task.*.sems;
    var n = list_first(head);
    while (n != @as(*c.struct_list, @ptrCast(head))) {
        const next = list_next(n);
        const s: *c.struct_sem = @fieldParentPtr("task_link", n);
        sem_release(@ptrCast(s));
        n = next;
    }
}

comptime {
    @export(&sem_init, .{ .name = "sem_init", .linkage = .strong });
    @export(&sem_destroy, .{ .name = "sem_destroy", .linkage = .strong });
    @export(&sem_wait, .{ .name = "sem_wait", .linkage = .strong });
    @export(&sem_trywait, .{ .name = "sem_trywait", .linkage = .strong });
    @export(&sem_post, .{ .name = "sem_post", .linkage = .strong });
    @export(&ksem_post, .{ .name = "ksem_post", .linkage = .strong });
    @export(&sem_getvalue, .{ .name = "sem_getvalue", .linkage = .strong });
    @export(&sem_cleanup, .{ .name = "sem_cleanup", .linkage = .strong });
}
