const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});

extern fn hal_get_cpu_control() callconv(.c) ?*c.struct_cpu_control;

inline fn get_curthread() ?*c.struct_thread {
    if (@hasDecl(c, "CONFIG_SMP")) {
        return @ptrCast(hal_get_cpu_control().?.*.active_thread);
    } else {
        const env = struct {
            extern var curthread: c.thread_t;
        };
        return @ptrCast(env.curthread);
    }
}

const TM_ACTIVE: c_int = 0x54616321; // 'Tac!'
const TM_STOP: c_int = 0x54737421; // 'Tst!'
const SIGALRM: c_int = 14;

// ---------------------------------------------------------------------------
// Local global variables
// ---------------------------------------------------------------------------
var lbolt: c_ulong = 0;
var idle_ticks: c_ulong = 0;
var timer_lock: c.spinlock_t = c.SPINLOCK_INITIALIZER;

var timer_event: c.struct_event = std.mem.zeroes(c.struct_event);
var delay_event: c.struct_event = std.mem.zeroes(c.struct_event);
var timer_list: c.struct_list = std.mem.zeroes(c.struct_list);
var expire_list: c.struct_list = std.mem.zeroes(c.struct_list);

// ---------------------------------------------------------------------------
// Inline helper functions for spinlocks
// ---------------------------------------------------------------------------
inline fn spinlock_lock(lock: *c.spinlock_t) void {
    if (@hasDecl(c, "__broken_spinlock_lock")) {
        c.__broken_spinlock_lock(lock);
    }
}

inline fn spinlock_unlock(lock: *c.spinlock_t) void {
    if (@hasDecl(c, "__broken_spinlock_unlock")) {
        c.__broken_spinlock_unlock(lock);
    }
}

inline fn spinlock_lock_irq(lock: *c.spinlock_t, s: *c_int) void {
    s.* = c.splhigh();
    if (@hasDecl(c, "__broken_spinlock_lock")) {
        c.__broken_spinlock_lock(lock);
    }
}

inline fn spinlock_unlock_irq(lock: *c.spinlock_t, s: c_int) void {
    if (@hasDecl(c, "__broken_spinlock_unlock")) {
        c.__broken_spinlock_unlock(lock);
    }
    _ = c.splx(s);
}

// ---------------------------------------------------------------------------
// Inline helper functions for lists and events
// ---------------------------------------------------------------------------

inline fn list_empty(head: *c.struct_list) bool {
    return head.next == head;
}

inline fn list_insert(prev: *c.struct_list, node: *c.struct_list) void {
    node.prev = prev;
    node.next = prev.next;
    prev.next.*.prev = node;
    prev.next = node;
}

inline fn list_remove(node: *c.struct_list) void {
    node.prev.*.next = node.next;
    node.next.*.prev = node.prev;
}

inline fn list_init(head: *c.struct_list) void {
    head.next = head;
    head.prev = head;
}

inline fn event_init(event: *c.struct_event, name: [*c]const u8) void {
    event.sleepq.next = &event.sleepq;
    event.sleepq.prev = &event.sleepq;
    event.name = @constCast(name);
}

inline fn time_before(a: c_ulong, b: c_ulong) bool {
    return @as(c_long, @bitCast(b -% a)) < 0;
}

inline fn timer_next(head: *c.struct_list) *c.struct_timer {
    const n: *c.struct_list = @ptrCast(head.next.?);
    return @fieldParentPtr("link", n);
}

// ---------------------------------------------------------------------------
// Static (internal) helpers
// ---------------------------------------------------------------------------

fn time_remain(expire: c_ulong) c_ulong {
    if (time_before(lbolt, expire)) {
        return expire -% lbolt;
    }
    return 0;
}

