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
const hal = ffi.hal;
const kern = ffi.kern;
const kmem = ffi.kmem;
const kutil = ffi.kutil;
const lib = ffi.lib;
const msg = ffi.msg;
const mutex = ffi.mutex;
const sched = ffi.sched;
const task = ffi.task;
const thread = ffi.thread;
const timer = ffi.timer;
pub var idle_thread: kern.Thread = std.mem.zeroes(kern.Thread);
var zombie: kern.ThreadRef = null;
var thread_list: hal.List = undefined;

pub var curthread: kern.ThreadRef = &idle_thread;
pub var irq_nesting: c_int = 0;
pub var curspl: c_int = 15;




inline fn list_init(head: *hal.List) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

inline fn list_insert(prev: *hal.List, node: *hal.List) void {
    node.prev = @ptrCast(prev);
    node.next = prev.next;
    prev.next.?.*.prev = @ptrCast(node);
    prev.next = @ptrCast(node);
}

inline fn list_remove(node: *hal.List) void {
    node.prev.?.*.next = node.next;
    node.next.?.*.prev = node.prev;
}

fn allocate(tsk: kern.TaskRef) kern.ThreadRef {
    const mem = kmem.alloc(@sizeOf(kern.Thread));
    const t: kern.ThreadRef = @ptrCast(@alignCast(mem));
    if (t == null) return null;

    const stack = kmem.alloc(hal.KSTACKSZ);
    if (stack == null) {
        kmem.free(t);
        return null;
    }

    _ = lib.memset(t, 0, @sizeOf(kern.Thread));
    t.*.kstack = stack;
    t.*.task = tsk;
    list_init(&t.*.mutexes);
    list_insert(&thread_list, &t.*.link);
    list_insert(&tsk.*.threads, &t.*.task_link);
    tsk.*.nthreads += 1;

    return t;
}

fn deallocate(t: kern.ThreadRef) void {
    list_remove(&t.*.task_link);
    list_remove(&t.*.link);
    t.*.excbits = 0;
    t.*.task.*.nthreads -= 1;

    if (zombie) |z| {
        kmem.free(z.*.kstack);
        z.*.kstack = null;
        kmem.free(z);
        zombie = null;
    }

    if (t == kutil.get_curthread()) {
        zombie = t;
        return;
    }

    kmem.free(t.*.kstack);
    t.*.kstack = null;
    kmem.free(t);
}

pub fn create(tsk: kern.TaskRef, tp: ?*kern.ThreadRef) callconv(.c) c_int {
    sched.lock();
    defer sched.unlock();

    if (task.valid(tsk) == 0) {
        return kern.Errno.ESRCH;
    }
    if (task.access(tsk) == 0) {
        return kern.Errno.EPERM;
    }
    if (tsk.*.nthreads >= hal.MAXTHREADS) {
        return kern.Errno.EAGAIN;
    }

    if ((kutil.get_curtask().?.*.flags & kern.TF_SYSTEM) == 0) {
        var tmp: kern.ThreadRef = null;
        if (hal.copyout(@as(?*const anyopaque, @ptrCast(&tmp)), @as(?*anyopaque, @ptrCast(tp)), @sizeOf(kern.ThreadRef)) != 0) {
            return kern.Errno.EFAULT;
        }
    }

    const t = allocate(tsk) orelse {
        return kern.Errno.ENOMEM;
    };

    if (comptime @hasDecl(c, "CONFIG_ARMV8M")) {
        _ = lib.memset(t.*.kstack, 0, hal.KSTACKSZ);
        const parent_uregs = kutil.get_curthread().?.*.ctx.uregs;
        const child_uregs: *hal.CpuRegs = @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(@intFromPtr(t.*.kstack) + hal.KSTACKSZ - @sizeOf(hal.CpuRegs)))));
        _ = lib.memcpy(child_uregs, parent_uregs, @sizeOf(hal.CpuRegs));
    } else {
        _ = lib.memcpy(t.*.kstack, kutil.get_curthread().?.*.kstack, hal.KSTACKSZ);
    }

    const sp: usize = @intFromPtr(t.*.kstack) + hal.KSTACKSZ;
    hal.context_set(&t.*.ctx, hal.CTX_KSTACK, kutil.toReg(sp));
    hal.context_set(&t.*.ctx, hal.CTX_KENTRY, kutil.toReg(&thread.syscall_ret));
    sched.start(t, kutil.get_curthread().?.*.basepri, kern.SCHED_RR);
    t.*.suscnt = tsk.*.suscnt + 1;

    if (kutil.get_curtask().?.*.flags & kern.TF_SYSTEM != 0) {
        if (tp) |tp_ptr| {
            tp_ptr.* = t;
        }
    } else {
        _ = hal.copyout(@as(?*const anyopaque, @ptrCast(&t)), @as(?*anyopaque, @ptrCast(tp)), @sizeOf(kern.ThreadRef));
    }

    return 0;
}

