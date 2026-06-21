const std = @import("std");
const builtin = @import("builtin");

const c = @import("c").c;

const ffi = @import("ffi");
const kutil = ffi.kutil;
const smp = ffi.smp;
const kmem = ffi.kmem;
const sched = ffi.sched;
const thread = ffi.thread;

inline fn is_mutex_initializer(m: c.mutex_t) bool {
    if (m) |ptr| {
        return @intFromPtr(ptr) == 0x4d496e69;
    }
    return false;
}

fn valid(m: c.mutex_t) c_int {
    const km: *ffi.sync.Mutex = @ptrCast(m);
    const head = &kutil.cur_task().*.mutexes;
    var n = @as(*ffi.List, @ptrCast(head)).first();
    while (n != @as(*ffi.List, @ptrCast(head))) : (n = n.nextNode()) {
        const tmp = n.entry(ffi.sync.Mutex, "task_link");
        if (tmp == km) {
            return 1;
        }
    }
    return 0;
}

fn copyin(ump: ?*c.mutex_t, kmp: ?*c.mutex_t) c_int {
    var m: c.mutex_t = undefined;
    if (ffi.hal.copyin(@as(?*const anyopaque, @ptrCast(ump)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.mutex_t)) != 0) {
        return c.EFAULT;
    }

    if (is_mutex_initializer(m)) {
        const error_code = init(ump);
        if (error_code != 0) {
            return error_code;
        }
        _ = ffi.hal.copyin(@as(?*const anyopaque, @ptrCast(ump)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.mutex_t));
    } else {
        if (valid(m) == 0) {
            return c.EINVAL;
        }
    }
    kmp.?.* = m;
    return 0;
}

fn prio_inherit(waiter: c.thread_t) c_int {
    var m: c.mutex_t = waiter.*.mutex_waiting;
    var holder: c.thread_t = undefined;
    var count: c_int = 0;
    var iters: u32 = 0;

    while (m != null) {
        holder = m.*.holder;
        ffi.deadlock.check_loop("prio_inherit", &iters);

        if (holder == waiter) {
            return c.EDEADLK;
        }

        if (holder.*.priority > waiter.*.priority) {
            sched.set_pri(holder, holder.*.basepri, waiter.*.priority);
            m.*.priority = waiter.*.priority;
        }

        m = @ptrCast(holder.*.mutex_waiting);

        count += 1;
        if (count >= c.MAXINHERIT) {
            break;
        }
    }
    return 0;
}

fn prio_uninherit(t: c.thread_t) void {
    if (t.*.priority == t.*.basepri) {
        return;
    }

    var maxpri = t.*.basepri;
    const head = @as(*ffi.List, @ptrCast(&t.*.mutexes));
    var n = head.first();
    while (n != head) : (n = n.nextNode()) {
        const m = n.entry(ffi.sync.Mutex, "link");
        if (m.*.priority < maxpri) {
            maxpri = m.*.priority;
        }
    }

    sched.set_pri(t, t.*.basepri, maxpri);
}

pub fn init(mp: ?*c.mutex_t) callconv(.c) c_int {
    const self = kutil.cur_task();
    if (self.*.nsyncs >= c.MAXSYNCS) {
        return c.EAGAIN;
    }

    const mem = kmem.alloc(@sizeOf(ffi.sync.Mutex)) orelse return c.ENOMEM;
    const m: c.mutex_t = @ptrCast(@alignCast(mem));
    c.event_init(&m.*.event, "mutex");
    m.*.owner = self;
    m.*.holder = null;
    m.*.priority = c.MINPRI;

    if (ffi.hal.copyout(@as(?*const anyopaque, @ptrCast(&m)), @as(?*anyopaque, @ptrCast(mp)), @sizeOf(c.mutex_t)) != 0) {
        kmem.free(m);
        return c.EFAULT;
    }

    sched.lock();
    @as(*ffi.List, @ptrCast(&self.*.mutexes)).insertAfter(@as(*ffi.List, @ptrCast(&m.*.task_link)));
    self.*.nsyncs += 1;
    sched.unlock();
    return 0;
}

fn deallocate(m: c.mutex_t) void {
    m.*.owner.*.nsyncs -= 1;
    @as(*ffi.List, @ptrCast(&m.*.task_link)).remove();
    kmem.free(m);
}

