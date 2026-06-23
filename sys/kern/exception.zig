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

const c = @import("c").c;

const ffi = @import("ffi");
const lib = ffi.lib;
const hal = ffi.hal;
const kern = ffi.kern;
const kutil = ffi.kutil;
const sched = ffi.sched;
const sync = ffi.sync;
const task = ffi.task;
var EXC_DFL: ?*const fn (c_int) callconv(.c) void = undefined;

var exception_event: sync.Event = undefined;




inline fn list_first(head: *hal.List) ?*hal.List {
    return @ptrCast(head.next);
}

inline fn list_next(node: *hal.List) ?*hal.List {
    return @ptrCast(node.next);
}

inline fn list_empty(head: *hal.List) bool {
    return head.next == @as(?*hal.List, @ptrCast(head));
}

pub fn setup(handler: ?*const fn (c_int) callconv(.c) void) callconv(.c) c_int {
    const self = kutil.get_curtask() orelse return kern.Errno.EINVAL;

    if (handler != EXC_DFL and !kutil.user_area(handler)) {
        return kern.Errno.EFAULT;
    }
    if (handler == null) {
        return kern.Errno.EINVAL;
    }

    sched.lock();
    defer sched.unlock();
    if (self.handler != EXC_DFL and handler == EXC_DFL) {
        var n = list_first(&self.threads);
        while (n != null and n.? != @as(?*hal.List, @ptrCast(&self.threads))) {
            const s = hal.splhigh();
            const t: *kern.Thread = lib.IntrusiveList(kern.Thread, hal.List, "task_link").parent(n.?);
            t.excbits = 0;
            _ = hal.splx(s);

            if (t.slpevt == @as(?*hal.Event, @alignCast(@ptrCast(&exception_event)))) {
                sched.unsleep(t, kern.SLP_BREAK);
            }
            n = list_next(n.?);
        }
    }
    self.handler = handler;
    return 0;
}

pub fn raise(t: kern.TaskRef, excno: c_int) callconv(.c) c_int {
    var error_code: c_int = undefined;

    sched.lock();
    defer sched.unlock();
    if (task.valid(t) == 0) {
        return kern.Errno.ESRCH;
    }
    if (t != @as(?*kern.Task, @ptrCast(kutil.get_curtask())) and task.capable(kern.CAP_KILL) == 0) {
        return kern.Errno.EPERM;
    }
    error_code = post(t, excno);
    return error_code;
}

pub fn post(task_arg: kern.TaskRef, excno: c_int) callconv(.c) c_int {
    var t: ?*kern.Thread = null;
    var found: c_int = 0;

    sched.lock();
    defer sched.unlock();
    if (task_arg.*.flags & kern.TF_SYSTEM != 0) {
        return kern.Errno.EPERM;
    }

    if (task_arg.*.handler == EXC_DFL or task_arg.*.nthreads == 0 or excno < 0 or excno >= hal.NEXC) {
        return kern.Errno.EINVAL;
    }

    var n = list_first(&task_arg.*.threads);
    while (n != null and n.? != @as(?*hal.List, @ptrCast(&task_arg.*.threads))) {
        const tmp: *kern.Thread = lib.IntrusiveList(kern.Thread, hal.List, "task_link").parent(n.?);
        if (tmp.slpevt == @as(?*hal.Event, @alignCast(@ptrCast(&exception_event)))) {
            t = tmp;
            found = 1;
            break;
        }
        n = list_next(n.?);
    }

    if (found == 0) {
        if (!list_empty(&task_arg.*.threads)) {
            const first: *kern.Thread = lib.IntrusiveList(kern.Thread, hal.List, "task_link").parent(list_first(&task_arg.*.threads).?);
            t = first;
        }
    }

    const s = hal.splhigh();
    t.?.excbits |= @as(u32, 1) << @intCast(excno);
    _ = hal.splx(s);

    sched.unsleep(t.?, kern.SLP_INTR);

    return 0;
}

pub fn wait(excno: ?*c_int) callconv(.c) c_int {
    var i: c_int = 0;
    var rc: c_int = undefined;
    var s: c_int = undefined;

    if (kutil.get_curtask().?.handler == EXC_DFL) {
        return kern.Errno.EINVAL;
    }

    i = 0;
    if (hal.copyout(@as(?*const anyopaque, @ptrCast(&i)), @as(?*anyopaque, @ptrCast(excno)), @sizeOf(c_int)) != 0) {
        return kern.Errno.EFAULT;
    }

    sched.lock();

    rc = sched.tsleep(&exception_event, 0);
    if (rc == kern.SLP_BREAK) {
        sched.unlock();
        return kern.Errno.EINVAL;
    }
    s = hal.splhigh();
    var j: c_int = 0;
    while (j < hal.NEXC) : (j += 1) {
        if (kutil.get_curthread().?.excbits & (@as(u32, 1) << @intCast(j)) != 0) {
            break;
        }
    }
    _ = hal.splx(s);
    sched.unlock();

    i = j;
    if (hal.copyout(@as(?*const anyopaque, @ptrCast(&i)), @as(?*anyopaque, @ptrCast(excno)), @sizeOf(c_int)) != 0) {
        return kern.Errno.EFAULT;
    }
    return kern.Errno.EINTR;
}

pub fn mark(excno: c_int) callconv(.c) void {
    const s = hal.splhigh();
    kutil.get_curthread().?.excbits |= @as(u32, 1) << @intCast(excno);
    _ = hal.splx(s);
}

pub fn deliver() callconv(.c) void {
    const self = kutil.get_curtask().?;
    var handler: ?*const fn (c_int) callconv(.c) void = undefined;
    var bitmap: u32 = undefined;
    var s: c_int = undefined;
    var excno: c_int = undefined;

    sched.lock();
    defer sched.unlock();

    s = hal.splhigh();
    bitmap = kutil.get_curthread().?.excbits;
    _ = hal.splx(s);

    if (bitmap != 0) {
        excno = 0;
        while (excno < hal.NEXC) : (excno += 1) {
            if (bitmap & (@as(u32, 1) << @intCast(excno)) != 0) {
                break;
            }
        }
        handler = self.handler;
        if (handler == EXC_DFL) {
            _ = task.terminate(self);
        }

        s = hal.splhigh();
        hal.context_save(&kutil.get_curthread().?.ctx);
        hal.context_set(&kutil.get_curthread().?.ctx, hal.CTX_UENTRY, kutil.toReg(handler));
        hal.context_set(&kutil.get_curthread().?.ctx, hal.CTX_UARG, kutil.toReg(excno));
        kutil.get_curthread().?.excbits &= ~(@as(u32, 1) << @intCast(excno));
        _ = hal.splx(s);
    }
}

pub fn @"return"() callconv(.c) void {
    const s = hal.splhigh();
    hal.context_restore(&kutil.get_curthread().?.ctx);
    _ = hal.splx(s);
}

pub fn init() callconv(.c) void {
    @as(*usize, @ptrCast(&EXC_DFL)).* = @as(usize, @bitCast(@as(isize, -1)));
    sync.event_init(@as(?*anyopaque, @ptrCast(&exception_event)), "exception");
}
