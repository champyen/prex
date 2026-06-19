const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});

extern fn hal_get_cpu_control() callconv(.c) ?*c.struct_cpu_control;

pub var kernel_lock: c.spinlock_t = 0;
var runq: [c.NPRI]c.struct_queue = undefined;
var wakeq: c.struct_queue = undefined;
var dpcq: c.struct_queue = undefined;
var dpc_event: c.struct_event = undefined;
var maxpri: c_int = c.PRI_IDLE;

fn runq_getbest() c_int {
    var pri: c_int = 0;
    while (pri < c.MINPRI) : (pri += 1) {
        if (!c.queue_empty(&runq[@intCast(pri)])) {
            break;
        }
    }
    return pri;
}

fn runq_enqueue(t: c.thread_t) void {
    c.enqueue(&runq[@intCast(t.*.priority)], &t.*.sched_link);
    if (t.*.priority < maxpri) {
        maxpri = t.*.priority;
        if (get_curthread()) |ct| {
            ct.resched = 1;
        }
    }
}

fn runq_insert(t: c.thread_t) void {
    c.queue_insert(&runq[@intCast(t.*.priority)], &t.*.sched_link);
    if (t.*.priority < maxpri) {
        maxpri = t.*.priority;
    }
}

fn runq_dequeue() c.thread_t {
    if (maxpri >= c.PRI_IDLE) {
        return &c.idle_thread;
    }
    const q = c.dequeue(&runq[@intCast(maxpri)]).?;
    const t: *c.struct_thread = @fieldParentPtr("sched_link", @as(*c.struct_queue, @ptrCast(q)));
    if (c.queue_empty(&runq[@intCast(maxpri)])) {
        maxpri = runq_getbest();
    }
    return t;
}

fn runq_remove(t: c.thread_t) void {
    c.queue_remove(&t.*.sched_link);
    maxpri = runq_getbest();
}

fn get_curthread() ?*c.struct_thread {
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        return @ptrCast(hal_get_cpu_control().?.*.active_thread);
    } else {
        const env = struct {
            extern var curthread: c.thread_t;
        };
        return @ptrCast(env.curthread);
    }
}

fn set_curthread(t: c.thread_t) void {
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        hal_get_cpu_control().?.*.active_thread = t;
    } else {
        const env = struct {
            extern var curthread: c.thread_t;
        };
        env.curthread = t;
    }
}

fn curthread() *c.struct_thread {
    return get_curthread().?;
}

fn wakeq_flush() callconv(.c) void {
    while (!c.queue_empty(&wakeq)) {
        const q = c.dequeue(&wakeq).?;
        const t: *c.struct_thread = @fieldParentPtr("sched_link", @as(*c.struct_queue, @ptrCast(q)));
        t.*.slpevt = null;
        t.*.state &= ~@as(c_int, c.TS_SLEEP);
        if (t != curthread() and t.*.state == c.TS_RUN) {
            runq_enqueue(t);
        }
    }
}

fn sched_setrun(t: c.thread_t) callconv(.c) void {
    c.enqueue(&wakeq, &t.*.sched_link);
    c.timer_stop(&t.*.timeout);
}

fn sleep_timeout(arg: ?*anyopaque) callconv(.c) void {
    const t: c.thread_t = @ptrCast(@alignCast(arg));
    sched_unsleep(t, c.SLP_TIMEOUT);
}

fn sched_swtch() callconv(.c) void {
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
        c.vm_switch(next.*.task.*.map);
    }

    var locks: c_int = undefined;
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        locks = prev.*.locks;
        prev.*.locks = 0;
        if (locks > 0) {
            @atomicStore(c.spinlock_t, &kernel_lock, 0, .seq_cst);
        }
    }

    c.context_switch(&prev.*.ctx, &next.*.ctx);

    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        const cpu = hal_get_cpu_control().?;
        var s = c.splhigh();
        while (@atomicRmw(c.spinlock_t, &kernel_lock, .Xchg, 1, .seq_cst) != 0) {
            if (cpu.*.nest_count == 0) {
                c.splx(s);
                while (kernel_lock != 0) {
                    c.zig_memory_barrier();
                }
                s = c.splhigh();
            } else {
                while (kernel_lock != 0) {
                    c.zig_memory_barrier();
                }
            }
        }
        curthread().*.locks = locks;
        c.splx(s);
    }
}

fn sched_tsleep(evt: *c.struct_event, msec: c_ulong) callconv(.c) c_int {
    c.sched_lock();
    const s = c.splhigh();

    curthread().*.slpevt = evt;
    curthread().*.state |= @as(c_int, c.TS_SLEEP);
    c.enqueue(&evt.*.sleepq, &curthread().*.sched_link);

    if (msec != 0) {
        c.timer_callout(&curthread().*.timeout, msec, sleep_timeout, curthread());
    }

    wakeq_flush();
    sched_swtch();

    c.splx(s);
    c.sched_unlock();
    return curthread().*.slpret;
}