pub fn destroy(mp: ?*c.mutex_t) callconv(.c) c_int {
    var m: c.mutex_t = undefined;
    sched.lock();
    if (ffi.hal.copyin(@as(?*const anyopaque, @ptrCast(mp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(c.mutex_t)) != 0) {
        sched.unlock();
        return c.EFAULT;
    }
    if (valid(m) == 0) {
        sched.unlock();
        return c.EINVAL;
    }
    const km: *ffi.sync.Mutex = @ptrCast(m);
    if (km.*.holder != null or !km.*.event.sleepq.isEmpty()) {
        sched.unlock();
        return c.EBUSY;
    }
    deallocate(m);
    sched.unlock();
    return 0;
}

pub fn cleanup(task: c.task_t) callconv(.c) void {
    while (!@as(*ffi.List, @ptrCast(&task.*.mutexes)).isEmpty()) {
        const n = @as(*ffi.List, @ptrCast(&task.*.mutexes)).first();
        const m = n.entry(ffi.sync.Mutex, "task_link");
        deallocate(@ptrCast(m));
    }
}

pub fn lock(mp: ?*c.mutex_t) callconv(.c) c_int {
    var m: c.mutex_t = undefined;

    sched.lock();
    const error_code = copyin(mp, &m);
    if (error_code != 0) {
        sched.unlock();
        return error_code;
    }

    const km: *ffi.sync.Mutex = @ptrCast(m);
    if (km.*.holder == kutil.cur_thread()) {
        km.*.locks += 1;
    } else {
        if (km.*.holder == null) {
            km.*.priority = kutil.cur_thread().*.priority;
            km.*.locks = 1;
            km.*.holder = kutil.cur_thread();
            @as(*ffi.List, @ptrCast(&kutil.cur_thread().*.mutexes)).insertAfter(&km.*.link);
            ffi.deadlock.record_lock(m, c.LOCK_TYPE_MUTEX);
        } else {
            ffi.deadlock.mutex_wait(m, kutil.cur_thread());
            kutil.cur_thread().*.mutex_waiting = m;
            const inherit_err = prio_inherit(kutil.cur_thread());
            if (inherit_err != 0) {
                ffi.deadlock.mutex_stop_wait(kutil.cur_thread());
                kutil.cur_thread().*.mutex_waiting = null;
                sched.unlock();
                return inherit_err;
            }
            const rc = sched.tsleep(&km.*.event, 0);
            ffi.deadlock.mutex_stop_wait(kutil.cur_thread());
            kutil.cur_thread().*.mutex_waiting = null;
            if (rc == c.SLP_INTR) {
                sched.unlock();
                return c.EINTR;
            }
            km.*.locks = 1;
            @as(*ffi.List, @ptrCast(&kutil.cur_thread().*.mutexes)).insertAfter(&km.*.link);
            ffi.deadlock.record_lock(m, c.LOCK_TYPE_MUTEX);
        }
    }
    sched.unlock();
    return 0;
}

pub fn tryLock(mp: ?*c.mutex_t) callconv(.c) c_int {
    var m: c.mutex_t = undefined;

    sched.lock();
    const error_code = copyin(mp, &m);
    if (error_code != 0) {
        sched.unlock();
        return error_code;
    }

    const km: *ffi.sync.Mutex = @ptrCast(m);
    var err: c_int = 0;
    if (km.*.holder == kutil.cur_thread()) {
        km.*.locks += 1;
    } else {
        if (km.*.holder != null) {
            err = c.EBUSY;
        } else {
            km.*.locks = 1;
            km.*.holder = kutil.cur_thread();
            @as(*ffi.List, @ptrCast(&kutil.cur_thread().*.mutexes)).insertAfter(&km.*.link);
            ffi.deadlock.record_lock(m, c.LOCK_TYPE_MUTEX);
        }
    }
    sched.unlock();
    return err;
}

pub fn unlock(mp: ?*c.mutex_t) callconv(.c) c_int {
    var m: c.mutex_t = undefined;

    sched.lock();
    const error_code = copyin(mp, &m);
    if (error_code != 0) {
        sched.unlock();
        return error_code;
    }

    if (m.*.holder != kutil.cur_thread() or m.*.locks <= 0) {
        sched.unlock();
        return c.EPERM;
    }

    const km: *ffi.sync.Mutex = @ptrCast(m);
    km.*.locks -= 1;
    if (km.*.locks == 0) {
        ffi.deadlock.record_unlock(m);
        @as(*ffi.List, @ptrCast(&km.*.link)).remove();
        prio_uninherit(kutil.cur_thread());

        km.*.holder = sched.wakeone(&km.*.event);
        if (km.*.holder) |holder| {
            holder.*.mutex_waiting = null;
        }

        km.*.priority = if (km.*.holder) |holder| holder.*.priority else c.MINPRI;
    }
    sched.unlock();
    return 0;
}

pub fn cancel(t: c.thread_t) callconv(.c) void {
    const head = @as(*ffi.List, @ptrCast(&t.*.mutexes));
    while (!head.isEmpty()) {
        const n = head.first();
        const m = n.entry(ffi.sync.Mutex, "link");
        m.*.locks = 0;
        @as(*ffi.List, @ptrCast(&m.*.link)).remove();

        const holder = sched.wakeone(&m.*.event);
        if (holder) |h| {
            h.*.mutex_waiting = null;
            m.*.locks = 1;
            @as(*ffi.List, @ptrCast(&h.*.mutexes)).insertAfter(&m.*.link);
        }
        m.*.holder = holder;
    }
}

pub fn setpri(t: c.thread_t, pri: c_int) callconv(.c) void {
    if (t.*.mutex_waiting != null and pri < t.*.priority) {
        _ = prio_inherit(t);
    }
}

comptime {
    if (@import("root") == @This()) {
        @export(&init, .{ .name = "mutex_init", .linkage = .strong });
        @export(&destroy, .{ .name = "mutex_destroy", .linkage = .strong });
        @export(&cleanup, .{ .name = "mutex_cleanup", .linkage = .strong });
        @export(&lock, .{ .name = "mutex_lock", .linkage = .strong });
        @export(&tryLock, .{ .name = "mutex_trylock", .linkage = .strong });
        @export(&unlock, .{ .name = "mutex_unlock", .linkage = .strong });
        @export(&cancel, .{ .name = "mutex_cancel", .linkage = .strong });
        @export(&setpri, .{ .name = "mutex_setpri", .linkage = .strong });
    }
}