fn timer_add(tmr: *c.struct_timer, ticks: c_ulong) void {
    var actual_ticks = ticks;
    if (actual_ticks == 0) actual_ticks = 1;

    tmr.expire = lbolt +% actual_ticks;
    tmr.state = TM_ACTIVE;

    const head = &timer_list;
    var n: *c.struct_list = head;
    while (n.next != head) : (n = @ptrCast(n.next.?)) {
        const t = timer_next(n);
        if (time_before(tmr.expire, t.expire))
            break;
    }
    list_insert(@ptrCast(n.prev.?), &tmr.link);
}

fn alarm_expire(arg: ?*anyopaque) callconv(.c) void {
    const task: c.task_t = @ptrCast(@alignCast(arg));
    _ = c.exception_post(task, SIGALRM);
}

// ---------------------------------------------------------------------------
// Timer thread – handles expired timers
// ---------------------------------------------------------------------------

fn timer_thread(dummy: ?*anyopaque) callconv(.c) void {
    _ = dummy;
    _ = c.splhigh();

    while (true) {
        _ = c.sched_sleep(&timer_event);

        spinlock_lock(&timer_lock);
        while (!list_empty(&expire_list)) {
            const tmr = timer_next(&expire_list);
            list_remove(&tmr.link);
            tmr.state = TM_STOP;
            spinlock_unlock(&timer_lock);
            c.sched_lock();
            _ = c.spl0();
            const func = tmr.func.?;
            func(tmr.arg);
            c.sched_unlock();
            _ = c.splhigh();
            spinlock_lock(&timer_lock);
        }
        spinlock_unlock(&timer_lock);
    }
}

// ---------------------------------------------------------------------------
// Exported functions
// ---------------------------------------------------------------------------

/// timer_stop – stop an active timer.
pub fn timer_stop(tmr: ?*c.struct_timer) callconv(.c) void {
    var s: c_int = undefined;

    spinlock_lock_irq(&timer_lock, &s);
    if (tmr.?.state == TM_ACTIVE) {
        list_remove(&tmr.?.link);
        tmr.?.state = TM_STOP;
    }
    spinlock_unlock_irq(&timer_lock, s);
}

/// timer_callout – schedule a callout function after a specified delay.
pub fn timer_callout(
    tmr: ?*c.struct_timer,
    msec: c_ulong,
    fn_ptr: ?*const fn (?*anyopaque) callconv(.c) void,
    arg: ?*anyopaque,
) callconv(.c) void {
    var s: c_int = undefined;

    spinlock_lock_irq(&timer_lock, &s);

    if (tmr.?.state == TM_ACTIVE)
        list_remove(&tmr.?.link);

    tmr.?.func = fn_ptr;
    tmr.?.arg = arg;
    tmr.?.interval = 0;
    timer_add(tmr.?, c.mstohz(msec));

    spinlock_unlock_irq(&timer_lock, s);
}

/// timer_delay – delay thread execution for the specified time.
pub fn timer_delay(msec: c_ulong) callconv(.c) c_ulong {
    var remain: c_ulong = 0;

    const rc = c.sched_tsleep(&delay_event, msec);
    if (rc != c.SLP_TIMEOUT) {
        const cur_thread: ?*c.struct_thread = get_curthread();
        const tmr: *c.struct_timer = @ptrCast(@alignCast(&cur_thread.?.timeout));
        remain = c.hztoms(time_remain(tmr.expire));
    }
    return remain;
}

/// timer_sleep – sleep system call.
pub fn timer_sleep(msec: c_ulong, remain: ?*c_ulong) callconv(.c) c_int {
    const left = timer_delay(msec);

    if (remain != null) {
        if (c.copyout(@ptrCast(&left), @ptrCast(remain), @sizeOf(c_ulong)) != 0)
            return c.EFAULT;
    }
    if (left > 0)
        return c.EINTR;
    return 0;
}

