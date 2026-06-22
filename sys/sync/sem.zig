const std = @import("std");
const builtin = @import("builtin");

const c = @import("c").c;

var sem_list: ?*sync.Sem = null;

const ffi = @import("ffi");
const deadlock = ffi.deadlock;
const hal = ffi.hal;
const kern = ffi.kern;
const sync = ffi.sync;
const kutil = ffi.kutil;
const smp = ffi.smp;
const kmem = ffi.kmem;
const sched = ffi.sched;
const thread = ffi.thread;

fn valid(s: kern.SemRef) bool {
    const ks: *sync.Sem = @ptrCast(s);
    var tmp = sem_list;
    while (tmp) |current| {
        if (current == ks) {
            return true;
        }
        tmp = current.*.next;
    }
    return false;
}

fn reference(s: kern.SemRef) void {
    s.*.refcnt += 1;
}

fn release(s: kern.SemRef) void {
    const ks: *sync.Sem = @ptrCast(s);
    ks.*.refcnt -= 1;
    if (ks.*.refcnt > 0) {
        return;
    }
    ffi.IntrusiveList(sync.Sem, ffi.List, "task_link").node(ks).remove();
    ks.*.owner.*.nsyncs -= 1;

    var sp: *?*sync.Sem = &sem_list;
    while (sp.*) |current| {
        if (current == ks) {
            sp.* = current.*.next;
            break;
        }
        sp = @ptrCast(&current.*.next);
    }
    kmem.free(s);
}

fn copyin(usp: ?*kern.SemRef, ksp: ?*kern.SemRef) c_int {
    var s: kern.SemRef = undefined;
    if (hal.copyin(@as(?*const anyopaque, @ptrCast(usp)), @as(?*anyopaque, @ptrCast(&s)), @sizeOf(kern.SemRef)) != 0 or !valid(s)) {
        return kern.Errno.EINVAL;
    }
    ksp.?.* = s;
    return 0;
}

pub fn init(sp: ?*kern.SemRef, value: c_uint) callconv(.c) c_int {
    const self = kutil.cur_task();
    if (self.*.nsyncs >= hal.MAXSYNCS) {
        return kern.Errno.EAGAIN;
    }
    if (value > sync.MAXSEMVAL) {
        return kern.Errno.EINVAL;
    }

    var s: kern.SemRef = undefined;
    if (hal.copyin(@as(?*const anyopaque, @ptrCast(sp)), @as(?*anyopaque, @ptrCast(&s)), @sizeOf(kern.SemRef)) != 0) {
        return kern.Errno.EFAULT;
    }

    sched.lock();
    defer sched.unlock();
    if (s != null and valid(s)) {
        const ks: *sync.Sem = @ptrCast(s);
        if (ks.*.owner != self) {
            return kern.Errno.EINVAL;
        }
        if (!ks.*.event.sleepq.isEmpty()) {
            return kern.Errno.EBUSY;
        }
        ks.*.value = value;
    } else {
        const mem = kmem.alloc(@sizeOf(sync.Sem)) orelse return kern.Errno.ENOSPC;
        s = @ptrCast(@alignCast(mem));
        errdefer kmem.free(s);
        if (hal.copyout(@as(?*const anyopaque, @ptrCast(&s)), @as(?*anyopaque, @ptrCast(sp)), @sizeOf(kern.SemRef)) != 0) {
            return kern.Errno.EFAULT;
        }
        const ks: *sync.Sem = @ptrCast(s);
        sync.event_init(&s.*.event, "semaphore");
        ks.*.owner = self;
        ks.*.refcnt = 1;
        ks.*.value = value;

        const TL = ffi.IntrusiveList(kern.Task, ffi.List, "sems");
        const ML = ffi.IntrusiveList(sync.Sem, ffi.List, "task_link");
        TL.node(self).insertAfter(ML.node(ks));
        self.*.nsyncs += 1;
        ks.*.next = sem_list;
        sem_list = ks;
    }
    return 0;
}

