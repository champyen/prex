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
const kmem = ffi.kmem;
const kutil = ffi.kutil;
const object = ffi.object;
const sched = ffi.sched;
const sync = ffi.sync;
var ipc_event: sync.Event = undefined;





fn dequeue(head: *lib.Queue) ?*kern.Thread {
    var q = head.first();
    var top = q.entry(kern.Thread, "ipc_link");

    while (q != head) {
        const t = q.entry(kern.Thread, "ipc_link");
        if (t.priority < top.priority) {
            top = t;
        }
        q = q.nextNode();
    }
    lib.IntrusiveQueue(kern.Thread, lib.Queue, "ipc_link").node(top).remove();
    return top;
}

pub fn send(obj: kern.ObjectRef, msg: ?*anyopaque, size: usize) callconv(.c) c_int {
    if (!kutil.user_area(msg)) {
        return kern.Errno.EFAULT;
    }
    if (size < @sizeOf(hal.MsgHeader)) {
        return kern.Errno.EINVAL;
    }

    sched.lock();
    defer sched.unlock();

    if (object.valid(obj) == 0) {
        return kern.Errno.EINVAL;
    }

    if (obj == kutil.get_curthread().?.recvobj) {
        return kern.Errno.EDEADLK;
    }

    const kmsg = kmem.map(msg, size) orelse return kern.Errno.EFAULT;
    kutil.get_curthread().?.msgaddr = kmsg;
    kutil.get_curthread().?.msgsize = size;

    const hdr: *hal.MsgHeader = @ptrCast(@alignCast(kmsg));
    hdr.task = kutil.get_curtask();

    if (!lib.IntrusiveQueue(hal.Object, lib.Queue, "recvq").node(obj.?).isEmpty()) {
        const t = dequeue(lib.IntrusiveQueue(hal.Object, lib.Queue, "recvq").node(obj.?));
        sched.unsleep(t, 0);
    }

    kutil.get_curthread().?.sendobj = obj;
    lib.IntrusiveQueue(hal.Object, lib.Queue, "sendq").node(obj.?).enqueue(lib.IntrusiveQueue(hal.Thread, lib.Queue, "ipc_link").node(kutil.get_curthread().?));
    const rc = sched.tsleep(&ipc_event, 0);
    if (rc == kern.SLP_INTR) {
        lib.IntrusiveQueue(hal.Thread, lib.Queue, "ipc_link").node(kutil.get_curthread().?).remove();
    }
    kutil.get_curthread().?.sendobj = null;

    switch (rc) {
        kern.SLP_BREAK => {
            return kern.Errno.EAGAIN;
        },
        kern.SLP_INVAL => {
            return kern.Errno.EINVAL;
        },
        kern.SLP_INTR => {
            return kern.Errno.EINTR;
        },
        else => {},
    }
    return 0;
}

pub fn receive(obj: kern.ObjectRef, msg: ?*anyopaque, size: usize) callconv(.c) c_int {
    var rc: c_int = undefined;
    var err_code: c_int = 0;

    if (!kutil.user_area(msg)) {
        return kern.Errno.EFAULT;
    }

    sched.lock();
    defer sched.unlock();

    if (object.valid(obj) == 0) {
        return kern.Errno.EINVAL;
    }
    if (obj.*.owner != kutil.get_curtask()) {
        return kern.Errno.EACCES;
    }

    if (kutil.get_curthread().?.recvobj != null) {
        return kern.Errno.EBUSY;
    }
    kutil.get_curthread().?.recvobj = obj;

    while (lib.IntrusiveQueue(hal.Object, lib.Queue, "sendq").node(obj.?).isEmpty()) {
        lib.IntrusiveQueue(hal.Object, lib.Queue, "recvq").node(obj.?).enqueue(lib.IntrusiveQueue(hal.Thread, lib.Queue, "ipc_link").node(kutil.get_curthread().?));
        rc = sched.tsleep(&ipc_event, 0);
        if (rc != 0) {
            switch (rc) {
                kern.SLP_INVAL => {
                    err_code = kern.Errno.EINVAL;
                },
                kern.SLP_INTR => {
                    lib.IntrusiveQueue(hal.Thread, lib.Queue, "ipc_link").node(kutil.get_curthread().?).remove();
                    err_code = kern.Errno.EINTR;
                },
                else => {
                    @panic("receive");
                },
            }
            kutil.get_curthread().?.recvobj = null;
            return err_code;
        }
    }

    const t = dequeue(lib.IntrusiveQueue(hal.Object, lib.Queue, "sendq").node(obj.?));

    const len: usize = if (size < t.?.msgsize) size else t.?.msgsize;
    if (len > 0) {
        if (hal.copyout(t.?.msgaddr, msg, len) != 0) {
            lib.IntrusiveQueue(hal.Object, lib.Queue, "sendq").node(obj.?).enqueue(lib.IntrusiveQueue(hal.Thread, lib.Queue, "ipc_link").node(t.?));
            kutil.get_curthread().?.recvobj = null;
            return kern.Errno.EFAULT;
        }
    }

    kutil.get_curthread().?.sender = t;
    t.?.receiver = kutil.get_curthread();

    return err_code;
}