/// timer_alarm – alarm system call.
pub fn timer_alarm(msec: c_ulong, remain: ?*c_ulong) callconv(.c) c_int {
    var s: c_int = undefined;
    var left: c_ulong = 0;

    spinlock_lock_irq(&timer_lock, &s);
    const cur_thread: ?*c.struct_thread = get_curthread();
    const cur_task: ?*c.struct_task = cur_thread.?.task;
    const tmr: *c.struct_timer = @ptrCast(@alignCast(&cur_task.?.alarm));

    if (tmr.state == TM_ACTIVE)
        left = c.hztoms(time_remain(tmr.expire));
    spinlock_unlock_irq(&timer_lock, s);

    if (msec == 0) {
        timer_stop(tmr);
    } else {
        const cur_thread2: ?*c.struct_thread = get_curthread();
        const cur_task2 = cur_thread2.?.task;
        timer_callout(tmr, msec, &alarm_expire, cur_task2);
    }

    if (remain != null) {
        if (c.copyout(@ptrCast(&left), @ptrCast(remain), @sizeOf(c_ulong)) != 0)
            return c.EFAULT;
    }
    return 0;
}

/// timer_periodic – set periodic timer for the specified thread.
pub fn timer_periodic(t: c.thread_t, start: c_ulong, period: c_ulong) callconv(.c) c_int {
    var s: c_int = undefined;

    if (start != 0 and period == 0)
        return c.EINVAL;

    c.sched_lock();
    if (c.thread_valid(t) == 0) {
        c.sched_unlock();
        return c.ESRCH;
    }
    const thread_ptr: ?*c.struct_thread = t;
    const cur_thread: ?*c.struct_thread = get_curthread();
    if (thread_ptr.?.task != cur_thread.?.task) {
        c.sched_unlock();
        return c.EPERM;
    }

    var tmr: ?*c.struct_timer = thread_ptr.?.periodic;
    if (start == 0) {
        if (tmr == null or tmr.?.state != TM_ACTIVE) {
            c.sched_unlock();
            return c.EINVAL;
        }
        timer_stop(tmr);
    } else {
        if (tmr == null) {
            const alloc: ?*anyopaque = c.kmem_alloc(@sizeOf(c.struct_timer));
            if (alloc == null) {
                c.sched_unlock();
                return c.ENOMEM;
            }
            tmr = @ptrCast(@alignCast(alloc));
            _ = c.memset(tmr, 0, @sizeOf(c.struct_timer));
            event_init(&tmr.?.event, "periodic");
            thread_ptr.?.periodic = tmr;
        }
        spinlock_lock_irq(&timer_lock, &s);
        tmr.?.interval = c.mstohz(period);
        if (tmr.?.interval == 0)
            tmr.?.interval = 1;
        timer_add(tmr.?, c.mstohz(start));
        spinlock_unlock_irq(&timer_lock, s);
    }
    c.sched_unlock();
    return 0;
}

/// timer_waitperiod – wait next period of the periodic timer.
pub fn timer_waitperiod() callconv(.c) c_int {
    const cur_thread: ?*c.struct_thread = get_curthread();
    const tmr: ?*c.struct_timer = cur_thread.?.periodic;
    if (tmr == null or tmr.?.state != TM_ACTIVE)
        return c.EINVAL;

    if (time_before(lbolt, tmr.?.expire)) {
        const rc = c.sched_sleep(&tmr.?.event);
        if (rc != c.SLP_SUCCESS)
            return c.EINTR;
    }
    return 0;
}

/// timer_cancel – cancel timers for thread termination.
pub fn timer_cancel(thread: c.thread_t) callconv(.c) void {
    const t: ?*c.struct_thread = thread;
    if (t) |tr| {
        const periodic: ?*c.struct_timer = tr.periodic;
        if (periodic) |p| {
            timer_stop(p);
            c.kmem_free(p);
            tr.periodic = null;
        }
    }
}

