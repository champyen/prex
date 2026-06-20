const std = @import("std");
const builtin = @import("builtin");

const c = @import("c").c;

const ffi = @import("ffi");
const kutil = ffi.kutil;
const hal = ffi.hal;
const timer = ffi.timer;
const thread = ffi.thread;
const smp = ffi.smp;

pub var kernel_lock: c.spinlock_t = 0;
var runq: [c.NPRI]c.struct_queue = undefined;
var wakeq: c.struct_queue = undefined;
var dpcq: c.struct_queue = undefined;
var dpc_event: c.struct_event = undefined;
var maxpri: c_int = c.PRI_IDLE;

fn runq_getbest() c_int {
    var pri: c_int = 0;
    while (pri < c.MINPRI) : (pri += 1) {
        if (!ffi.queue.empty(&runq[@intCast(pri)])) {
            break;
        }
    }
    return pri;
}

fn runq_enqueue(t: c.thread_t) void {
    ffi.queue.enqueue(&runq[@intCast(t.*.priority)], &t.*.sched_link);
    if (t.*.priority < maxpri) {
        maxpri = t.*.priority;
        if (kutil.get_curthread()) |ct| {
            ct.resched = 1;
        }
    }
}

fn runq_insert(t: c.thread_t) void {
    ffi.queue.insert(&runq[@intCast(t.*.priority)], &t.*.sched_link);
    if (t.*.priority < maxpri) {
        maxpri = t.*.priority;
    }
}

fn runq_dequeue() c.thread_t {
    if (maxpri >= c.PRI_IDLE) {
        return &c.idle_thread;
    }
    const q = ffi.queue.dequeue(&runq[@intCast(maxpri)]).?;
    const t: *c.struct_thread = @fieldParentPtr("sched_link", @as(*c.struct_queue, @ptrCast(q)));
    if (ffi.queue.empty(&runq[@intCast(maxpri)])) {
        maxpri = runq_getbest();
    }
    return t;
}

fn runq_remove(t: c.thread_t) void {
    ffi.queue.remove(&t.*.sched_link);
    maxpri = runq_getbest();
}


fn set_curthread(t: c.thread_t) void {
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        smp.get_cpu_control().*.active_thread = t;
    } else {
        thread.curthread = t;
    }
}

fn curthread() *c.struct_thread {
    return kutil.get_curthread().?;
}

fn wakeq_flush() callconv(.c) void {
    while (!ffi.queue.empty(&wakeq)) {
        const q = ffi.queue.dequeue(&wakeq).?;
        const t: *c.struct_thread = @fieldParentPtr("sched_link", @as(*c.struct_queue, @ptrCast(q)));
        t.*.slpevt = null;
        t.*.state &= ~@as(c_int, c.TS_SLEEP);
        if (t != curthread() and t.*.state == c.TS_RUN) {
            runq_enqueue(t);
        }
    }
}

fn setrun(t: c.thread_t) callconv(.c) void {
    ffi.queue.enqueue(&wakeq, &t.*.sched_link);
    timer.stop(&t.*.timeout);
}

fn sleep_timeout(arg: ?*anyopaque) callconv(.c) void {
    const t: c.thread_t = @ptrCast(@alignCast(arg));
    unsleep(t, c.SLP_TIMEOUT);
}

fn swtch() callconv(.c) void {
    const prev = curthread();
    if (prev.*.state == c.TS_RUN and prev.*.priority < c.PRI_IDLE) {
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
        ffi.vm.switch_map(next.*.task.*.map);
    }

    var locks: c_int = undefined;
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        locks = prev.*.locks;
        prev.*.locks = 0;
        if (locks > 0) {
            @atomicStore(c.spinlock_t, &kernel_lock, 0, .seq_cst);
        }
    }

    hal.context_switch(&prev.*.ctx, &next.*.ctx);

    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        const cpu = smp.get_cpu_control();
        var s = hal.splhigh();
        while (@atomicRmw(c.spinlock_t, &kernel_lock, .Xchg, 1, .seq_cst) != 0) {
            if (cpu.*.nest_count == 0) {
                hal.splx(s);
                while (kernel_lock != 0) {
                    hal.zig_memory_barrier();
                }
                s = hal.splhigh();
            } else {
                while (kernel_lock != 0) {
                    hal.zig_memory_barrier();
                }
            }
        }
        curthread().*.locks = locks;
        hal.splx(s);
    }
}

