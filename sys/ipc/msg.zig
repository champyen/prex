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
    @as(*ffi.Queue, @ptrCast(&top.ipc_link)).remove();
    return top;
}

pub fn send(obj: c.object_t, msg: ?*anyopaque, size: usize) callconv(.c) c_int {
    if (!kutil.user_area(msg)) {
        return kern.Errno.EFAULT;
    }
    if (size < @sizeOf(c.struct_msg_header)) {
        return kern.Errno.EINVAL;
    }

    sched.lock();

    if (object.valid(obj) == 0) {
        sched.unlock();
        return kern.Errno.EINVAL;
    }

    if (obj == kutil.get_curthread().?.recvobj) {
        sched.unlock();
        return kern.Errno.EDEADLK;
    }

    const kmsg = kmem.map(msg, size);
    if (kmsg == null) {
        sched.unlock();
        return kern.Errno.EFAULT;
    }
    kutil.get_curthread().?.msgaddr = kmsg;
    kutil.get_curthread().?.msgsize = size;

    const hdr: *c.struct_msg_header = @ptrCast(@alignCast(kmsg));
    hdr.task = kutil.get_curtask();

    if (!@as(*ffi.Queue, @ptrCast(&obj.*.recvq)).isEmpty()) {
        const t = dequeue(@as(*ffi.Queue, @ptrCast(&obj.*.recvq)));
        sched.unsleep(t, 0);
    }

    kutil.get_curthread().?.sendobj = obj;
    @as(*ffi.Queue, @ptrCast(&obj.*.sendq)).enqueue(@as(*ffi.Queue, @ptrCast(&kutil.get_curthread().?.ipc_link)));
    const rc = sched.tsleep(&ipc_event, 0);
    if (rc == kern.SLP_INTR) {
        @as(*ffi.Queue, @ptrCast(&kutil.get_curthread().?.ipc_link)).remove();
    }
    kutil.get_curthread().?.sendobj = null;

    sched.unlock();

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

pub fn receive(obj: c.object_t, msg: ?*anyopaque, size: usize) callconv(.c) c_int {
    var rc: c_int = undefined;
    var err_code: c_int = 0;

    if (!kutil.user_area(msg)) {
        return kern.Errno.EFAULT;
    }

    sched.lock();

    if (object.valid(obj) == 0) {
        sched.unlock();
        return kern.Errno.EINVAL;
    }
    if (obj.*.owner != kutil.get_curtask()) {
        sched.unlock();
        return kern.Errno.EACCES;
    }

    if (kutil.get_curthread().?.recvobj != null) {
        sched.unlock();
        return kern.Errno.EBUSY;
    }
    kutil.get_curthread().?.recvobj = obj;

    while (@as(*ffi.Queue, @ptrCast(&obj.*.sendq)).isEmpty()) {
        @as(*ffi.Queue, @ptrCast(&obj.*.recvq)).enqueue(@as(*ffi.Queue, @ptrCast(&kutil.get_curthread().?.ipc_link)));
        rc = sched.tsleep(&ipc_event, 0);
        if (rc != 0) {
            switch (rc) {
                kern.SLP_INVAL => {
                    err_code = kern.Errno.EINVAL;
                },
                kern.SLP_INTR => {
                    @as(*ffi.Queue, @ptrCast(&kutil.get_curthread().?.ipc_link)).remove();
                    err_code = kern.Errno.EINTR;
                },
                else => {
                    @panic("receive");
                },
            }
            kutil.get_curthread().?.recvobj = null;
            sched.unlock();
            return err_code;
        }
    }

    const t = dequeue(@as(*ffi.Queue, @ptrCast(&obj.*.sendq)));

    const len: usize = if (size < t.?.msgsize) size else t.?.msgsize;
    if (len > 0) {
        if (hal.copyout(t.?.msgaddr, msg, len) != 0) {
            @as(*ffi.Queue, @ptrCast(&obj.*.sendq)).enqueue(@as(*ffi.Queue, @ptrCast(&t.?.ipc_link)));
            kutil.get_curthread().?.recvobj = null;
            sched.unlock();
            return kern.Errno.EFAULT;
        }
    }

    kutil.get_curthread().?.sender = t;
    t.?.receiver = kutil.get_curthread();

    sched.unlock();
    return err_code;
}

pub fn reply(obj: c.object_t, msg: ?*anyopaque, size: usize) callconv(.c) c_int {
    if (!kutil.user_area(msg)) {
        return kern.Errno.EFAULT;
    }

    sched.lock();

    if (object.valid(obj) == 0 or @intFromPtr(obj) != @intFromPtr(kutil.get_curthread().?.recvobj)) {
        sched.unlock();
        return kern.Errno.EINVAL;
    }

    if (kutil.get_curthread().?.sender == null) {
        kutil.get_curthread().?.recvobj = null;
        sched.unlock();
        return kern.Errno.EINVAL;
    }

    const t: ?*kern.Thread = @ptrCast(kutil.get_curthread().?.sender);
    const len: usize = if (size < t.?.msgsize) size else t.?.msgsize;
    if (len > 0) {
        if (hal.copyin(msg, t.?.msgaddr, len) != 0) {
            sched.unlock();
            return kern.Errno.EFAULT;
        }
    }

    sched.unsleep(t, 0);
    t.?.receiver = null;

    kutil.get_curthread().?.sender = null;
    kutil.get_curthread().?.recvobj = null;

    sched.unlock();
    return 0;
}

pub fn cancel(t: ?*kern.Thread) callconv(.c) void {
    sched.lock();

    if (t.?.sendobj != null) {
        if (t.?.receiver != null) {
            const receiver: ?*kern.Thread = @ptrCast(t.?.receiver);
            receiver.?.sender = null;
        } else {
            @as(*ffi.Queue, @ptrCast(&t.?.ipc_link)).remove();
        }
    }
    if (t.?.recvobj != null) {
        if (t.?.sender != null) {
            const sender: ?*kern.Thread = @ptrCast(t.?.sender);
            sched.unsleep(sender, kern.SLP_BREAK);
            sender.?.receiver = null;
        } else {
            @as(*ffi.Queue, @ptrCast(&t.?.ipc_link)).remove();
        }
    }
    sched.unlock();
}

pub fn abort(obj: c.object_t) callconv(.c) void {
    sched.lock();

    while (!@as(*ffi.Queue, @ptrCast(&obj.*.sendq)).isEmpty()) {
        const q = @as(*ffi.Queue, @ptrCast(&obj.*.sendq)).dequeue().?;
        const t = q.entry(kern.Thread, "ipc_link");
        sched.unsleep(t, kern.SLP_INVAL);
    }

    while (!@as(*ffi.Queue, @ptrCast(&obj.*.recvq)).isEmpty()) {
        const q = @as(*ffi.Queue, @ptrCast(&obj.*.recvq)).dequeue().?;
        const t = q.entry(kern.Thread, "ipc_link");
        sched.unsleep(t, kern.SLP_INVAL);
    }
    sched.unlock();
}

pub fn init() callconv(.c) void {
    c.event_init(@as(?*anyopaque, @ptrCast(&ipc_event)), "ipc");
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
