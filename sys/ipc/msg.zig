const std = @import("std");

const c = @import("c").c;
const ffi = @import("ffi");
const hal = ffi.hal;
const kern = ffi.kern;
const sync = ffi.sync;
const kutil = ffi.kutil;
const smp = ffi.smp;
const kmem = ffi.kmem;
const sched = ffi.sched;
const object = ffi.object;
const thread = ffi.thread;

var ipc_event: sync.Event = undefined;





fn dequeue(head: *ffi.Queue) ?*kern.Thread {
    var q = head.first();
    var top = q.entry(kern.Thread, "ipc_link");

    while (q != head) {
        const t = q.entry(kern.Thread, "ipc_link");
        if (t.priority < top.priority) {
            top = t;
        }
        q = q.nextNode();
    }
    ffi.IntrusiveQueue(kern.Thread, ffi.Queue, "ipc_link").node(top).remove();
    return top;
}

pub fn send(obj: kern.ObjectRef, msg: ?*anyopaque, size: usize) callconv(.c) c_int {
    if (!kutil.user_area(msg)) {
        return kern.Errno.EFAULT;
    }
    if (size < @sizeOf(ffi.hal.MsgHeader)) {
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

    const hdr: *ffi.hal.MsgHeader = @ptrCast(@alignCast(kmsg));
    hdr.task = kutil.get_curtask();

    if (!ffi.IntrusiveQueue(ffi.hal.Object, ffi.Queue, "recvq").node(obj.?).isEmpty()) {
        const t = dequeue(ffi.IntrusiveQueue(ffi.hal.Object, ffi.Queue, "recvq").node(obj.?));
        sched.unsleep(t, 0);
    }

    kutil.get_curthread().?.sendobj = obj;
    ffi.IntrusiveQueue(ffi.hal.Object, ffi.Queue, "sendq").node(obj.?).enqueue(ffi.IntrusiveQueue(ffi.hal.Thread, ffi.Queue, "ipc_link").node(kutil.get_curthread().?));
    const rc = sched.tsleep(&ipc_event, 0);
    if (rc == kern.SLP_INTR) {
        ffi.IntrusiveQueue(ffi.hal.Thread, ffi.Queue, "ipc_link").node(kutil.get_curthread().?).remove();
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

    while (ffi.IntrusiveQueue(ffi.hal.Object, ffi.Queue, "sendq").node(obj.?).isEmpty()) {
        ffi.IntrusiveQueue(ffi.hal.Object, ffi.Queue, "recvq").node(obj.?).enqueue(ffi.IntrusiveQueue(ffi.hal.Thread, ffi.Queue, "ipc_link").node(kutil.get_curthread().?));
        rc = sched.tsleep(&ipc_event, 0);
        if (rc != 0) {
            switch (rc) {
                kern.SLP_INVAL => {
                    err_code = kern.Errno.EINVAL;
                },
                kern.SLP_INTR => {
                    ffi.IntrusiveQueue(ffi.hal.Thread, ffi.Queue, "ipc_link").node(kutil.get_curthread().?).remove();
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

    const t = dequeue(ffi.IntrusiveQueue(ffi.hal.Object, ffi.Queue, "sendq").node(obj.?));

    const len: usize = if (size < t.?.msgsize) size else t.?.msgsize;
    if (len > 0) {
        if (hal.copyout(t.?.msgaddr, msg, len) != 0) {
            ffi.IntrusiveQueue(ffi.hal.Object, ffi.Queue, "sendq").node(obj.?).enqueue(ffi.IntrusiveQueue(ffi.hal.Thread, ffi.Queue, "ipc_link").node(t.?));
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
            ffi.IntrusiveQueue(ffi.hal.Thread, ffi.Queue, "ipc_link").node(t.?).remove();
        }
    }
    if (t.?.recvobj != null) {
        if (t.?.sender != null) {
            const sender: ?*kern.Thread = @ptrCast(t.?.sender);
            sched.unsleep(sender, kern.SLP_BREAK);
            sender.?.receiver = null;
        } else {
            ffi.IntrusiveQueue(ffi.hal.Thread, ffi.Queue, "ipc_link").node(t.?).remove();
        }
    }
}

pub fn abort(obj: kern.ObjectRef) callconv(.c) void {
    sched.lock();
    defer sched.unlock();

    while (!ffi.IntrusiveQueue(ffi.hal.Object, ffi.Queue, "sendq").node(obj.?).isEmpty()) {
        const q = ffi.IntrusiveQueue(ffi.hal.Object, ffi.Queue, "sendq").node(obj.?).dequeue().?;
        const t = q.entry(kern.Thread, "ipc_link");
        sched.unsleep(t, kern.SLP_INVAL);
    }

    while (!ffi.IntrusiveQueue(ffi.hal.Object, ffi.Queue, "recvq").node(obj.?).isEmpty()) {
        const q = ffi.IntrusiveQueue(ffi.hal.Object, ffi.Queue, "recvq").node(obj.?).dequeue().?;
        const t = q.entry(kern.Thread, "ipc_link");
        sched.unsleep(t, kern.SLP_INVAL);
    }
}

pub fn init() callconv(.c) void {
    sync.event_init(@as(?*anyopaque, @ptrCast(&ipc_event)), "ipc");
}

comptime {
    if (@import("root") == @This()) {
        @export(&send, .{ .name = "msg_send", .linkage = .strong });
        @export(&receive, .{ .name = "msg_receive", .linkage = .strong });
        @export(&reply, .{ .name = "msg_reply", .linkage = .strong });
        @export(&cancel, .{ .name = "msg_cancel", .linkage = .strong });
        @export(&abort, .{ .name = "msg_abort", .linkage = .strong });
        @export(&init, .{ .name = "msg_init", .linkage = .strong });
    }
}
