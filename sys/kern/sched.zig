const std = @import("std");
const builtin = @import("builtin");

const c = @import("c").c;

const ffi = @import("ffi");
const hal = ffi.hal;
const kern = ffi.kern;
const sync = ffi.sync;
const vm = ffi.vm;
const kutil = ffi.kutil;
const timer = ffi.timer;
const thread = ffi.thread;
const smp = ffi.smp;

pub var kernel_lock: hal.Spinlock = .{ .value = 0 };
var runq: [hal.NPRI]ffi.Queue = undefined;
var wakeq: ffi.Queue = undefined;
var dpcq: ffi.Queue = undefined;
var dpc_event: sync.Event = undefined;
var maxpri: c_int = hal.PRI_IDLE;

fn runq_getbest() c_int {
    var pri: c_int = 0;
    while (pri < hal.MINPRI) : (pri += 1) {
        if (!runq[@intCast(pri)].isEmpty()) {
            break;
        }
    }
    return pri;
}

fn runq_enqueue(t: kern.ThreadRef) void {
    runq[@intCast(t.*.priority)].enqueue(ffi.IntrusiveQueue(kern.Thread, ffi.Queue, "sched_link").node(t));
    if (t.*.priority < maxpri) {
        maxpri = t.*.priority;
        if (kutil.get_curthread()) |ct| {
            ct.resched = 1;
        }
    }
}

fn runq_insert(t: kern.ThreadRef) void {
    runq[@intCast(t.*.priority)].insert(ffi.IntrusiveQueue(kern.Thread, ffi.Queue, "sched_link").node(t));
    if (t.*.priority < maxpri) {
        maxpri = t.*.priority;
    }
}

fn runq_dequeue() kern.ThreadRef {
    if (maxpri >= hal.PRI_IDLE) {
        return &ffi.thread.idle_thread;
    }
    const q = runq[@intCast(maxpri)].dequeue().?;
    const t = q.entry(kern.Thread, "sched_link");
    if (runq[@intCast(maxpri)].isEmpty()) {
        maxpri = runq_getbest();
    }
    return t;
}

fn runq_remove(t: kern.ThreadRef) void {
    t.*.sched_link.remove();
    maxpri = runq_getbest();
}


fn set_curthread(t: kern.ThreadRef) void {
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        smp.get_cpu_control().*.active_thread = t;
    } else {
        thread.curthread = t;
    }
}

fn curthread() *kern.Thread {
    return kutil.get_curthread().?;
}

fn wakeq_flush() callconv(.c) void {
    while (!wakeq.isEmpty()) {
        const q = wakeq.dequeue().?;
        const t = q.entry(kern.Thread, "sched_link");
        t.*.slpevt = null;
        t.*.state &= ~@as(c_int, kern.TS_SLEEP);
        if (t != curthread() and t.*.state == kern.TS_RUN) {
            runq_enqueue(t);
        }
    }
}

fn setrun(t: kern.ThreadRef) callconv(.c) void {
    wakeq.enqueue(ffi.IntrusiveQueue(kern.Thread, ffi.Queue, "sched_link").node(t));
    timer.stop(&t.*.timeout);
}

fn sleep_timeout(arg: ?*anyopaque) callconv(.c) void {
    const t: kern.ThreadRef = @ptrCast(@alignCast(arg));
    unsleep(t, kern.SLP_TIMEOUT);
}

fn swtch() callconv(.c) void {
    const prev = curthread();
    if (prev.*.state == kern.TS_RUN and prev.*.priority < hal.PRI_IDLE) {
        if (prev.*.priority > maxpri) {
            runq_insert(prev);
        } else {
            runq_enqueue(prev);
        }
    }
    prev.*.resched = 0;

    const next = runq_dequeue();
    if (next == prev) {
        return;
    }
    set_curthread(next);

    if (prev.*.task != next.*.task) {
        vm.switch_map(next.*.task.*.map);
    }

    var locks: c_int = undefined;
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        locks = prev.*.locks;
        prev.*.locks = 0;
        if (locks > 0) {
            kernel_lock.unlock();
        }
    }

    hal.context_switch(&prev.*.ctx, &next.*.ctx);

    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        const s = hal.splhigh();
        kernel_lock.lock();
        curthread().*.locks = locks;
        hal.splx(s);
    }
}

fn tsleep(evt: *hal.Event, msec: c_ulong) callconv(.c) c_int {
    const e: *sync.Event = @ptrCast(evt);
    lock();
    const s = hal.splhigh();

    curthread().*.slpevt = @as([*c]hal.Event, @ptrCast(e));
    curthread().*.state |= @as(c_int, kern.TS_SLEEP);
    e.*.sleepq.enqueue(ffi.IntrusiveQueue(kern.Thread, ffi.Queue, "sched_link").node(curthread()));

    if (msec != 0) {
        timer.callout(&curthread().*.timeout, @intCast(msec), sleep_timeout, curthread());
    }

    wakeq_flush();
    swtch();

    hal.splx(s);
    unlock();
    return curthread().*.slpret;
}

