const c = @import("c").c;
const ffi = @import("ffi");
const kutil = ffi.kutil;
const smp = ffi.smp;
const kmem = ffi.kmem;
const sched = ffi.sched;
const mutex = ffi.mutex;
const thread = ffi.thread;

inline fn is_cond_initializer(m: c.cond_t) bool {
    if (m) |ptr| {
        return @intFromPtr(ptr) == 0x43496e69;
    }
    return false;
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

fn valid(m: c.cond_t) c_int {
    const head = &kutil.cur_task().*.conds;
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

fn copyin(ucp: ?*c.cond_t, kcp: ?*c.cond_t) c_int {
    var m: c.cond_t = undefined;
    if (ffi.hal.copyin(@as(?*const anyopaque, @ptrCast(ucp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t)) != 0) {
        return c.EFAULT;
    }

    if (is_cond_initializer(m)) {
        const error_code = init(ucp);
        if (error_code != 0) {
            return error_code;
        }
        _ = ffi.hal.copyin(@as(?*const anyopaque, @ptrCast(ucp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t));
    } else {
        if (valid(m) == 0) {
            return c.EINVAL;
        }
    }
    kcp.?.* = m;
    return 0;
}

pub fn init(cp: ?*c.cond_t) callconv(.c) c_int {
    const self = kutil.cur_task();
    if (self.*.nsyncs >= c.MAXSYNCS) {
        return c.EAGAIN;
    }

    const mem = kmem.alloc(@sizeOf(c.struct_cond)) orelse return c.ENOMEM;
    const m: c.cond_t = @ptrCast(@alignCast(mem));

    c.event_init(&m.*.event, "condvar");
    m.*.owner = self;

    if (ffi.hal.copyout(@as(?*const anyopaque, @ptrCast(&m)), @as(?*anyopaque, @ptrCast(cp)), @sizeOf(c.cond_t)) != 0) {
        kmem.free(m);
        return c.EFAULT;
    }

    sched.lock();
    list_insert(&self.*.conds, &m.*.task_link);
    self.*.nsyncs += 1;
    sched.unlock();
    return 0;
}

fn deallocate(m: c.cond_t) void {
    m.*.owner.*.nsyncs -= 1;
    list_remove(&m.*.task_link);
    kmem.free(m);
}

pub fn destroy(cp: ?*c.cond_t) callconv(.c) c_int {
    var m: c.cond_t = undefined;
    sched.lock();
    if (ffi.hal.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t)) != 0) {
        sched.unlock();
        return c.EFAULT;
    }
    if (valid(m) == 0) {
        sched.unlock();
        return c.EINVAL;
    }
    if (!ffi.queue.empty(&m.*.event.sleepq)) {
        sched.unlock();
        return c.EBUSY;
    }
    deallocate(m);
    sched.unlock();
    return 0;
}

pub fn cleanup(task: c.task_t) callconv(.c) void {
    while (!list_empty(&task.*.conds)) {
        const n = list_first(&task.*.conds);
        const m: *c.struct_cond = @fieldParentPtr("task_link", n);
        deallocate(@ptrCast(m));
    }
}

pub fn wait(cp: ?*c.cond_t, mp: ?*c.mutex_t) callconv(.c) c_int {
    var m: c.cond_t = undefined;

    if (ffi.hal.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t)) != 0) {
        return c.EINVAL;
    }

    sched.lock();
    if (is_cond_initializer(m)) {
        const error_code = init(cp);
        if (error_code != 0) {
            sched.unlock();
            return error_code;
        }
        _ = ffi.hal.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t));
    } else {
        if (valid(m) == 0) {
            sched.unlock();
            return c.EINVAL;
        }
    }

    var err: c_int = 0;

    const unlock_err = mutex.unlock(mp);
    if (unlock_err != 0) {
        sched.unlock();
        return unlock_err;
    }

    ffi.deadlock.sleep(@ptrCast(m), "cond");
    const rc = sched.tsleep(&m.*.event, 0);
    ffi.deadlock.stop_sleep();
    if (rc == c.SLP_INTR) {
        err = c.EINTR;
    }
    sched.unlock();

    if (err == 0) {
        err = mutex.lock(mp);
    }

    return err;
}

pub fn signal(cp: ?*c.cond_t) callconv(.c) c_int {
    var m: c.cond_t = undefined;

    sched.lock();
    if (ffi.hal.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t)) != 0) {
        sched.unlock();
        return c.EINVAL;
    }
    _ = sched.wakeone(&m.*.event);
    sched.unlock();
    return 0;
}

pub fn broadcast(cp: ?*c.cond_t) callconv(.c) c_int {
    var m: c.cond_t = undefined;

    sched.lock();
    if (ffi.hal.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t)) != 0) {
        sched.unlock();
        return c.EINVAL;
    }
    sched.wakeup(&m.*.event);
    sched.unlock();
    return 0;
}

comptime {
    if (@import("root") == @This()) {
        @export(&init, .{ .name = "cond_init", .linkage = .strong });
        @export(&destroy, .{ .name = "cond_destroy", .linkage = .strong });
        @export(&cleanup, .{ .name = "cond_cleanup", .linkage = .strong });
        @export(&wait, .{ .name = "cond_wait", .linkage = .strong });
        @export(&signal, .{ .name = "cond_signal", .linkage = .strong });
        @export(&broadcast, .{ .name = "cond_broadcast", .linkage = .strong });
    }
}