fn sched_wakeup(evt: *c.struct_event) callconv(.c) void {
    c.sched_lock();
    const s = c.splhigh();
    while (!c.queue_empty(&evt.*.sleepq)) {
        const q = c.dequeue(&evt.*.sleepq).?;
        const t: *c.struct_thread = @fieldParentPtr("sched_link", @as(*c.struct_queue, @ptrCast(q)));
        t.*.slpret = 0;
        sched_setrun(t);
    }
    c.splx(s);
    c.sched_unlock();
}

fn sched_wakeone(evt: *c.struct_event) callconv(.c) c.thread_t {
    c.sched_lock();
    const s = c.splhigh();
    var result: c.thread_t = null;
    const head = &evt.*.sleepq;
    if (!c.queue_empty(head)) {
        var q = head.*.next;
        var top: *c.struct_thread = @fieldParentPtr("sched_link", @as(*c.struct_queue, @ptrCast(q)));
        while (q != head) {
            const t: *c.struct_thread = @fieldParentPtr("sched_link", @as(*c.struct_queue, @ptrCast(q)));
            if (t.*.priority < top.*.priority) {
                top = t;
            }
            q = q.*.next;
        }
        c.queue_remove(&top.*.sched_link);
        top.*.slpret = 0;
        sched_setrun(top);
        result = top;
    }
    c.splx(s);
    c.sched_unlock();
    return result;
}

fn sched_unsleep(t: c.thread_t, result: c_int) callconv(.c) void {
    c.sched_lock();
    if (t.*.state & c.TS_SLEEP != 0) {
        const s = c.splhigh();
        c.queue_remove(&t.*.sched_link);
        t.*.slpret = result;
        sched_setrun(t);
        c.splx(s);
    }
    c.sched_unlock();
}

fn sched_yield() callconv(.c) void {
    c.sched_lock();
    if (!c.queue_empty(&runq[@intCast(curthread().*.priority)])) {
        curthread().*.resched = 1;
    }
    c.sched_unlock();
}

fn sched_suspend(t: c.thread_t) callconv(.c) void {
    if (t.*.state == c.TS_RUN) {
        if (t == curthread()) {
            curthread().*.resched = 1;
        } else {
            runq_remove(t);
        }
    }
    t.*.state |= @as(c_int, c.TS_SUSP);
}

fn sched_resume(t: c.thread_t) callconv(.c) void {
    if (t.*.state & c.TS_SUSP != 0) {
        t.*.state &= ~@as(c_int, c.TS_SUSP);
        if (t.*.state == c.TS_RUN) {
            runq_enqueue(t);
        }
    }
}

fn sched_tick() callconv(.c) void {
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

fn sched_start(t: c.thread_t, pri: c_int, policy: c_int) callconv(.c) void {
    t.*.state = c.TS_RUN | @as(c_int, c.TS_SUSP);
    t.*.policy = policy;
    t.*.priority = pri;
    t.*.basepri = pri;
    if (t.*.policy == c.SCHED_RR) {
        t.*.timeleft = c.QUANTUM;
    }
}

fn sched_stop(t: c.thread_t) callconv(.c) void {
    if (t == curthread()) {
        curthread().*.locks = 1;
        curthread().*.resched = 1;
    } else {
        if (t.*.state == c.TS_RUN) {
            runq_remove(t);
        } else if (t.*.state & c.TS_SLEEP != 0) {
            c.queue_remove(&t.*.sched_link);
        }
    }
    c.timer_stop(&t.*.timeout);
    t.*.state = c.TS_EXIT;
}

fn sched_lock() callconv(.c) void {
    var s = c.splhigh();
    if (curthread().*.locks == 0) {
        if (comptime @hasDecl(c, "CONFIG_SMP")) {
            const cpu = hal_get_cpu_control().?;
            while (@atomicRmw(c.spinlock_t, &kernel_lock, .Xchg, 1, .seq_cst) != 0) {
                if (cpu.*.nest_count == 0) {
                    c.splx(s);
                    while (kernel_lock != 0) {
                        c.zig_memory_barrier();
                    }
                    s = c.splhigh();
                } else {
                    while (kernel_lock != 0) {
                        c.zig_memory_barrier();
                    }
                }
            }
        }
    }
    curthread().*.locks += 1;
    c.splx(s);
}

fn sched_unlock() callconv(.c) void {
    var s = c.splhigh();
    if (curthread().*.locks == 1) {
        wakeq_flush();
        while (curthread().*.resched != 0) {
            sched_swtch();
            c.splx(s);
            s = c.splhigh();
            wakeq_flush();
        }
        curthread().*.locks = 0;
        if (comptime @hasDecl(c, "CONFIG_SMP")) {
            @atomicStore(c.spinlock_t, &kernel_lock, 0, .seq_cst);
        }
    } else {
        curthread().*.locks -= 1;
    }
    c.splx(s);
}

fn sched_bkl_unlock() callconv(.c) void {
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        @atomicStore(c.spinlock_t, &kernel_lock, 0, .seq_cst);
    }
}