pub fn reply(obj: kern.ObjectRef, msg: ?*anyopaque, size: usize) callconv(.c) c_int {
    if (!kutil.user_area(msg)) {
        return kern.Errno.EFAULT;
    }

    sched.lock();
    defer sched.unlock();

    if (object.valid(obj) == 0 or @intFromPtr(obj) != @intFromPtr(kutil.get_curthread().?.recvobj)) {
        return kern.Errno.EINVAL;
    }

    if (kutil.get_curthread().?.sender == null) {
        kutil.get_curthread().?.recvobj = null;
        return kern.Errno.EINVAL;
    }

    const t: ?*kern.Thread = @ptrCast(kutil.get_curthread().?.sender);
    const len: usize = if (size < t.?.msgsize) size else t.?.msgsize;
    if (len > 0) {
        if (hal.copyin(msg, t.?.msgaddr, len) != 0) {
            return kern.Errno.EFAULT;
        }
    }

    sched.unsleep(t, 0);
    t.?.receiver = null;

    kutil.get_curthread().?.sender = null;
    kutil.get_curthread().?.recvobj = null;

    return 0;
}

pub fn cancel(t: ?*kern.Thread) callconv(.c) void {
    sched.lock();
    defer sched.unlock();

    if (t.?.sendobj != null) {
        if (t.?.receiver != null) {
            const receiver: ?*kern.Thread = @ptrCast(t.?.receiver);
            receiver.?.sender = null;
        } else {
            lib.IntrusiveQueue(hal.Thread, lib.Queue, "ipc_link").node(t.?).remove();
        }
    }
    if (t.?.recvobj != null) {
        if (t.?.sender != null) {
            const sender: ?*kern.Thread = @ptrCast(t.?.sender);
            sched.unsleep(sender, kern.SLP_BREAK);
            sender.?.receiver = null;
        } else {
            lib.IntrusiveQueue(hal.Thread, lib.Queue, "ipc_link").node(t.?).remove();
        }
    }
}

pub fn abort(obj: kern.ObjectRef) callconv(.c) void {
    sched.lock();
    defer sched.unlock();

    while (!lib.IntrusiveQueue(hal.Object, lib.Queue, "sendq").node(obj.?).isEmpty()) {
        const q = lib.IntrusiveQueue(hal.Object, lib.Queue, "sendq").node(obj.?).dequeue().?;
        const t = q.entry(kern.Thread, "ipc_link");
        sched.unsleep(t, kern.SLP_INVAL);
    }

    while (!lib.IntrusiveQueue(hal.Object, lib.Queue, "recvq").node(obj.?).isEmpty()) {
        const q = lib.IntrusiveQueue(hal.Object, lib.Queue, "recvq").node(obj.?).dequeue().?;
        const t = q.entry(kern.Thread, "ipc_link");
        sched.unsleep(t, kern.SLP_INVAL);
    }
}

pub fn init() callconv(.c) void {
    sync.event_init(@as(?*anyopaque, @ptrCast(&ipc_event)), "ipc");
}
