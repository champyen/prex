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

const c = @import("c").c;
const ffi = @import("ffi");
const lib = ffi.lib;
const deadlock = ffi.deadlock;
const hal = ffi.hal;
const kern = ffi.kern;
const kmem = ffi.kmem;
const kutil = ffi.kutil;
const mutex = ffi.mutex;
const sched = ffi.sched;
const sync = ffi.sync;
inline fn is_cond_initializer(m: kern.CondRef) bool {
    if (m) |ptr| {
        return @intFromPtr(ptr) == 0x43496e69;
    }
    return false;
}

fn valid(m: kern.CondRef) c_int {
    const km: *sync.Cond = @ptrCast(m);
    const CL = lib.IntrusiveList(kern.Task, lib.List, "conds");
    const self = kutil.cur_task();
    const head = CL.node(self);
    var n = head.first();
    while (n != head) : (n = n.nextNode()) {
        const tmp = n.entry(sync.Cond, "task_link");
        if (tmp == km) {
            return 1;
        }
    }
    return 0;
}

fn copyin(ucp: ?*kern.CondRef, kcp: ?*kern.CondRef) c_int {
    var m: kern.CondRef = undefined;
    if (hal.copyin(@as(?*const anyopaque, @ptrCast(ucp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(kern.CondRef)) != 0) {
        return kern.Errno.EFAULT;
    }

    if (is_cond_initializer(m)) {
        const error_code = init(ucp);
        if (error_code != 0) {
            return error_code;
        }
        _ = hal.copyin(@as(?*const anyopaque, @ptrCast(ucp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(kern.CondRef));
    } else {
        if (valid(m) == 0) {
            return kern.Errno.EINVAL;
        }
    }
    kcp.?.* = m;
    return 0;
}

pub fn init(cp: ?*kern.CondRef) callconv(.c) c_int {
    const self = kutil.cur_task();
    if (self.*.nsyncs >= hal.MAXSYNCS) {
        return kern.Errno.EAGAIN;
    }

    const mem = kmem.alloc(@sizeOf(sync.Cond)) orelse return kern.Errno.ENOMEM;
    const m: kern.CondRef = @ptrCast(@alignCast(mem));
    errdefer kmem.free(m);

    sync.event_init(&m.*.event, "condvar");
    m.*.owner = self;

    if (hal.copyout(@as(?*const anyopaque, @ptrCast(&m)), @as(?*anyopaque, @ptrCast(cp)), @sizeOf(kern.CondRef)) != 0) {
        return kern.Errno.EFAULT;
    }

    sched.lock();
    defer sched.unlock();
    const TL = lib.IntrusiveList(kern.Task, lib.List, "conds");
    const ML = lib.IntrusiveList(sync.Cond, lib.List, "task_link");
    TL.node(self).insertAfter(ML.node(m));
    self.*.nsyncs += 1;
    return 0;
}

fn deallocate(m: kern.CondRef) void {
    m.*.owner.*.nsyncs -= 1;
    lib.IntrusiveList(sync.Cond, lib.List, "task_link").node(m).remove();
    kmem.free(m);
}

pub fn destroy(cp: ?*kern.CondRef) callconv(.c) c_int {
    var m: kern.CondRef = undefined;
    sched.lock();
    defer sched.unlock();
    if (hal.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(kern.CondRef)) != 0) {
        return kern.Errno.EFAULT;
    }
    if (valid(m) == 0) {
        return kern.Errno.EINVAL;
    }
    const km: *sync.Cond = @ptrCast(m);
    if (!km.*.event.sleepq.isEmpty()) {
        return kern.Errno.EBUSY;
    }
    deallocate(m);
    return 0;
}

pub fn cleanup(task: kern.TaskRef) callconv(.c) void {
    const TL = lib.IntrusiveList(kern.Task, lib.List, "conds");
    const head = TL.node(task);
    while (!head.isEmpty()) {
        const n = head.first();
        const m = n.entry(sync.Cond, "task_link");
        deallocate(@ptrCast(m));
    }
}

pub fn wait(cp: ?*kern.CondRef, mp: ?*kern.MutexRef) callconv(.c) c_int {
    var m: kern.CondRef = undefined;

    if (hal.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(kern.CondRef)) != 0) {
        return kern.Errno.EINVAL;
    }

    sched.lock();
    if (is_cond_initializer(m)) {
        const error_code = init(cp);
        if (error_code != 0) {
            sched.unlock();
            return error_code;
        }
        _ = hal.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(kern.CondRef));
    } else {
        if (valid(m) == 0) {
            sched.unlock();
            return kern.Errno.EINVAL;
        }
    }

    const km: *sync.Cond = @ptrCast(m);
    var err: c_int = 0;

    const unlock_err = mutex.unlock(mp);
    if (unlock_err != 0) {
        sched.unlock();
        return unlock_err;
    }

    deadlock.sleep(@ptrCast(km), "cond");
    const rc = sched.tsleep(&km.*.event, 0);
    deadlock.stop_sleep();
    if (rc == kern.SLP_INTR) {
        err = kern.Errno.EINTR;
    }
    sched.unlock();

    if (err == 0) {
        err = mutex.lock(mp);
    }

    return err;
}

pub fn signal(cp: ?*kern.CondRef) callconv(.c) c_int {
    var m: kern.CondRef = undefined;

    sched.lock();
    defer sched.unlock();
    if (hal.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(kern.CondRef)) != 0) {
        return kern.Errno.EINVAL;
    }
    const km: *sync.Cond = @ptrCast(m);
    _ = sched.wakeone(&km.*.event);
    return 0;
}

pub fn broadcast(cp: ?*kern.CondRef) callconv(.c) c_int {
    var m: kern.CondRef = undefined;

    sched.lock();
    defer sched.unlock();
    if (hal.copyin(@as(?*const anyopaque, @ptrCast(cp)), @as(?*anyopaque, @ptrCast(&m)), @sizeOf(kern.CondRef)) != 0) {
        return kern.Errno.EINVAL;
    }
    const km: *sync.Cond = @ptrCast(m);
    sched.wakeup(&km.*.event);
    return 0;
}
