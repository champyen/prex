const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});

extern fn hal_get_cpu_control() callconv(.c) ?*c.struct_cpu_control;

inline fn is_cond_initializer(m: c.cond_t) bool {
    if (m) |ptr| {
        return @intFromPtr(ptr) == 0x43496e69;
    }
    return false;
}

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

fn cond_valid(m: c.cond_t) c_int {
    const head = &get_curtask().*.conds;
    var n = head.*.next.?;
    while (n != @as(*c.struct_list, @ptrCast(head))) : (n = n.*.next.?) {
        const node: *c.struct_list = @ptrCast(n);
        const tmp: *c.struct_cond = @fieldParentPtr("task_link", node);
        if (tmp == m) {
            return 1;
        }
    }
    return 0;
}

fn cond_copyin(ucp: ?*c.cond_t, kcp: ?*c.cond_t) c_int {
    var m: c.cond_t = undefined;
    if (c.copyin(@as(?*const anyopaque, @ptrCast(ucp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t)) != 0) {
        return c.EFAULT;
    }

    if (is_cond_initializer(m)) {
        const error_code = cond_init(ucp);
        if (error_code != 0) {
            return error_code;
        }
        _ = c.copyin(@as(?*const anyopaque, @ptrCast(ucp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t));
    } else {
        if (cond_valid(m) == 0) {
            return c.EINVAL;
        }
    }
    kcp.?.* = m;
    return 0;
}

pub fn cond_init(cp: ?*c.cond_t) callconv(.c) c_int {
    const self = get_curtask();
    if (self.*.nsyncs >= c.MAXSYNCS) {
        return c.EAGAIN;
    }

    const mem = c.kmem_alloc(@sizeOf(c.struct_cond)) orelse return c.ENOMEM;
    const m: c.cond_t = @ptrCast(@alignCast(mem));

    c.event_init(&m.*.event, "condvar");
    m.*.owner = self;

    if (c.copyout(@as(?*const anyopaque, @ptrCast(&m)), @as(?*anyopaque, @ptrCast(cp)), @sizeOf(c.cond_t)) != 0) {
        c.kmem_free(m);
        return c.EFAULT;
    }

    c.sched_lock();
    list_insert(&self.*.conds, &m.*.task_link);
    self.*.nsyncs += 1;
    c.sched_unlock();
    return 0;
}

fn cond_deallocate(m: c.cond_t) void {
    m.*.owner.*.nsyncs -= 1;
    list_remove(&m.*.task_link);
    c.kmem_free(m);
}

pub fn cond_destroy(cp: ?*c.cond_t) callconv(.c) c_int {
    var m: c.cond_t = undefined;
    c.sched_lock();
    if (c.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t)) != 0) {
        c.sched_unlock();
        return c.EFAULT;
    }
    if (cond_valid(m) == 0) {
        c.sched_unlock();
        return c.EINVAL;
    }
    if (!c.queue_empty(&m.*.event.sleepq)) {
        c.sched_unlock();
        return c.EBUSY;
    }
    cond_deallocate(m);
    c.sched_unlock();
    return 0;
}

pub fn cond_cleanup(task: c.task_t) callconv(.c) void {
    while (!list_empty(&task.*.conds)) {
        const n = list_first(&task.*.conds);
        const m: *c.struct_cond = @fieldParentPtr("task_link", n);
        cond_deallocate(@ptrCast(m));
    }
}

pub fn cond_wait(cp: ?*c.cond_t, mp: ?*c.mutex_t) callconv(.c) c_int {
    var m: c.cond_t = undefined;

    if (c.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t)) != 0) {
        return c.EINVAL;
    }

    c.sched_lock();
    if (is_cond_initializer(m)) {
        const error_code = cond_init(cp);
        if (error_code != 0) {
            c.sched_unlock();
            return error_code;
        }
        _ = c.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t));
    } else {
        if (cond_valid(m) == 0) {
            c.sched_unlock();
            return c.EINVAL;
        }
    }

    var err: c_int = 0;

    const unlock_err = c.mutex_unlock(mp);
    if (unlock_err != 0) {
        c.sched_unlock();
        return unlock_err;
    }

    c.deadlock_sleep(@ptrCast(m), "cond");
    const rc = c.sched_sleep(&m.*.event);
    c.deadlock_stop_sleep();
    if (rc == c.SLP_INTR) {
        err = c.EINTR;
    }
    c.sched_unlock();

    if (err == 0) {
        err = c.mutex_lock(mp);
    }

    return err;
}

pub fn cond_signal(cp: ?*c.cond_t) callconv(.c) c_int {
    var m: c.cond_t = undefined;

    c.sched_lock();
    if (c.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t)) != 0) {
        c.sched_unlock();
        return c.EINVAL;
    }
    _ = c.sched_wakeone(&m.*.event);
    c.sched_unlock();
    return 0;
}

pub fn cond_broadcast(cp: ?*c.cond_t) callconv(.c) c_int {
    var m: c.cond_t = undefined;

    c.sched_lock();
    if (c.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t)) != 0) {
        c.sched_unlock();
        return c.EINVAL;
    }
    c.sched_wakeup(&m.*.event);
    c.sched_unlock();
    return 0;
}

comptime {
    @export(&cond_init, .{ .name = "cond_init", .linkage = .strong });
    @export(&cond_destroy, .{ .name = "cond_destroy", .linkage = .strong });
    @export(&cond_cleanup, .{ .name = "cond_cleanup", .linkage = .strong });
    @export(&cond_wait, .{ .name = "cond_wait", .linkage = .strong });
    @export(&cond_signal, .{ .name = "cond_signal", .linkage = .strong });
    @export(&cond_broadcast, .{ .name = "cond_broadcast", .linkage = .strong });
}
