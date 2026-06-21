const std = @import("std");
const builtin = @import("builtin");

const c = @import("c").c;

var sem_list: ?*ffi.sync.Sem = null;

const ffi = @import("ffi");
const kutil = ffi.kutil;
const smp = ffi.smp;
const kmem = ffi.kmem;
const sched = ffi.sched;
const thread = ffi.thread;

fn valid(s: c.sem_t) bool {
    const ks: *ffi.sync.Sem = @ptrCast(s);
    var tmp = sem_list;
    while (tmp) |current| {
        if (current == ks) {
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
    const ks: *ffi.sync.Sem = @ptrCast(s);
    ks.*.refcnt -= 1;
    if (ks.*.refcnt > 0) {
        return;
    }
    @as(*ffi.List, @ptrCast(&ks.*.task_link)).remove();
    ks.*.owner.*.nsyncs -= 1;

    var sp: *?*ffi.sync.Sem = &sem_list;
    while (sp.*) |current| {
        if (current == ks) {
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
        const ks: *ffi.sync.Sem = @ptrCast(s);
        if (ks.*.owner != self) {
            sched.unlock();
            return c.EINVAL;
        }
        if (!ks.*.event.sleepq.isEmpty()) {
            sched.unlock();
            return c.EBUSY;
        }
        ks.*.value = value;
    } else {
        const mem = kmem.alloc(@sizeOf(ffi.sync.Sem)) orelse {
            sched.unlock();
            return c.ENOSPC;
        };
        s = @ptrCast(@alignCast(mem));
        if (ffi.hal.copyout(@as(?*const anyopaque, @ptrCast(&s)), @as(?*anyopaque, @ptrCast(sp)), @sizeOf(c.sem_t)) != 0) {
            kmem.free(s);
            sched.unlock();
            return c.EFAULT;
        }
        const ks: *ffi.sync.Sem = @ptrCast(s);
        c.event_init(&s.*.event, "semaphore");
        ks.*.owner = self;
        ks.*.refcnt = 1;
        ks.*.value = value;

        @as(*ffi.List, @ptrCast(&self.*.sems)).insertAfter(@as(*ffi.List, @ptrCast(&ks.*.task_link)));
        self.*.nsyncs += 1;
        ks.*.next = sem_list;
        sem_list = ks;
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
    const ks: *ffi.sync.Sem = @ptrCast(s);
    if (!ks.*.event.sleepq.isEmpty() or ks.*.value == 0) {
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

    const ks: *ffi.sync.Sem = @ptrCast(s);
    while (ks.*.value == 0) {
        ffi.deadlock.sleep(@ptrCast(ks), "semaphore");
        const rc = sched.tsleep(&ks.*.event, @intCast(timeout));
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
        ks.*.value -= 1;
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
    const ks: *ffi.sync.Sem = @ptrCast(s);
    ks.*.value += 1;
    if (ks.*.value > 0) {
        _ = sched.wakeone(&ks.*.event);
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
    const ks: *ffi.sync.Sem = @ptrCast(s);
    if (ks.*.value >= c.MAXSEMVAL) {
        sched.unlock();
        return c.ERANGE;
    }
    ks.*.value += 1;
    if (ks.*.value > 0) {
        _ = sched.wakeone(&ks.*.event);
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

pub fn cleanup(task: ffi.kern.TaskRef) callconv(.c) void {
    const head = @as(*ffi.List, @ptrCast(&task.*.sems));
    var n = head.first();
    while (n != head) {
        const next = n.nextNode();
        const s = n.entry(ffi.sync.Sem, "task_link");
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