fn sched_getpri(t: c.thread_t) callconv(.c) c_int {
    return t.*.priority;
}

fn sched_setpri(t: c.thread_t, basepri: c_int, pri: c_int) callconv(.c) void {
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

fn sched_getpolicy(t: c.thread_t) callconv(.c) c_int {
    return t.*.policy;
}

fn sched_setpolicy(t: c.thread_t, policy: c_int) callconv(.c) c_int {
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

fn sched_dpc(dpc: *c.struct_dpc, fn_ptr: ?*const fn (?*anyopaque) callconv(.c) void, arg: ?*anyopaque) callconv(.c) void {
    c.sched_lock();
    const s = c.splhigh();
    dpc.*.func = fn_ptr;
    dpc.*.arg = arg;
    if (dpc.*.state != c.DPC_PENDING) {
        c.enqueue(&dpcq, &dpc.*.link);
    }
    dpc.*.state = c.DPC_PENDING;
    c.splx(s);
    sched_wakeup(&dpc_event);
    c.sched_unlock();
}

fn dpc_thread(dummy: ?*anyopaque) callconv(.c) void {
    _ = dummy;
    _ = c.splhigh();
    while (true) {
        _ = sched_tsleep(&dpc_event, 0);
        while (!c.queue_empty(&dpcq)) {
            const q = c.dequeue(&dpcq).?;
            const dpc: *c.struct_dpc = @fieldParentPtr("link", @as(*c.struct_queue, @ptrCast(q)));
            dpc.*.state = c.DPC_FREE;
            _ = c.spl0();
            if (dpc.*.func) |f| {
                f(dpc.*.arg);
            }
            _ = c.splhigh();
        }
    }
}

fn sched_init() callconv(.c) void {
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

    const t = c.kthread_create(dpc_thread, null, c.PRI_DPC);
    if (t == null) {
        @panic("sched_init");
    }
}

comptime {
    @export(&sleep_timeout, .{ .name = "sleep_timeout", .linkage = .strong });
    @export(&dpc_thread, .{ .name = "dpc_thread", .linkage = .strong });
    @export(&wakeq_flush, .{ .name = "wakeq_flush", .linkage = .strong });
    @export(&sched_setrun, .{ .name = "sched_setrun", .linkage = .strong });
    @export(&sched_swtch, .{ .name = "sched_swtch", .linkage = .strong });
    @export(&sched_tsleep, .{ .name = "sched_tsleep", .linkage = .strong });
    @export(&sched_wakeup, .{ .name = "sched_wakeup", .linkage = .strong });
    @export(&sched_wakeone, .{ .name = "sched_wakeone", .linkage = .strong });
    @export(&sched_unsleep, .{ .name = "sched_unsleep", .linkage = .strong });
    @export(&sched_yield, .{ .name = "sched_yield", .linkage = .strong });
    @export(&sched_suspend, .{ .name = "sched_suspend", .linkage = .strong });
    @export(&sched_resume, .{ .name = "sched_resume", .linkage = .strong });
    @export(&sched_tick, .{ .name = "sched_tick", .linkage = .strong });
    @export(&sched_start, .{ .name = "sched_start", .linkage = .strong });
    @export(&sched_stop, .{ .name = "sched_stop", .linkage = .strong });
    @export(&sched_lock, .{ .name = "sched_lock", .linkage = .strong });
    @export(&sched_unlock, .{ .name = "sched_unlock", .linkage = .strong });
    @export(&sched_bkl_unlock, .{ .name = "sched_bkl_unlock", .linkage = .strong });
    @export(&sched_getpri, .{ .name = "sched_getpri", .linkage = .strong });
    @export(&sched_setpri, .{ .name = "sched_setpri", .linkage = .strong });
    @export(&sched_getpolicy, .{ .name = "sched_getpolicy", .linkage = .strong });
    @export(&sched_setpolicy, .{ .name = "sched_setpolicy", .linkage = .strong });
    @export(&sched_dpc, .{ .name = "sched_dpc", .linkage = .strong });
    @export(&sched_init, .{ .name = "sched_init", .linkage = .strong });
}
