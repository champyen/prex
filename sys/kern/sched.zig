const std = @import("std");
const builtin = @import("builtin");

const c = @import("c").c;

const ffi = @import("ffi");
const lib = ffi.lib;
const hal = ffi.hal;
const kern = ffi.kern;
const kutil = ffi.kutil;
const smp = ffi.smp;
const sync = ffi.sync;
const thread = ffi.thread;
const timer = ffi.timer;
const vm = ffi.vm;

pub var kernel_lock: hal.Spinlock = .{ .value = 0 };
var runq: [hal.NPRI]lib.Queue = undefined;
var wakeq: lib.Queue = undefined;
var dpcq: lib.Queue = undefined;
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
    runq[@intCast(t.*.priority)].enqueue(lib.IntrusiveQueue(kern.Thread, lib.Queue, "sched_link").node(t));
    if (t.*.priority < maxpri) {
        maxpri = t.*.priority;
        if (kutil.get_curthread()) |ct| {
            ct.resched = 1;
        }
    }
}

fn runq_insert(t: kern.ThreadRef) void {
    runq[@intCast(t.*.priority)].insert(lib.IntrusiveQueue(kern.Thread, lib.Queue, "sched_link").node(t));
    if (t.*.priority < maxpri) {
        maxpri = t.*.priority;
    }
}

fn runq_dequeue() kern.ThreadRef {
    if (maxpri >= hal.PRI_IDLE) {
        return &thread.idle_thread;
    }
    const q = runq[@intCast(maxpri)].dequeue().?;
    const t = q.entry(kern.Thread, "sched_link");
    if (runq[@intCast(maxpri)].isEmpty()) {
        maxpri = runq_getbest();
    }
    return t;
}