fn wakeup(evt: *hal.Event) callconv(.c) void {
    const e: *sync.Event = @ptrCast(evt);
    lock();
    const s = hal.splhigh();
    while (!e.*.sleepq.isEmpty()) {
        const q = e.*.sleepq.dequeue().?;
        const t = q.entry(kern.Thread, "sched_link");
        t.*.slpret = 0;
        setrun(t);
    }
    hal.splx(s);
    unlock();
}

fn wakeone(evt: *hal.Event) callconv(.c) kern.ThreadRef {
    const e: *sync.Event = @ptrCast(evt);
    lock();
    const s = hal.splhigh();
    var result: kern.ThreadRef = null;
    const head: *ffi.Queue = @ptrCast(&e.*.sleepq);
    if (!head.isEmpty()) {
        var q = head.first();
        var top = q.entry(kern.Thread, "sched_link");
        while (q != head) {
            const t = q.entry(kern.Thread, "sched_link");
            if (t.*.priority < top.*.priority) {
                top = t;
            }
            q = q.nextNode();
        }
        top.*.sched_link.remove();
        top.*.slpret = 0;
        setrun(top);
        result = top;
    }
    hal.splx(s);
    unlock();
    return result;
}

fn unsleep(t: kern.ThreadRef, result: c_int) callconv(.c) void {
    lock();
    if (t.*.state & kern.TS_SLEEP != 0) {
        const s = hal.splhigh();
        t.*.sched_link.remove();
        t.*.slpret = result;
        setrun(t);
        hal.splx(s);
    }
    unlock();
}

fn yield() callconv(.c) void {
    lock();
    if (!runq[@intCast(curthread().*.priority)].isEmpty()) {
        curthread().*.resched = 1;
    }
    unlock();
}

fn @"suspend"(t: kern.ThreadRef) callconv(.c) void {
    if (t.*.state == kern.TS_RUN) {
        if (t == curthread()) {
            curthread().*.resched = 1;
        } else {
            runq_remove(t);
        }
    }
    t.*.state |= @as(c_int, kern.TS_SUSP);
}

fn @"resume"(t: kern.ThreadRef) callconv(.c) void {
    if (t.*.state & kern.TS_SUSP != 0) {
        t.*.state &= ~@as(c_int, kern.TS_SUSP);
        if (t.*.state == kern.TS_RUN) {
            runq_enqueue(t);
        }
    }
}

fn tick() callconv(.c) void {
    if (curthread().*.state != kern.TS_EXIT) {
        curthread().*.time += 1;
        if (curthread().*.policy == kern.SCHED_RR) {
            curthread().*.timeleft -= 1;
            if (curthread().*.timeleft <= 0) {
                curthread().*.timeleft += hal.QUANTUM;
                curthread().*.resched = 1;
            }
        }
    }
}

fn start(t: kern.ThreadRef, pri: c_int, policy: c_int) callconv(.c) void {
    t.*.state = kern.TS_RUN | @as(c_int, kern.TS_SUSP);
    t.*.policy = policy;
    t.*.priority = pri;
    t.*.basepri = pri;
    if (t.*.policy == kern.SCHED_RR) {
        t.*.timeleft = hal.QUANTUM;
    }
}

fn stop(t: kern.ThreadRef) callconv(.c) void {
    if (t == curthread()) {
        curthread().*.locks = 1;
        curthread().*.resched = 1;
    } else {
        if (t.*.state == kern.TS_RUN) {
            runq_remove(t);
        } else if (t.*.state & kern.TS_SLEEP != 0) {
            t.*.sched_link.remove();
        }
    }
    timer.stop(&t.*.timeout);
    t.*.state = kern.TS_EXIT;
}

fn lock() callconv(.c) void {
    const s = hal.splhigh();
    if (curthread().*.locks == 0) {
        if (comptime @hasDecl(c, "CONFIG_SMP")) {
            kernel_lock.lock();
        }
    }
    curthread().*.locks += 1;
    hal.splx(s);
}

fn unlock() callconv(.c) void {
    var s = hal.splhigh();
    if (curthread().*.locks == 1) {
        wakeq_flush();
        while (curthread().*.resched != 0) {
            swtch();
            hal.splx(s);
            s = hal.splhigh();
            wakeq_flush();
        }
        curthread().*.locks = 0;
        if (comptime @hasDecl(c, "CONFIG_SMP")) {
            kernel_lock.unlock();
        }
    } else {
        curthread().*.locks -= 1;
    }
    hal.splx(s);
}

fn bklUnlock() callconv(.c) void {
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        kernel_lock.unlock();
    }
}

fn getpri(t: kern.ThreadRef) callconv(.c) c_int {
    return t.*.priority;
}

