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

extern fn zig_memory_barrier() callconv(.c) void;

const ffi = @import("ffi");
const hal = ffi.hal;
const kern = ffi.kern;
const kmem = ffi.kmem;
const kutil = ffi.kutil;
const lib = ffi.lib;
const msg = ffi.msg;
const sched = ffi.sched;
const task = ffi.task;
var object_list: lib.List = .{};

fn find(name: [*:0]const u8) ?*hal.Object {
    var n = object_list.first();
    while (n != &object_list) {
        const obj = n.entry(hal.Object, "link");
        if (lib.strncmp(&obj.name, name, hal.MAXOBJNAME) == 0) {
            return obj;
        }
        n = n.nextNode();
    }
    return null;
}

fn deallocate(obj: *hal.Object) void {
    msg.abort(obj);
    const owner = @as(*kern.Task, @ptrCast(obj.owner));
    owner.nobjects -|= 1;
    lib.IntrusiveList(hal.Object, lib.List, "task_link").node(obj).remove();
    lib.IntrusiveList(hal.Object, lib.List, "link").node(obj).remove();
    kmem.free(obj);
}

pub fn create(name: ?[*:0]const u8, objp: ?*kern.ObjectRef) callconv(.c) c_int {
    var str: [hal.MAXOBJNAME:0]u8 = undefined;

    if (name == null) {
        str[0] = 0;
    } else {
        const name_ptr = name.?;
        var i: usize = 0;
        while (i < hal.MAXOBJNAME - 1 and name_ptr[i] != 0) : (i += 1) {
            str[i] = name_ptr[i];
        }
        str[i] = 0;

        if (name_ptr[0] == '!' and task.capable(kern.CAP_PROTSERV) == 0) {
            return kern.Errno.EPERM;
        }
    }

    sched.lock();
    defer sched.unlock();

    const cur = kutil.get_curtask().?;
    if (cur.nobjects >= hal.MAXOBJECTS) {
        return kern.Errno.EAGAIN;
    }

    const null_obj: kern.ObjectRef = null;
    if (hal.copyout(@as(?*const anyopaque, @ptrCast(&null_obj)), @as(?*anyopaque, @ptrCast(objp)), @sizeOf(kern.ObjectRef)) != 0) {
        return kern.Errno.EFAULT;
    }

    if (find(&str) != null) {
        return kern.Errno.EEXIST;
    }

    const mem = kmem.alloc(@sizeOf(hal.Object)) orelse return kern.Errno.ENOMEM;
    const obj: ?*hal.Object = @ptrCast(@alignCast(mem));
    errdefer kmem.free(mem);

    if (name != null) {
        _ = lib.strlcpy(&obj.?.name, &str, hal.MAXOBJNAME);
    }

    obj.?.owner = cur;
    lib.IntrusiveQueue(hal.Object, lib.Queue, "sendq").node(obj.?).init();
    lib.IntrusiveQueue(hal.Object, lib.Queue, "recvq").node(obj.?).init();
    lib.IntrusiveList(kern.Task, lib.List, "objects").node(cur).insertAfter(lib.IntrusiveList(hal.Object, lib.List, "task_link").node(obj.?));
    cur.nobjects += 1;
    object_list.insertAfter(lib.IntrusiveList(hal.Object, lib.List, "link").node(obj.?));

    zig_memory_barrier();

    _ = hal.copyout(@as(?*const anyopaque, @ptrCast(&obj)), @as(?*anyopaque, @ptrCast(objp)), @sizeOf(kern.ObjectRef));

    return 0;
}

pub fn lookup(name: [*:0]const u8, objp: ?*kern.ObjectRef) callconv(.c) c_int {
    var str: [hal.MAXOBJNAME:0]u8 = undefined;

    var i: usize = 0;
    while (i < hal.MAXOBJNAME - 1 and name[i] != 0) : (i += 1) {
        str[i] = name[i];
    }
    str[i] = 0;

    sched.lock();
    const obj = find(&str);
    sched.unlock();

    if (obj == null) {
        return kern.Errno.ENOENT;
    }

    if (hal.copyout(@as(?*const anyopaque, @ptrCast(&obj)), @as(?*anyopaque, @ptrCast(objp)), @sizeOf(kern.ObjectRef)) != 0) {
        return kern.Errno.EFAULT;
    }
    return 0;
}

pub fn valid(obj: kern.ObjectRef) callconv(.c) c_int {
    var n = object_list.first();
    while (n != &object_list) {
        const tmp = n.entry(hal.Object, "link");
        if (tmp == obj) {
            return 1;
        }
        n = n.nextNode();
    }
    return 0;
}

pub fn destroy(obj: kern.ObjectRef) callconv(.c) c_int {
    sched.lock();
    defer sched.unlock();
    if (valid(obj) == 0) {
        return kern.Errno.EINVAL;
    }
    const target_obj = @as(*hal.Object, @ptrCast(obj));
    if (@intFromPtr(target_obj.owner) != @intFromPtr(kutil.get_curtask())) {
        return kern.Errno.EACCES;
    }
    deallocate(target_obj);
    return 0;
}

pub fn cleanup(tsk: kern.TaskRef) callconv(.c) void {
    const t = @as(*kern.Task, @ptrCast(tsk));
    const head = lib.IntrusiveList(kern.Task, lib.List, "objects").node(t);
    while (!head.isEmpty()) {
        const obj = head.first().entry(hal.Object, "task_link");
        deallocate(obj);
    }
}

pub fn init() callconv(.c) void {
    object_list.init();
}