fn tsleep(evt: *c.struct_event, msec: c_ulong) callconv(.c) c_int {
    lock();
    const s = hal.splhigh();

    curthread().*.slpevt = evt;
    curthread().*.state |= @as(c_int, c.TS_SLEEP);
    ffi.queue.enqueue(&evt.*.sleepq, &curthread().*.sched_link);

    if (msec != 0) {
        timer.callout(&curthread().*.timeout, @intCast(msec), sleep_timeout, curthread());
    }

    wakeq_flush();
    swtch();

    hal.splx(s);
    unlock();
    return curthread().*.slpret;
}

fn wakeup(evt: *c.struct_event) callconv(.c) void {
    lock();
    const s = hal.splhigh();
    while (!ffi.queue.empty(&evt.*.sleepq)) {
        const q = ffi.queue.dequeue(&evt.*.sleepq).?;
        const t: *c.struct_thread = @fieldParentPtr("sched_link", @as(*c.struct_queue, @ptrCast(q)));
        t.*.slpret = 0;
        setrun(t);
    }
    hal.splx(s);
    unlock();
}

fn wakeone(evt: *c.struct_event) callconv(.c) c.thread_t {
    lock();
    const s = hal.splhigh();
    var result: c.thread_t = null;
    const head = &evt.*.sleepq;
    if (!ffi.queue.empty(head)) {
        var q = head.*.next;
        var top: *c.struct_thread = @fieldParentPtr("sched_link", @as(*c.struct_queue, @ptrCast(q)));
        while (q != head) {
            const t: *c.struct_thread = @fieldParentPtr("sched_link", @as(*c.struct_queue, @ptrCast(q)));
            if (t.*.priority < top.*.priority) {
                top = t;
            }
            q = q.*.next;
        }
        ffi.queue.remove(&top.*.sched_link);
        top.*.slpret = 0;
        setrun(top);
        result = top;
    }
    hal.splx(s);
    unlock();
    return result;
}

fn unsleep(t: c.thread_t, result: c_int) callconv(.c) void {
    lock();
    if (t.*.state & c.TS_SLEEP != 0) {
        const s = hal.splhigh();
        ffi.queue.remove(&t.*.sched_link);
        t.*.slpret = result;
        setrun(t);
        hal.splx(s);
    }
    unlock();
}

fn yield() callconv(.c) void {
    lock();
    if (!ffi.queue.empty(&runq[@intCast(curthread().*.priority)])) {
        curthread().*.resched = 1;
    }
    unlock();
}

fn @"suspend"(t: c.thread_t) callconv(.c) void {
    if (t.*.state == c.TS_RUN) {
        if (t == curthread()) {
            curthread().*.resched = 1;
        } else {
            runq_remove(t);
        }
    }
    t.*.state |= @as(c_int, c.TS_SUSP);
}

fn @"resume"(t: c.thread_t) callconv(.c) void {
    if (t.*.state & c.TS_SUSP != 0) {
        t.*.state &= ~@as(c_int, c.TS_SUSP);
        if (t.*.state == c.TS_RUN) {
            runq_enqueue(t);
        }
    }
}

fn tick() callconv(.c) void {
    if (curthread().*.state != c.TS_EXIT) {
        curthread().*.time += 1;
        if (curthread().*.policy == c.SCHED_RR) {
            curthread().*.timeleft -= 1;
            if (curthread().*.timeleft <= 0) {
                curthread().*.timeleft += c.QUANTUM;
                curthread().*.resched = 1;
            }
        }
    }
}

fn start(t: c.thread_t, pri: c_int, policy: c_int) callconv(.c) void {
    t.*.state = c.TS_RUN | @as(c_int, c.TS_SUSP);
    t.*.policy = policy;
    t.*.priority = pri;
    t.*.basepri = pri;
    if (t.*.policy == c.SCHED_RR) {
        t.*.timeleft = c.QUANTUM;
    }
}

fn stop(t: c.thread_t) callconv(.c) void {
    if (t == curthread()) {
        curthread().*.locks = 1;
        curthread().*.resched = 1;
    } else {
        if (t.*.state == c.TS_RUN) {
            runq_remove(t);
        } else if (t.*.state & c.TS_SLEEP != 0) {
            ffi.queue.remove(&t.*.sched_link);
        }
    }
    timer.stop(&t.*.timeout);
    t.*.state = c.TS_EXIT;
}