fn setpri(t: kern.ThreadRef, basepri: c_int, pri: c_int) callconv(.c) void {
    t.*.basepri = basepri;
    if (t == curthread()) {
        t.*.priority = pri;
        maxpri = runq_getbest();
        if (pri != maxpri) {
            curthread().*.resched = 1;
        }
    } else {
        if (t.*.state == kern.TS_RUN) {
            runq_remove(t);
            t.*.priority = pri;
            runq_enqueue(t);
        } else {
            t.*.priority = pri;
        }
    }
}

fn getpolicy(t: kern.ThreadRef) callconv(.c) c_int {
    return t.*.policy;
}

fn setpolicy(t: kern.ThreadRef, policy: c_int) callconv(.c) c_int {
    var err: c_int = 0;
    switch (policy) {
        kern.SCHED_RR, kern.SCHED_FIFO => {
            t.*.timeleft = hal.QUANTUM;
            t.*.policy = policy;
        },
        else => {
            err = kern.Errno.EINVAL;
        },
    }
    return err;
}

fn dpc(dpc_ptr: *ffi.hal.Dpc, fn_ptr: ?*const fn (?*anyopaque) callconv(.c) void, arg: ?*anyopaque) callconv(.c) void {
    lock();
    const s = hal.splhigh();
    dpc_ptr.*.func = fn_ptr;
    dpc_ptr.*.arg = arg;
    if (dpc_ptr.*.state != hal.DPC_PENDING) {
        dpcq.enqueue(ffi.IntrusiveQueue(hal.Dpc, ffi.Queue, "link").node(dpc_ptr));
    }
    dpc_ptr.*.state = hal.DPC_PENDING;
    hal.splx(s);
    wakeup(@ptrCast(&dpc_event));
    unlock();
}

fn dpc_thread(dummy: ?*anyopaque) callconv(.c) void {
    _ = dummy;
    _ = hal.splhigh();
    while (true) {
        _ = tsleep(@ptrCast(&dpc_event), 0);
        while (!dpcq.isEmpty()) {
            const q = dpcq.dequeue().?;
            const dpc_val = q.entry(ffi.hal.Dpc, "link");
            dpc_val.*.state = hal.DPC_FREE;
            _ = hal.spl0();
            if (dpc_val.*.func) |f| {
                f(dpc_val.*.arg);
            }
            _ = hal.splhigh();
        }
    }
}

fn init() callconv(.c) void {
    {
        var i: c_int = 0;
        while (i < hal.NPRI) : (i += 1) {
            runq[@intCast(i)].init();
        }
    }
    {
        wakeq.init();
    }
    {
        dpcq.init();
    }
    {
        dpc_event.sleepq.init();
        dpc_event.name = "dpc";
    }
    maxpri = hal.PRI_IDLE;
    curthread().*.resched = 1;

    const t = thread.kcreate(dpc_thread, null, hal.PRI_DPC);
    if (t == null) {
        @panic("sched_init");
    }
}

comptime {
    if (@import("root") == @This()) {
        @export(&sleep_timeout, .{ .name = "sleep_timeout", .linkage = .strong });
        @export(&dpc_thread, .{ .name = "dpc_thread", .linkage = .strong });
        @export(&wakeq_flush, .{ .name = "wakeq_flush", .linkage = .strong });
        @export(&setrun, .{ .name = "sched_setrun", .linkage = .strong });
        @export(&swtch, .{ .name = "sched_swtch", .linkage = .strong });
        @export(&tsleep, .{ .name = "sched_tsleep", .linkage = .strong });
        @export(&wakeup, .{ .name = "sched_wakeup", .linkage = .strong });
        @export(&wakeone, .{ .name = "sched_wakeone", .linkage = .strong });
        @export(&unsleep, .{ .name = "sched_unsleep", .linkage = .strong });
        @export(&yield, .{ .name = "sched_yield", .linkage = .strong });
        @export(&@"suspend", .{ .name = "sched_suspend", .linkage = .strong });
        @export(&@"resume", .{ .name = "sched_resume", .linkage = .strong });
        @export(&tick, .{ .name = "sched_tick", .linkage = .strong });
        @export(&start, .{ .name = "sched_start", .linkage = .strong });
        @export(&stop, .{ .name = "sched_stop", .linkage = .strong });
        @export(&lock, .{ .name = "sched_lock", .linkage = .strong });
        @export(&unlock, .{ .name = "sched_unlock", .linkage = .strong });
        @export(&bklUnlock, .{ .name = "sched_bkl_unlock", .linkage = .strong });
        @export(&getpri, .{ .name = "sched_getpri", .linkage = .strong });
        @export(&setpri, .{ .name = "sched_setpri", .linkage = .strong });
        @export(&getpolicy, .{ .name = "sched_getpolicy", .linkage = .strong });
        @export(&setpolicy, .{ .name = "sched_setpolicy", .linkage = .strong });
        @export(&dpc, .{ .name = "sched_dpc", .linkage = .strong });
        @export(&init, .{ .name = "sched_init", .linkage = .strong });
    }
}