pub fn terminate(t: kern.ThreadRef) callconv(.c) c_int {
    sched.lock();
    defer sched.unlock();

    if (valid(t) == 0) {
        return kern.Errno.ESRCH;
    }
    if (task.access(t.*.task) == 0) {
        return kern.Errno.EPERM;
    }
    destroy(t);
    return 0;
}

pub fn destroy(th: kern.ThreadRef) callconv(.c) void {
    msg.cancel(th);
    mutex.cancel(th);
    timer.cancel(th);
    sched.stop(th);
    deallocate(th);
}

pub fn setup(t: kern.ThreadRef, entry: ?*anyopaque, stack: ?*anyopaque, gp: ?*anyopaque) callconv(.c) c_int {
    if (entry != null and !kutil.user_area(entry)) return kern.Errno.EINVAL;
    if (stack != null and !kutil.user_area(stack)) return kern.Errno.EINVAL;

    sched.lock();
    defer sched.unlock();

    if (valid(t) == 0) {
        return kern.Errno.ESRCH;
    }
    if (task.access(t.*.task) == 0) {
        return kern.Errno.EPERM;
    }

    const s = hal.splhigh();
    if (entry != null) {
        if (comptime @hasDecl(c, "CONFIG_ARMV8M")) {
            t.*.task.*.got_base = if (gp) |p| @intFromPtr(p) else 0;
        }
        hal.context_set(&t.*.ctx, hal.CTX_UENTRY, kutil.toReg(entry));
    }
    if (stack != null) {
        hal.context_set(&t.*.ctx, hal.CTX_USTACK, kutil.toReg(stack));
    }
    _ = hal.splx(s);

    return 0;
}

pub fn self() callconv(.c) kern.ThreadRef {
    return kutil.get_curthread();
}

pub fn valid(t: kern.ThreadRef) callconv(.c) c_int {
    const head = &thread_list;
    var n: *hal.List = @ptrCast(head.next);
    while (n != head) : (n = @ptrCast(n.next)) {
        const tmp: *kern.Thread = lib.IntrusiveList(kern.Thread, hal.List, "link").parent(n);
        if (tmp == t) return 1;
    }
    return 0;
}

pub fn yield() callconv(.c) void {
    sched.yield();
}

pub fn @"suspend"(t: kern.ThreadRef) callconv(.c) c_int {
    sched.lock();
    defer sched.unlock();

    if (valid(t) == 0) {
        return kern.Errno.ESRCH;
    }
    if (task.access(t.*.task) == 0) {
        return kern.Errno.EPERM;
    }
    t.*.suscnt += 1;
    if (t.*.suscnt == 1) {
        sched.@"suspend"(t);
        if (comptime @hasDecl(c, "CONFIG_ARMV8M")) {
            if (t.*.ctx.uregs != null and t.*.ctx.saved_uregs_valid == 0) {
                _ = lib.memcpy(&t.*.ctx.saved_uregs, t.*.ctx.uregs, @sizeOf(hal.CpuRegs));
                t.*.ctx.saved_uregs_ptr = t.*.ctx.uregs;
                t.*.ctx.saved_uregs_valid = 1;
                t.*.ctx.uregs = &t.*.ctx.saved_uregs;
            }
        }
    }

    return 0;
}

pub fn @"resume"(t: kern.ThreadRef) callconv(.c) c_int {
    sched.lock();
    defer sched.unlock();

    if (valid(t) == 0) {
        return kern.Errno.ESRCH;
    }
    if (task.access(t.*.task) == 0) {
        return kern.Errno.EPERM;
    }
    if (t.*.suscnt == 0) {
        return kern.Errno.EINVAL;
    }
    t.*.suscnt -= 1;
    if (t.*.suscnt == 0 and t.*.task.*.suscnt == 0) {
        sched.@"resume"(t);
    }

    return 0;
}

pub fn schedparam(t: kern.ThreadRef, op: c_int, param: ?*c_int) callconv(.c) c_int {
    var pri: c_int = undefined;
    var policy: c_int = undefined;
    var err: c_int = 0;

    sched.lock();
    defer sched.unlock();

    if (valid(t) == 0) {
        return kern.Errno.ESRCH;
    }
    if (t.*.task.*.flags & kern.TF_SYSTEM != 0) {
        return kern.Errno.EINVAL;
    }

    if (!(t.*.task == kutil.get_curtask() or t.*.task.*.parent == kutil.get_curtask()) and task.capable(kern.CAP_NICE) == 0) {
        return kern.Errno.EPERM;
    }

    switch (op) {
        kern.SOP_GETPRI => {
            pri = sched.get_pri(t);
            if (hal.copyout(&pri, param, @sizeOf(c_int)) != 0) {
                err = kern.Errno.EINVAL;
            }
        },
        kern.SOP_SETPRI => {
            if (hal.copyin(param, &pri, @sizeOf(c_int)) != 0) {
                err = kern.Errno.EINVAL;
            } else {
                if (pri < 0) pri = 0;
                if (pri >= hal.PRI_IDLE) pri = hal.PRI_IDLE - 1;

                if (pri <= hal.PRI_REALTIME and task.capable(kern.CAP_NICE) == 0) {
                    err = kern.Errno.EPERM;
                } else {
                    if (t.*.priority != t.*.basepri and pri > t.*.priority) {
                        pri = t.*.priority;
                    }

                    mutex.setpri(t, pri);
                    sched.set_pri(t, pri, pri);
                }
            }
        },
        kern.SOP_GETPOLICY => {
            policy = sched.get_policy(t);
            if (hal.copyout(&policy, param, @sizeOf(c_int)) != 0) {
                err = kern.Errno.EINVAL;
            }
        },
        kern.SOP_SETPOLICY => {
            if (hal.copyin(param, &policy, @sizeOf(c_int)) != 0) {
                err = kern.Errno.EINVAL;
            } else {
                err = sched.set_policy(t, policy);
            }
        },
        else => {
            err = kern.Errno.EINVAL;
        },
    }

    return err;
}