/// timer_handler – handle clock interrupts.
pub fn timer_handler() callconv(.c) void {
    var wakeup: c_int = 0;

    if (c.smp_processor_id() == 0) {
        lbolt +%= 1;
        const cur_thread: ?*c.struct_thread = get_curthread();
        if (cur_thread.?.priority == c.PRI_IDLE)
            idle_ticks +%= 1;

        spinlock_lock(&timer_lock);
        while (!list_empty(&timer_list)) {
            const tmr = timer_next(&timer_list);
            if (time_before(lbolt, tmr.expire))
                break;

            list_remove(&tmr.link);
            if (tmr.interval != 0) {
                const ticks = time_remain(tmr.expire +% tmr.interval);
                timer_add(tmr, ticks);
                spinlock_unlock(&timer_lock);
                c.sched_wakeup(&tmr.event);
                spinlock_lock(&timer_lock);
            } else {
                list_insert(&expire_list, &tmr.link);
                wakeup = 1;
            }
        }
        spinlock_unlock(&timer_lock);
        if (wakeup != 0)
            c.sched_wakeup(&timer_event);

        if (@hasDecl(c, "DEBUG") and @hasDecl(c, "CONFIG_KD")) {
            c.deadlock_heartbeat();
            c.deadlock_proactive_check();
        }
    }

    c.sched_tick();
}

/// timer_ticks – return ticks since boot.
pub fn timer_ticks() callconv(.c) c_ulong {
    return lbolt;
}

/// timer_info – return timer information.
pub fn timer_info(info: ?*c.struct_timerinfo) callconv(.c) void {
    if (info) |inf| {
        inf.hz = c.HZ;
        inf.cputicks = lbolt;
        inf.idleticks = idle_ticks;
    }
}

/// timer_init – initialize the timer facility.
pub fn timer_init() callconv(.c) void {
    event_init(&timer_event, "timer");
    event_init(&delay_event, "delay");
    list_init(&timer_list);
    list_init(&expire_list);

    if (c.kthread_create(&timer_thread, null, c.PRI_TIMER) == null)
        c.panic("timer_init");
}

// ---------------------------------------------------------------------------
// Comptime exports – public API functions with strong C linkage
// ---------------------------------------------------------------------------
comptime {
    @export(&timer_stop, .{ .name = "timer_stop", .linkage = .strong });
    @export(&timer_callout, .{ .name = "timer_callout", .linkage = .strong });
    @export(&timer_delay, .{ .name = "timer_delay", .linkage = .strong });
    @export(&timer_sleep, .{ .name = "timer_sleep", .linkage = .strong });
    @export(&timer_alarm, .{ .name = "timer_alarm", .linkage = .strong });
    @export(&timer_periodic, .{ .name = "timer_periodic", .linkage = .strong });
    @export(&timer_waitperiod, .{ .name = "timer_waitperiod", .linkage = .strong });
    @export(&timer_cancel, .{ .name = "timer_cancel", .linkage = .strong });
    @export(&timer_handler, .{ .name = "timer_handler", .linkage = .strong });
    @export(&timer_ticks, .{ .name = "timer_ticks", .linkage = .strong });
    @export(&timer_info, .{ .name = "timer_info", .linkage = .strong });
    @export(&timer_init, .{ .name = "timer_init", .linkage = .strong });

    if (@hasDecl(c, "CONFIG_SMP")) {
        @export(&__broken_spinlock_lock, .{ .name = "__broken_spinlock_lock", .linkage = .strong });
        @export(&__broken_spinlock_unlock, .{ .name = "__broken_spinlock_unlock", .linkage = .strong });
    }
}

pub fn __broken_spinlock_lock(lock: ?*volatile c.spinlock_t) callconv(.c) void {
    if (comptime !@hasDecl(c, "CONFIG_SMP")) return;
    const l: *volatile i32 = @ptrCast(@alignCast(lock.?));
    while (@atomicRmw(i32, l, .Xchg, 1, .seq_cst) != 0) {
        while (l.* != 0) {}
    }
}

pub fn __broken_spinlock_unlock(lock: ?*volatile c.spinlock_t) callconv(.c) void {
    if (comptime !@hasDecl(c, "CONFIG_SMP")) return;
    const l: *volatile i32 = @ptrCast(@alignCast(lock.?));
    @atomicStore(i32, l, 0, .seq_cst);
}
