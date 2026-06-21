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

fn valid(m: c.cond_t) c_int {
    const km: *ffi.sync.Cond = @ptrCast(m);
    const head = &kutil.cur_task().*.conds;
    var n = @as(*ffi.List, @ptrCast(head)).first();
    while (n != @as(*ffi.List, @ptrCast(head))) : (n = n.nextNode()) {
        const tmp = n.entry(ffi.sync.Cond, "task_link");
        if (tmp == km) {
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

    const mem = kmem.alloc(@sizeOf(ffi.sync.Cond)) orelse return c.ENOMEM;
    const m: c.cond_t = @ptrCast(@alignCast(mem));

    c.event_init(&m.*.event, "condvar");
    m.*.owner = self;

    if (ffi.hal.copyout(@as(?*const anyopaque, @ptrCast(&m)), @as(?*anyopaque, @ptrCast(cp)), @sizeOf(c.cond_t)) != 0) {
        kmem.free(m);
        return c.EFAULT;
    }

    sched.lock();
    @as(*ffi.List, @ptrCast(&self.*.conds)).insertAfter(@as(*ffi.List, @ptrCast(&m.*.task_link)));
    self.*.nsyncs += 1;
    sched.unlock();
    return 0;
}

fn deallocate(m: c.cond_t) void {
    m.*.owner.*.nsyncs -= 1;
    @as(*ffi.List, @ptrCast(&m.*.task_link)).remove();
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
    const km: *ffi.sync.Cond = @ptrCast(m);
    if (!km.*.event.sleepq.isEmpty()) {
        sched.unlock();
        return c.EBUSY;
    }
    deallocate(m);
    sched.unlock();
    return 0;
}

pub fn cleanup(task: c.task_t) callconv(.c) void {
    while (!@as(*ffi.List, @ptrCast(&task.*.conds)).isEmpty()) {
        const n = @as(*ffi.List, @ptrCast(&task.*.conds)).first();
        const m = n.entry(ffi.sync.Cond, "task_link");
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

    const km: *ffi.sync.Cond = @ptrCast(m);
    var err: c_int = 0;

    const unlock_err = mutex.unlock(mp);
    if (unlock_err != 0) {
        sched.unlock();
        return unlock_err;
    }

    ffi.deadlock.sleep(@ptrCast(km), "cond");
    const rc = sched.tsleep(&km.*.event, 0);
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
    const km: *ffi.sync.Cond = @ptrCast(m);
    _ = sched.wakeone(&km.*.event);
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
    const km: *ffi.sync.Cond = @ptrCast(m);
    sched.wakeup(&km.*.event);
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