fn lock() callconv(.c) void {
    var s = hal.splhigh();
    if (curthread().*.locks == 0) {
        if (comptime @hasDecl(c, "CONFIG_SMP")) {
            const cpu = smp.get_cpu_control();
            while (@atomicRmw(c.spinlock_t, &kernel_lock, .Xchg, 1, .seq_cst) != 0) {
                if (cpu.*.nest_count == 0) {
                    hal.splx(s);
                    while (kernel_lock != 0) {
                        hal.zig_memory_barrier();
                    }
                    s = hal.splhigh();
                } else {
                    while (kernel_lock != 0) {
                        hal.zig_memory_barrier();
                    }
                }
            }
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
            @atomicStore(c.spinlock_t, &kernel_lock, 0, .seq_cst);
        }
    } else {
        curthread().*.locks -= 1;
    }
    hal.splx(s);
}

fn bklUnlock() callconv(.c) void {
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        @atomicStore(c.spinlock_t, &kernel_lock, 0, .seq_cst);
    }
}

fn getpri(t: c.thread_t) callconv(.c) c_int {
    return t.*.priority;
}

fn setpri(t: c.thread_t, basepri: c_int, pri: c_int) callconv(.c) void {
    t.*.basepri = basepri;
    if (t == curthread()) {
        t.*.priority = pri;
        maxpri = runq_getbest();
        if (pri != maxpri) {
            curthread().*.resched = 1;
        }
    } else {
        if (t.*.state == c.TS_RUN) {
            runq_remove(t);
            t.*.priority = pri;
            runq_enqueue(t);
        } else {
            t.*.priority = pri;
        }
    }
}

fn getpolicy(t: c.thread_t) callconv(.c) c_int {
    return t.*.policy;
}

fn setpolicy(t: c.thread_t, policy: c_int) callconv(.c) c_int {
    var err: c_int = 0;
    switch (policy) {
        c.SCHED_RR, c.SCHED_FIFO => {
            t.*.timeleft = c.QUANTUM;
            t.*.policy = policy;
        },
        else => {
            err = c.EINVAL;
        },
    }
    return err;
}

fn dpc(dpc_ptr: *c.struct_dpc, fn_ptr: ?*const fn (?*anyopaque) callconv(.c) void, arg: ?*anyopaque) callconv(.c) void {
    lock();
    const s = hal.splhigh();
    dpc_ptr.*.func = fn_ptr;
    dpc_ptr.*.arg = arg;
    if (dpc_ptr.*.state != c.DPC_PENDING) {
        ffi.queue.enqueue(&dpcq, &dpc_ptr.*.link);
    }
    dpc_ptr.*.state = c.DPC_PENDING;
    hal.splx(s);
    wakeup(&dpc_event);
    unlock();
}

fn dpc_thread(dummy: ?*anyopaque) callconv(.c) void {
    _ = dummy;
    _ = hal.splhigh();
    while (true) {
        _ = tsleep(&dpc_event, 0);
        while (!ffi.queue.empty(&dpcq)) {
            const q = ffi.queue.dequeue(&dpcq).?;
            const dpc_val: *c.struct_dpc = @fieldParentPtr("link", @as(*c.struct_queue, @ptrCast(q)));
            dpc_val.*.state = c.DPC_FREE;
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
        while (i < c.NPRI) : (i += 1) {
            const q = &runq[@intCast(i)];
            q.*.next = @ptrCast(q);
            q.*.prev = @ptrCast(q);
        }
    }
    {
        wakeq.next = @ptrCast(&wakeq);
        wakeq.prev = @ptrCast(&wakeq);
    }
    {
        dpcq.next = @ptrCast(&dpcq);
        dpcq.prev = @ptrCast(&dpcq);
    }
    {
        dpc_event.sleepq.next = @ptrCast(&dpc_event.sleepq);
        dpc_event.sleepq.prev = @ptrCast(&dpc_event.sleepq);
        dpc_event.name = @ptrCast(@as([*:0]u8, @constCast("dpc")));
    }
    maxpri = c.PRI_IDLE;
    curthread().*.resched = 1;

    const t = thread.kcreate(dpc_thread, null, c.PRI_DPC);
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