pub fn idle() callconv(.c) void {
    while (true) {
        hal.machine_idle();
    }
}

pub fn info(tinfo: ?*hal.ThreadInfo) callconv(.c) c_int {
    const target = tinfo.?.cookie;
    var i: c_ulong = 0;

    sched.lock();
    defer sched.unlock();

    var n: *hal.List = @ptrCast(thread_list.prev);
    while (n != &thread_list) {
        if (i == target) {
            const t: *kern.Thread = lib.IntrusiveList(kern.Thread, hal.List, "link").parent(n);
            tinfo.?.cookie = i;
            tinfo.?.id = t;
            tinfo.?.state = t.state;
            tinfo.?.policy = t.policy;
            tinfo.?.priority = t.priority;
            tinfo.?.basepri = t.basepri;
            tinfo.?.time = t.time;
            tinfo.?.suscnt = t.suscnt;
            tinfo.?.task = t.task;
            tinfo.?.active = if (t == @as(?*kern.Thread, @ptrCast(kutil.get_curthread().?))) 1 else 0;
            _ = lib.strlcpy(@ptrCast(&tinfo.?.taskname), @ptrCast(&t.task.*.name), hal.MAXTASKNAME);
            _ = lib.strlcpy(@ptrCast(&tinfo.?.slpevt), if (t.slpevt) |evt| @as([*c]const u8, @ptrCast(evt.*.name)) else @as([*c]const u8, "-"), hal.MAXEVTNAME);
            return 0;
        }
        i += 1;
        n = @ptrCast(n.prev);
    }

    return kern.Errno.ESRCH;
}

pub fn createKernel(entry: ?*const fn (?*anyopaque) callconv(.c) void, arg: ?*anyopaque, pri: c_int) callconv(.c) kern.ThreadRef {
    const t = allocate(&kern.kernel_task) orelse return null;

    _ = lib.memset(t.*.kstack, 0, hal.KSTACKSZ);
    const sp: usize = @intFromPtr(t.*.kstack) + hal.KSTACKSZ;
    hal.context_set(&t.*.ctx, hal.CTX_KSTACK, kutil.toReg(sp));
    hal.context_set(&t.*.ctx, hal.CTX_KENTRY, kutil.toReg(entry));
    hal.context_set(&t.*.ctx, hal.CTX_KARG, kutil.toReg(arg));
    sched.start(t, pri, kern.SCHED_FIFO);
    t.*.suscnt = 1;
    sched.@"resume"(t);

    return t;
}

pub fn terminateKernel(t: kern.ThreadRef) callconv(.c) void {
    sched.lock();
    defer sched.unlock();

    mutex.cancel(t);
    timer.cancel(t);
    sched.stop(t);
    deallocate(t);
}

pub fn createIdle() callconv(.c) kern.ThreadRef {
    const t = allocate(&kern.kernel_task) orelse @panic("thread_create_idle");

    _ = lib.memset(t.*.kstack, 0, hal.KSTACKSZ);
    t.*.state = kern.TS_RUN;
    t.*.locks = 1;
    t.*.priority = hal.PRI_IDLE;

    return t;
}

pub fn init() callconv(.c) void {
    const stack = kmem.alloc(hal.KSTACKSZ) orelse @panic("thread_init");
    list_init(&thread_list);

    _ = lib.memset(stack, 0, hal.KSTACKSZ);
    const sp: usize = @intFromPtr(stack) + hal.KSTACKSZ;
    hal.context_set(&idle_thread.ctx, hal.CTX_KSTACK, kutil.toReg(sp));
    sched.start(&idle_thread, hal.PRI_IDLE, kern.SCHED_FIFO);
    idle_thread.kstack = stack;
    idle_thread.task = &kern.kernel_task;
    idle_thread.state = kern.TS_RUN;
    list_init(&idle_thread.mutexes);

    list_insert(&thread_list, &idle_thread.link);
    list_insert(&kern.kernel_task.threads, &idle_thread.task_link);
    kern.kernel_task.nthreads = 1;
}
