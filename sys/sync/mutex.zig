const std = @import("std");
const builtin = @import("builtin");

const c = @import("c").c;

const ffi = @import("ffi");
const IntrusiveList = ffi.IntrusiveList;
const List = ffi.List;
const deadlock = ffi.deadlock;
const hal = ffi.hal;
const kern = ffi.kern;
const kmem = ffi.kmem;
const kutil = ffi.kutil;
const sched = ffi.sched;
const sync = ffi.sync;
inline fn is_mutex_initializer(m: kern.MutexRef) bool {
    if (m) |ptr| {
        return @intFromPtr(ptr) == 0x4d496e69;
    }
    return false;
}

fn valid(m: kern.MutexRef) c_int {
    const km: *sync.Mutex = @ptrCast(m);
    const TL = IntrusiveList(kern.Task, List, "mutexes");
    const self = kutil.cur_task();
    const head = TL.node(self);
    var n = head.first();
    while (n != head) : (n = n.nextNode()) {
        const tmp = n.entry(sync.Mutex, "task_link");
        if (tmp == km) {
            return 1;
        }
    }
    return 0;
}

fn copyin(ump: ?*kern.MutexRef, kmp: ?*kern.MutexRef) c_int {
    var m: kern.MutexRef = undefined;
    if (hal.copyin(@as(?*const anyopaque, @ptrCast(ump)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(kern.MutexRef)) != 0) {
        return kern.Errno.EFAULT;
    }

    if (is_mutex_initializer(m)) {
        const error_code = init(ump);
        if (error_code != 0) {
            return error_code;
        }
        _ = hal.copyin(@as(?*const anyopaque, @ptrCast(ump)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(kern.MutexRef));
    } else {
        if (valid(m) == 0) {
            return kern.Errno.EINVAL;
        }
    }
    kmp.?.* = m;
    return 0;
}

fn prio_inherit(waiter: kern.ThreadRef) c_int {
    var m: kern.MutexRef = waiter.*.mutex_waiting;
    var holder: kern.ThreadRef = undefined;
    var count: c_int = 0;
    var iters: u32 = 0;

    while (m != null) {
        holder = m.*.holder;
        deadlock.check_loop("prio_inherit", &iters);

        if (holder == waiter) {
            return kern.Errno.EDEADLK;
        }

        if (holder.*.priority > waiter.*.priority) {
            sched.set_pri(holder, holder.*.basepri, waiter.*.priority);
            m.*.priority = waiter.*.priority;
        }

        m = @ptrCast(holder.*.mutex_waiting);

        count += 1;
        if (count >= sync.MAXINHERIT) {
            break;
        }
    }
    return 0;
}

fn prio_uninherit(t: kern.ThreadRef) void {
    if (t.*.priority == t.*.basepri) {
        return;
    }

    var maxpri = t.*.basepri;
    const ML = IntrusiveList(kern.Thread, List, "mutexes");
    const head = ML.node(t);
    var n = head.first();
    while (n != head) : (n = n.nextNode()) {
        const m = n.entry(sync.Mutex, "link");
        if (m.*.priority < maxpri) {
            maxpri = m.*.priority;
        }
    }

    sched.set_pri(t, t.*.basepri, maxpri);
}

pub fn init(mp: ?*kern.MutexRef) callconv(.c) c_int {
    const self = kutil.cur_task();
    if (self.*.nsyncs >= hal.MAXSYNCS) {
        return kern.Errno.EAGAIN;
    }

    const mem = kmem.alloc(@sizeOf(sync.Mutex)) orelse return kern.Errno.ENOMEM;
    const m: kern.MutexRef = @ptrCast(@alignCast(mem));
    errdefer kmem.free(m);

    sync.event_init(&m.*.event, "mutex");
    m.*.owner = self;
    m.*.holder = null;
    m.*.priority = hal.MINPRI;

    if (hal.copyout(@as(?*const anyopaque, @ptrCast(&m)), @as(?*anyopaque, @ptrCast(mp)), @sizeOf(kern.MutexRef)) != 0) {
        return kern.Errno.EFAULT;
    }

    sched.lock();
    defer sched.unlock();
    const TL = IntrusiveList(kern.Task, List, "mutexes");
    const ML = IntrusiveList(sync.Mutex, List, "task_link");
    TL.node(self).insertAfter(ML.node(m.?));
    self.*.nsyncs += 1;
    return 0;
}

fn deallocate(m: kern.MutexRef) void {
    m.*.owner.*.nsyncs -= 1;
    IntrusiveList(sync.Mutex, List, "task_link").node(m.?).remove();
    kmem.free(m);
}

pub fn destroy(mp: ?*kern.MutexRef) callconv(.c) c_int {
    var m: kern.MutexRef = undefined;
    sched.lock();
    defer sched.unlock();
    if (hal.copyin(@as(?*const anyopaque, @ptrCast(mp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(kern.MutexRef)) != 0) {
        return kern.Errno.EFAULT;
    }
    if (valid(m) == 0) {
        return kern.Errno.EINVAL;
    }
    const km: *sync.Mutex = @ptrCast(m);
    if (km.*.holder != null or !km.*.event.sleepq.isEmpty()) {
        return kern.Errno.EBUSY;
    }
    deallocate(m);
    return 0;
}

pub fn cleanup(task: kern.TaskRef) callconv(.c) void {
    const TL = IntrusiveList(kern.Task, List, "mutexes");
    const head = TL.node(task);
    while (!head.isEmpty()) {
        const n = head.first();
        const m = n.entry(sync.Mutex, "task_link");
        deallocate(@ptrCast(m));
    }
}

pub fn lock(mp: ?*kern.MutexRef) callconv(.c) c_int {
    var m: kern.MutexRef = undefined;

    sched.lock();
    defer sched.unlock();
    const error_code = copyin(mp, &m);
    if (error_code != 0) {
        return error_code;
    }

    const km: *sync.Mutex = @ptrCast(m);
    if (km.*.holder == kutil.cur_thread()) {
        km.*.locks += 1;
    } else {
        if (km.*.holder == null) {
            km.*.priority = kutil.cur_thread().*.priority;
            km.*.locks = 1;
            km.*.holder = kutil.cur_thread();
            IntrusiveList(kern.Thread, List, "mutexes").node(kutil.cur_thread()).insertAfter(&km.*.link);
            deadlock.record_lock(m, hal.LOCK_TYPE_MUTEX);
        } else {
            deadlock.mutex_wait(m, kutil.cur_thread());
            kutil.cur_thread().*.mutex_waiting = m;
            const inherit_err = prio_inherit(kutil.cur_thread());
            if (inherit_err != 0) {
                deadlock.mutex_stop_wait(kutil.cur_thread());
                kutil.cur_thread().*.mutex_waiting = null;
                return inherit_err;
            }
            const rc = sched.tsleep(&km.*.event, 0);
            deadlock.mutex_stop_wait(kutil.cur_thread());
            kutil.cur_thread().*.mutex_waiting = null;
            if (rc == kern.SLP_INTR) {
                return kern.Errno.EINTR;
            }
            km.*.locks = 1;
            IntrusiveList(kern.Thread, List, "mutexes").node(kutil.cur_thread()).insertAfter(&km.*.link);
            deadlock.record_lock(m, hal.LOCK_TYPE_MUTEX);
        }
    }
    return 0;
}

pub fn tryLock(mp: ?*kern.MutexRef) callconv(.c) c_int {
    var m: kern.MutexRef = undefined;

    sched.lock();
    defer sched.unlock();
    const error_code = copyin(mp, &m);
    if (error_code != 0) {
        return error_code;
    }

    const km: *sync.Mutex = @ptrCast(m);
    var err: c_int = 0;
    if (km.*.holder == kutil.cur_thread()) {
        km.*.locks += 1;
    } else {
        if (km.*.holder != null) {
            err = kern.Errno.EBUSY;
        } else {
            km.*.locks = 1;
            km.*.holder = kutil.cur_thread();
            IntrusiveList(kern.Thread, List, "mutexes").node(kutil.cur_thread()).insertAfter(&km.*.link);
            deadlock.record_lock(m, hal.LOCK_TYPE_MUTEX);
        }
    }
    return err;
}

pub fn unlock(mp: ?*kern.MutexRef) callconv(.c) c_int {
    var m: kern.MutexRef = undefined;

    sched.lock();
    defer sched.unlock();
    const error_code = copyin(mp, &m);
    if (error_code != 0) {
        return error_code;
    }

    if (m.*.holder != kutil.cur_thread() or m.*.locks <= 0) {
        return kern.Errno.EPERM;
    }

    const km: *sync.Mutex = @ptrCast(m);
    km.*.locks -= 1;
    if (km.*.locks == 0) {
        deadlock.record_unlock(m);
        IntrusiveList(sync.Mutex, List, "link").node(km).remove();
        prio_uninherit(kutil.cur_thread());

        km.*.holder = sched.wakeone(&km.*.event);
        if (km.*.holder) |holder| {
            holder.*.mutex_waiting = null;
        }

        km.*.priority = if (km.*.holder) |holder| holder.*.priority else hal.MINPRI;
    }
    return 0;
}

pub fn cancel(t: kern.ThreadRef) callconv(.c) void {
    const TL = IntrusiveList(kern.Thread, List, "mutexes");
    const head = TL.node(t);
    while (!head.isEmpty()) {
        const n = head.first();
        const m = n.entry(sync.Mutex, "link");
        m.*.locks = 0;
        IntrusiveList(sync.Mutex, List, "link").node(m).remove();

        const holder = sched.wakeone(&m.*.event);
        if (holder) |h| {
            h.*.mutex_waiting = null;
            m.*.locks = 1;
            TL.node(h).insertAfter(&m.*.link);
        }
        m.*.holder = holder;
    }
}

pub fn setpri(t: kern.ThreadRef, pri: c_int) callconv(.c) void {
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
