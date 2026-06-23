// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
// OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
// HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
// LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
// OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
// SUCH DAMAGE.

const std = @import("std");
const builtin = @import("builtin");

const c = @import("c").c;

const ffi = @import("ffi");
const deadlock = ffi.deadlock;
const exception = ffi.exception;
const hal = ffi.hal;
const kern = ffi.kern;
const kmem = ffi.kmem;
const kutil = ffi.kutil;
const lib = ffi.lib;
const sched = ffi.sched;
const smp = ffi.smp;
const thread = ffi.thread;
const timer = ffi.timer;


const TM_ACTIVE: c_int = 0x54616321; // 'Tac!'
const TM_STOP: c_int = 0x54737421; // 'Tst!'
const SIGALRM: c_int = 14;

// ---------------------------------------------------------------------------
// Local global variables
// ---------------------------------------------------------------------------
var lbolt: c_ulong = 0;
var idle_ticks: c_ulong = 0;
var timer_lock: hal.Spinlock = .{ .value = hal.SPINLOCK_INITIALIZER };

var timer_event: hal.Event = std.mem.zeroes(hal.Event);
var delay_event: hal.Event = std.mem.zeroes(hal.Event);
var timer_list: hal.List = std.mem.zeroes(hal.List);
var expire_list: hal.List = std.mem.zeroes(hal.List);

// ---------------------------------------------------------------------------
// Inline helper functions for lists and events
// ---------------------------------------------------------------------------

inline fn list_empty(head: *hal.List) bool {
    return head.next == head;
}

inline fn list_insert(prev: *hal.List, node: *hal.List) void {
    node.prev = prev;
    node.next = prev.next;
    prev.next.*.prev = node;
    prev.next = node;
}

inline fn list_remove(node: *hal.List) void {
    node.prev.*.next = node.next;
    node.next.*.prev = node.prev;
}

inline fn list_init(head: *hal.List) void {
    head.next = head;
    head.prev = head;
}

inline fn event_init(event: *hal.Event, name: [*c]const u8) void {
    event.sleepq.next = &event.sleepq;
    event.sleepq.prev = &event.sleepq;
    event.name = @constCast(name);
}

inline fn time_before(a: c_ulong, b: c_ulong) bool {
    return @as(c_long, @bitCast(b -% a)) < 0;
}

