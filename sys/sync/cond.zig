const c = @import("c").c;
const ffi = @import("ffi");
const deadlock = ffi.deadlock;
const hal = ffi.hal;
const kern = ffi.kern;
const sync = ffi.sync;
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
    const km: *sync.Cond = @ptrCast(m);
    const CL = ffi.IntrusiveList(kern.Task, ffi.List, "conds");
    const self = kutil.cur_task();
    const head = CL.node(self);
    var n = head.first();
    while (n != head) : (n = n.nextNode()) {
        const tmp = n.entry(sync.Cond, "task_link");
        if (tmp == km) {
            return 1;
        }
    }
    return 0;
}

fn copyin(ucp: ?*c.cond_t, kcp: ?*c.cond_t) c_int {
    var m: c.cond_t = undefined;
    if (hal.copyin(@as(?*const anyopaque, @ptrCast(ucp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t)) != 0) {
        return kern.Errno.EFAULT;
    }

    if (is_cond_initializer(m)) {
        const error_code = init(ucp);
        if (error_code != 0) {
            return error_code;
        }
        _ = hal.copyin(@as(?*const anyopaque, @ptrCast(ucp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t));
    } else {
        if (valid(m) == 0) {
            return kern.Errno.EINVAL;
        }
    }
    kcp.?.* = m;
    return 0;
}

pub fn init(cp: ?*c.cond_t) callconv(.c) c_int {
    const self = kutil.cur_task();
    if (self.*.nsyncs >= hal.MAXSYNCS) {
        return kern.Errno.EAGAIN;
    }

    const mem = kmem.alloc(@sizeOf(sync.Cond)) orelse return kern.Errno.ENOMEM;
    const m: c.cond_t = @ptrCast(@alignCast(mem));
    errdefer kmem.free(m);

    c.event_init(&m.*.event, "condvar");
    m.*.owner = self;

    if (hal.copyout(@as(?*const anyopaque, @ptrCast(&m)), @as(?*anyopaque, @ptrCast(cp)), @sizeOf(c.cond_t)) != 0) {
        return kern.Errno.EFAULT;
    }

    sched.lock();
    defer sched.unlock();
    const TL = ffi.IntrusiveList(kern.Task, ffi.List, "conds");
    const ML = ffi.IntrusiveList(sync.Cond, ffi.List, "task_link");
    TL.node(self).insertAfter(ML.node(m));
    self.*.nsyncs += 1;
    return 0;
}

fn deallocate(m: c.cond_t) void {
    m.*.owner.*.nsyncs -= 1;
    ffi.IntrusiveList(sync.Cond, ffi.List, "task_link").node(m).remove();
    kmem.free(m);
}

pub fn destroy(cp: ?*c.cond_t) callconv(.c) c_int {
    var m: c.cond_t = undefined;
    sched.lock();
    defer sched.unlock();
    if (hal.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t)) != 0) {
        return kern.Errno.EFAULT;
    }
    if (valid(m) == 0) {
        return kern.Errno.EINVAL;
    }
    const km: *sync.Cond = @ptrCast(m);
    if (!km.*.event.sleepq.isEmpty()) {
        return kern.Errno.EBUSY;
    }
    deallocate(m);
    return 0;
}

pub fn cleanup(task: kern.TaskRef) callconv(.c) void {
    const TL = ffi.IntrusiveList(kern.Task, ffi.List, "conds");
    const head = TL.node(task);
    while (!head.isEmpty()) {
        const n = head.first();
        const m = n.entry(sync.Cond, "task_link");
        deallocate(@ptrCast(m));
    }
}

pub fn wait(cp: ?*c.cond_t, mp: ?*c.mutex_t) callconv(.c) c_int {
    var m: c.cond_t = undefined;

    if (hal.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t)) != 0) {
        return kern.Errno.EINVAL;
    }

    sched.lock();
    if (is_cond_initializer(m)) {
        const error_code = init(cp);
        if (error_code != 0) {
            sched.unlock();
            return error_code;
        }
        _ = hal.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t));
    } else {
        if (valid(m) == 0) {
            sched.unlock();
            return kern.Errno.EINVAL;
        }
    }

    const km: *sync.Cond = @ptrCast(m);
    var err: c_int = 0;

    const unlock_err = mutex.unlock(mp);
    if (unlock_err != 0) {
        sched.unlock();
        return unlock_err;
    }

    deadlock.sleep(@ptrCast(km), "cond");
    const rc = sched.tsleep(&km.*.event, 0);
    deadlock.stop_sleep();
    if (rc == kern.SLP_INTR) {
        err = kern.Errno.EINTR;
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
    defer sched.unlock();
    if (hal.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t)) != 0) {
        return kern.Errno.EINVAL;
    }
    const km: *sync.Cond = @ptrCast(m);
    _ = sched.wakeone(&km.*.event);
    return 0;
}

pub fn broadcast(cp: ?*c.cond_t) callconv(.c) c_int {
    var m: c.cond_t = undefined;

    sched.lock();
    defer sched.unlock();
    if (hal.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.cond_t)) != 0) {
        return kern.Errno.EINVAL;
    }
    const km: *sync.Cond = @ptrCast(m);
    sched.wakeup(&km.*.event);
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