fn runq_remove(t: kern.ThreadRef) void {
    lib.IntrusiveQueue(kern.Thread, lib.Queue, "sched_link").node(t).remove();
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

pub fn wakeq_flush() callconv(.c) void {
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

pub fn setrun(t: kern.ThreadRef) callconv(.c) void {
    wakeq.enqueue(lib.IntrusiveQueue(kern.Thread, lib.Queue, "sched_link").node(t));
    timer.stop(&t.*.timeout);
}

pub fn sleep_timeout(arg: ?*anyopaque) callconv(.c) void {
    const t: kern.ThreadRef = @ptrCast(@alignCast(arg));
    unsleep(t, kern.SLP_TIMEOUT);
}

pub fn swtch() callconv(.c) void {
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

pub fn tsleep(evt: *hal.Event, msec: c_ulong) callconv(.c) c_int {
    const e: *sync.Event = @ptrCast(evt);
    lock();
    const s = hal.splhigh();

    curthread().*.slpevt = @as([*c]hal.Event, @ptrCast(e));
    curthread().*.state |= @as(c_int, kern.TS_SLEEP);
    e.*.sleepq.enqueue(lib.IntrusiveQueue(kern.Thread, lib.Queue, "sched_link").node(curthread()));

    if (msec != 0) {
        timer.callout(&curthread().*.timeout, @intCast(msec), sleep_timeout, curthread());
    }

    wakeq_flush();
    swtch();

    hal.splx(s);
    unlock();
    return curthread().*.slpret;
}

pub fn wakeup(evt: *hal.Event) callconv(.c) void {
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

pub fn wakeone(evt: *hal.Event) callconv(.c) kern.ThreadRef {
    const e: *sync.Event = @ptrCast(evt);
    lock();
    const s = hal.splhigh();
    var result: kern.ThreadRef = null;
    const head: *lib.Queue = @ptrCast(&e.*.sleepq);
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
        lib.IntrusiveQueue(kern.Thread, lib.Queue, "sched_link").node(top).remove();
        top.*.slpret = 0;
        setrun(top);
        result = top;
    }
    hal.splx(s);
    unlock();
    return result;
}

pub fn unsleep(t: kern.ThreadRef, result: c_int) callconv(.c) void {
    lock();
    if (t.*.state & kern.TS_SLEEP != 0) {
        const s = hal.splhigh();
        lib.IntrusiveQueue(kern.Thread, lib.Queue, "sched_link").node(t).remove();
        t.*.slpret = result;
        setrun(t);
        hal.splx(s);
    }
    unlock();
}

pub fn yield() callconv(.c) void {
    lock();
    if (!runq[@intCast(curthread().*.priority)].isEmpty()) {
        curthread().*.resched = 1;
    }
    unlock();
}

pub fn @"suspend"(t: kern.ThreadRef) callconv(.c) void {
    if (t.*.state == kern.TS_RUN) {
        if (t == curthread()) {
            curthread().*.resched = 1;
        } else {
            runq_remove(t);
        }
    }
    t.*.state |= @as(c_int, kern.TS_SUSP);
}

pub fn @"resume"(t: kern.ThreadRef) callconv(.c) void {
    if (t.*.state & kern.TS_SUSP != 0) {
        t.*.state &= ~@as(c_int, kern.TS_SUSP);
        if (t.*.state == kern.TS_RUN) {
            runq_enqueue(t);
        }
    }
}

pub fn tick() callconv(.c) void {
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

pub fn start(t: kern.ThreadRef, pri: c_int, policy: c_int) callconv(.c) void {
    t.*.state = kern.TS_RUN | @as(c_int, kern.TS_SUSP);
    t.*.policy = policy;
    t.*.priority = pri;
    t.*.basepri = pri;
    if (t.*.policy == kern.SCHED_RR) {
        t.*.timeleft = hal.QUANTUM;
    }
}

pub fn stop(t: kern.ThreadRef) callconv(.c) void {
    if (t == curthread()) {
        curthread().*.locks = 1;
        curthread().*.resched = 1;
    } else {
        if (t.*.state == kern.TS_RUN) {
            runq_remove(t);
        } else if (t.*.state & kern.TS_SLEEP != 0) {
            lib.IntrusiveQueue(kern.Thread, lib.Queue, "sched_link").node(t).remove();
        }
    }
    timer.stop(&t.*.timeout);
    t.*.state = kern.TS_EXIT;
}

pub fn lock() callconv(.c) void {
    const s = hal.splhigh();
    if (curthread().*.locks == 0) {
        if (comptime @hasDecl(c, "CONFIG_SMP")) {
            kernel_lock.lock();
        }
    }
    curthread().*.locks += 1;
    hal.splx(s);
}

pub fn unlock() callconv(.c) void {
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

pub fn bklUnlock() callconv(.c) void {
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        kernel_lock.unlock();
    }
}

pub fn getpri(t: kern.ThreadRef) callconv(.c) c_int {
    return t.*.priority;
}

pub fn setpri(t: kern.ThreadRef, basepri: c_int, pri: c_int) callconv(.c) void {
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

pub fn getpolicy(t: kern.ThreadRef) callconv(.c) c_int {
    return t.*.policy;
}

pub fn setpolicy(t: kern.ThreadRef, policy: c_int) callconv(.c) c_int {
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

pub fn dpc(dpc_ptr: *hal.Dpc, fn_ptr: ?*const fn (?*anyopaque) callconv(.c) void, arg: ?*anyopaque) callconv(.c) void {
    lock();
    const s = hal.splhigh();
    dpc_ptr.*.func = fn_ptr;
    dpc_ptr.*.arg = arg;
    if (dpc_ptr.*.state != hal.DPC_PENDING) {
        dpcq.enqueue(lib.IntrusiveQueue(hal.Dpc, lib.Queue, "link").node(dpc_ptr));
    }
    dpc_ptr.*.state = hal.DPC_PENDING;
    hal.splx(s);
    wakeup(@ptrCast(&dpc_event));
    unlock();
}

pub fn dpc_thread(dummy: ?*anyopaque) callconv(.c) void {
    _ = dummy;
    _ = hal.splhigh();
    while (true) {
        _ = tsleep(@ptrCast(&dpc_event), 0);
        while (!dpcq.isEmpty()) {
            const q = dpcq.dequeue().?;
            const dpc_val = q.entry(hal.Dpc, "link");
            dpc_val.*.state = hal.DPC_FREE;
            _ = hal.spl0();
            if (dpc_val.*.func) |f| {
                f(dpc_val.*.arg);
            }
            _ = hal.splhigh();
        }
    }
}

pub fn init() callconv(.c) void {
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