inline fn timerNext(head: *hal.List) *hal.Timer {
    const n: *hal.List = @ptrCast(head.next.?);
    return lib.IntrusiveList(hal.Timer, hal.List, "link").parent(n);
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

fn timerAdd(tmr: *hal.Timer, tck: c_ulong) void {
    var ticks_val = tck;
    if (ticks_val == 0) ticks_val = 1;

    tmr.expire = lbolt +% ticks_val;
    tmr.state = TM_ACTIVE;

    const head = &timer_list;
    var n: *hal.List = head;
    while (n.next != head) : (n = @ptrCast(n.next.?)) {
        const t = timerNext(n);
        if (time_before(tmr.expire, t.expire))
            break;
    }
    list_insert(@ptrCast(n.prev.?), &tmr.link);
}

fn alarm_expire(arg: ?*anyopaque) callconv(.c) void {
    const task: kern.TaskRef = @ptrCast(@alignCast(arg));
    _ = exception.post(task, SIGALRM);
}

// ---------------------------------------------------------------------------
// Timer thread – handles expired timers
// ---------------------------------------------------------------------------

fn timerThread(dummy: ?*anyopaque) callconv(.c) void {
    _ = dummy;
    _ = hal.splhigh();

    while (true) {
        _ = sched.sleep(&timer_event);

        timer_lock.lock();
        while (!list_empty(&expire_list)) {
            const tmr = timerNext(&expire_list);
            list_remove(&tmr.link);
            tmr.state = TM_STOP;
            timer_lock.unlock();
            sched.lock();
            _ = hal.spl0();
            const func = tmr.func.?;
            func(tmr.arg);
            sched.unlock();
            _ = hal.splhigh();
            timer_lock.lock();
        }
        timer_lock.unlock();
    }
}

// ---------------------------------------------------------------------------
// Exported functions
// ---------------------------------------------------------------------------

/// stop – stop an active timer.
pub fn stop(tmr: ?*hal.Timer) callconv(.c) void {
    var s: c_int = undefined;

    timer_lock.lock_irq(&s);
    if (tmr.?.state == TM_ACTIVE) {
        list_remove(&tmr.?.link);
        tmr.?.state = TM_STOP;
    }
    timer_lock.unlock_irq(s);
}

/// callout – schedule a callout function after a specified delay.
pub fn callout(
    tmr: ?*hal.Timer,
    msec: c_ulong,
    fn_ptr: ?*const fn (?*anyopaque) callconv(.c) void,
    arg: ?*anyopaque,
) callconv(.c) void {
    var s: c_int = undefined;

    timer_lock.lock_irq(&s);

    if (tmr.?.state == TM_ACTIVE)
        list_remove(&tmr.?.link);

    tmr.?.func = fn_ptr;
    tmr.?.arg = arg;
    tmr.?.interval = 0;
    timerAdd(tmr.?, timer.mstohz(msec));

    timer_lock.unlock_irq(s);
}

/// delay – delay thread execution for the specified time.
pub fn delay(msec: c_ulong) callconv(.c) c_ulong {
    var remain: c_ulong = 0;

    const rc = sched.tsleep(@ptrCast(&delay_event), msec);
    if (rc != kern.SLP_TIMEOUT) {
        const cur_thread: ?*kern.Thread = kutil.get_curthread();
        const tmr: *hal.Timer = @ptrCast(@alignCast(&cur_thread.?.timeout));
        remain = timer.hztoms(time_remain(tmr.expire));
    }
    return remain;
}

/// sleep – sleep system call.
pub fn sleep(msec: c_ulong, remain: ?*c_ulong) callconv(.c) c_int {
    const left = delay(msec);

    if (remain != null) {
        if (hal.copyout(@ptrCast(&left), @ptrCast(remain), @sizeOf(c_ulong)) != 0)
            return kern.Errno.EFAULT;
    }
    if (left > 0)
        return kern.Errno.EINTR;
    return 0;
}

/// alarm – alarm system call.
pub fn alarm(msec: c_ulong, remain: ?*c_ulong) callconv(.c) c_int {
    var s: c_int = undefined;
    var left: c_ulong = 0;

    timer_lock.lock_irq(&s);
    const cur_thread: ?*kern.Thread = kutil.get_curthread();
    const cur_task: ?*kern.Task = cur_thread.?.task;
    const tmr: *hal.Timer = @ptrCast(@alignCast(&cur_task.?.alarm));

    if (tmr.state == TM_ACTIVE)
        left = timer.hztoms(time_remain(tmr.expire));
    timer_lock.unlock_irq(s);

    if (msec == 0) {
        stop(tmr);
    } else {
        const cur_thread2: ?*kern.Thread = kutil.get_curthread();
        const cur_task2 = cur_thread2.?.task;
        callout(tmr, msec, &alarm_expire, cur_task2);
    }

    if (remain != null) {
        if (hal.copyout(@ptrCast(&left), @ptrCast(remain), @sizeOf(c_ulong)) != 0)
            return kern.Errno.EFAULT;
    }
    return 0;
}

/// periodic – set periodic timer for the specified thread.
pub fn periodic(t: kern.ThreadRef, start: c_ulong, period: c_ulong) callconv(.c) c_int {
    var s: c_int = undefined;

    if (start != 0 and period == 0)
        return kern.Errno.EINVAL;

    sched.lock();
    defer sched.unlock();
    if (thread.valid(t) == 0) {
        return kern.Errno.ESRCH;
    }
    const thread_ptr: ?*kern.Thread = t;
    const cur_thread: ?*kern.Thread = kutil.get_curthread();
    if (thread_ptr.?.task != cur_thread.?.task) {
        return kern.Errno.EPERM;
    }

    var tmr: ?*hal.Timer = thread_ptr.?.periodic;
    if (start == 0) {
        if (tmr == null or tmr.?.state != TM_ACTIVE) {
            return kern.Errno.EINVAL;
        }
        stop(tmr);
    } else {
        if (tmr == null) {
            const alloc: ?*anyopaque = kmem.alloc(@sizeOf(hal.Timer)) orelse return kern.Errno.ENOMEM;
            tmr = @ptrCast(@alignCast(alloc));
            _ = lib.memset(tmr, 0, @sizeOf(hal.Timer));
            event_init(&tmr.?.event, "periodic");
            thread_ptr.?.periodic = tmr;
        }
        timer_lock.lock_irq(&s);
        tmr.?.interval = timer.mstohz(period);
        if (tmr.?.interval == 0)
            tmr.?.interval = 1;
        timerAdd(tmr.?, timer.mstohz(start));
        timer_lock.unlock_irq(s);
    }
    return 0;
}

/// waitperiod – wait next period of the periodic timer.
pub fn waitperiod() callconv(.c) c_int {
    const cur_thread: ?*kern.Thread = kutil.get_curthread();
    const tmr: ?*hal.Timer = cur_thread.?.periodic;
    if (tmr == null or tmr.?.state != TM_ACTIVE)
        return kern.Errno.EINVAL;

    if (time_before(lbolt, tmr.?.expire)) {
        const rc = sched.sleep(&tmr.?.event);
        if (rc != kern.SLP_SUCCESS)
            return kern.Errno.EINTR;
    }
    return 0;
}

/// cancel – cancel timers for thread termination.
pub fn cancel(t_ref: kern.ThreadRef) callconv(.c) void {
    const t: ?*kern.Thread = t_ref;
    if (t) |tr| {
        const periodic_val: ?*hal.Timer = tr.periodic;
        if (periodic_val) |p| {
            stop(p);
            kmem.free(p);
            tr.periodic = null;
        }
    }
}

/// handler – handle clock interrupts.
pub fn handler() callconv(.c) void {
    var wakeup: c_int = 0;

    if (smp.processor_id() == 0) {
        lbolt +%= 1;
        const cur_thread: ?*kern.Thread = kutil.get_curthread();
        if (cur_thread.?.priority == hal.PRI_IDLE)
            idle_ticks +%= 1;

        timer_lock.lock();
        while (!list_empty(&timer_list)) {
            const tmr = timerNext(&timer_list);
            if (time_before(lbolt, tmr.expire))
                break;

            list_remove(&tmr.link);
            if (tmr.interval != 0) {
                const ticks_val = time_remain(tmr.expire +% tmr.interval);
                timerAdd(tmr, ticks_val);
                timer_lock.unlock();
                sched.wakeup(@ptrCast(&tmr.event));
                timer_lock.lock();
            } else {
                list_insert(&expire_list, &tmr.link);
                wakeup = 1;
            }
        }
        timer_lock.unlock();
        if (wakeup != 0)
            sched.wakeup(@ptrCast(&timer_event));

        if (@hasDecl(c, "DEBUG") and @hasDecl(c, "CONFIG_KD")) {
            deadlock.heartbeat();
            deadlock.proactive_check();
        }
    }

    sched.tick();
}

/// ticks – return ticks since boot.
pub fn ticks() callconv(.c) c_ulong {
    return lbolt;
}

/// info – return timer information.
pub fn info(timer_info_ptr: ?*hal.TimerInfo) callconv(.c) void {
    if (timer_info_ptr) |inf| {
        inf.hz = hal.HZ;
        inf.cputicks = lbolt;
        inf.idleticks = idle_ticks;
    }
}

/// init – initialize the timer facility.
pub fn init() callconv(.c) void {
    event_init(&timer_event, "timer");
    event_init(&delay_event, "delay");
    list_init(&timer_list);
    list_init(&expire_list);

    if (thread.kcreate(&timerThread, null, hal.PRI_TIMER) == null)
        lib.panic("init");
}

// ---------------------------------------------------------------------------
// Comptime exports – public API functions with strong C linkage
// ---------------------------------------------------------------------------
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