pub fn destroy(sp: ?*kern.SemRef) callconv(.c) c_int {
    var s: kern.SemRef = undefined;

    sched.lock();
    defer sched.unlock();
    if (copyin(sp, &s) != 0 or s.*.owner != kutil.cur_task()) {
        return kern.Errno.EINVAL;
    }
    const ks: *sync.Sem = @ptrCast(s);
    if (!ks.*.event.sleepq.isEmpty() or ks.*.value == 0) {
        return kern.Errno.EBUSY;
    }
    release(s);
    return 0;
}

pub fn wait(sp: ?*kern.SemRef, timeout: c_ulong) callconv(.c) c_int {
    var s: kern.SemRef = undefined;
    var error_code: c_int = 0;

    sched.lock();
    defer sched.unlock();
    if (copyin(sp, &s) != 0) {
        return kern.Errno.EINVAL;
    }
    reference(s);

    const ks: *sync.Sem = @ptrCast(s);
    while (ks.*.value == 0) {
        deadlock.sleep(@ptrCast(ks), "semaphore");
        const rc = sched.tsleep(&ks.*.event, @intCast(timeout));
        deadlock.stop_sleep();
        if (rc == kern.SLP_TIMEOUT) {
            error_code = kern.Errno.ETIMEDOUT;
            break;
        }
        if (rc == kern.SLP_INTR) {
            error_code = kern.Errno.EINTR;
            break;
        }
    }
    if (error_code == 0) {
        ks.*.value -= 1;
    }

    release(s);
    return error_code;
}

pub fn tryWait(sp: ?*kern.SemRef) callconv(.c) c_int {
    var s: kern.SemRef = undefined;

    sched.lock();
    defer sched.unlock();
    if (copyin(sp, &s) != 0) {
        return kern.Errno.EINVAL;
    }
    if (s.*.value == 0) {
        return kern.Errno.EAGAIN;
    }
    s.*.value -= 1;
    return 0;
}

pub fn post(sp: ?*kern.SemRef) callconv(.c) c_int {
    var s: kern.SemRef = undefined;

    sched.lock();
    defer sched.unlock();
    if (copyin(sp, &s) != 0) {
        return kern.Errno.EINVAL;
    }
    if (s.*.value >= sync.MAXSEMVAL) {
        return kern.Errno.ERANGE;
    }
    const ks: *sync.Sem = @ptrCast(s);
    ks.*.value += 1;
    if (ks.*.value > 0) {
        _ = sched.wakeone(&ks.*.event);
    }

    return 0;
}

pub fn postKernel(s: kern.SemRef) callconv(.c) c_int {
    sched.lock();
    defer sched.unlock();
    if (!valid(s)) {
        return kern.Errno.EINVAL;
    }
    const ks: *sync.Sem = @ptrCast(s);
    if (ks.*.value >= sync.MAXSEMVAL) {
        return kern.Errno.ERANGE;
    }
    ks.*.value += 1;
    if (ks.*.value > 0) {
        _ = sched.wakeone(&ks.*.event);
    }

    return 0;
}

pub fn getValue(sp: ?*kern.SemRef, value: ?*c_uint) callconv(.c) c_int {
    var s: kern.SemRef = undefined;

    sched.lock();
    defer sched.unlock();
    if (copyin(sp, &s) != 0) {
        return kern.Errno.EINVAL;
    }
    if (hal.copyout(@as(?*const anyopaque, @ptrCast(&s.*.value)), @as(?*anyopaque, @ptrCast(value)), @sizeOf(@TypeOf(s.*.value))) != 0) {
        return kern.Errno.EFAULT;
    }
    return 0;
}

pub fn cleanup(task: kern.TaskRef) callconv(.c) void {
    const TL = ffi.IntrusiveList(kern.Task, ffi.List, "sems");
    const head = TL.node(task);
    var n = head.first();
    while (n != head) {
        const next = n.nextNode();
        const s = n.entry(sync.Sem, "task_link");
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
