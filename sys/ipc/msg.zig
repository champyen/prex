const std = @import("std");

const c = @import("c").c;
const ffi = @import("ffi");
const kutil = ffi.kutil;
const smp = ffi.smp;
const kmem = ffi.kmem;
const sched = ffi.sched;
const object = ffi.object;
const thread = ffi.thread;

var ipc_event: c.struct_event = undefined;





inline fn queue_empty(head: c.queue_t) bool {
    return head.?.*.next == head;
}

inline fn queue_first(head: c.queue_t) c.queue_t {
    return head.?.*.next;
}

inline fn queue_next(q: c.queue_t) c.queue_t {
    return q.?.*.next;
}

inline fn queue_end(head: c.queue_t, q: c.queue_t) bool {
    return q == head;
}

inline fn dequeue(head: c.queue_t) ?*c.struct_thread {
    var q = queue_first(head);
    var top: ?*c.struct_thread = @fieldParentPtr("ipc_link", @as(*c.struct_queue, @ptrCast(q)));

    while (!queue_end(head, q)) {
        const t: ?*c.struct_thread = @fieldParentPtr("ipc_link", @as(*c.struct_queue, @ptrCast(q)));
        if (t.?.priority < top.?.priority) {
            top = t;
        }
        q = queue_next(q);
    }
    ffi.queue.remove(&top.?.ipc_link);
    return top;
}

inline fn enqueue(head: c.queue_t, t: ?*c.struct_thread) void {
    ffi.queue.enqueue(head, &t.?.ipc_link);
}

pub fn send(obj: c.object_t, msg: ?*anyopaque, size: usize) callconv(.c) c_int {
    if (!kutil.user_area(msg)) {
        return c.EFAULT;
    }
    if (size < @sizeOf(c.struct_msg_header)) {
        return c.EINVAL;
    }

    sched.lock();

    if (object.valid(obj) == 0) {
        sched.unlock();
        return c.EINVAL;
    }

    if (obj == kutil.get_curthread().?.recvobj) {
        sched.unlock();
        return c.EDEADLK;
    }

    const kmsg = kmem.map(msg, size);
    if (kmsg == null) {
        sched.unlock();
        return c.EFAULT;
    }
    kutil.get_curthread().?.msgaddr = kmsg;
    kutil.get_curthread().?.msgsize = size;

    const hdr: *c.struct_msg_header = @ptrCast(@alignCast(kmsg));
    hdr.task = kutil.get_curtask();

    if (!queue_empty(&obj.*.recvq)) {
        const t = dequeue(&obj.*.recvq);
        sched.unsleep(t, 0);
    }

    kutil.get_curthread().?.sendobj = obj;
    enqueue(&obj.*.sendq, kutil.get_curthread());
    const rc = sched.tsleep(&ipc_event, 0);
    if (rc == c.SLP_INTR) {
        ffi.queue.remove(&kutil.get_curthread().?.ipc_link);
    }
    kutil.get_curthread().?.sendobj = null;

    sched.unlock();

    switch (rc) {
        c.SLP_BREAK => {
            return c.EAGAIN;
        },
        c.SLP_INVAL => {
            return c.EINVAL;
        },
        c.SLP_INTR => {
            return c.EINTR;
        },
        else => {},
    }
    return 0;
}

pub fn receive(obj: c.object_t, msg: ?*anyopaque, size: usize) callconv(.c) c_int {
    var rc: c_int = undefined;
    var err_code: c_int = 0;

    if (!kutil.user_area(msg)) {
        return c.EFAULT;
    }

    sched.lock();

    if (object.valid(obj) == 0) {
        sched.unlock();
        return c.EINVAL;
    }
    if (obj.*.owner != kutil.get_curtask()) {
        sched.unlock();
        return c.EACCES;
    }

    if (kutil.get_curthread().?.recvobj != null) {
        sched.unlock();
        return c.EBUSY;
    }
    kutil.get_curthread().?.recvobj = obj;

    while (queue_empty(&obj.*.sendq)) {
        enqueue(&obj.*.recvq, kutil.get_curthread());
        rc = sched.tsleep(&ipc_event, 0);
        if (rc != 0) {
            switch (rc) {
                c.SLP_INVAL => {
                    err_code = c.EINVAL;
                },
                c.SLP_INTR => {
                    ffi.queue.remove(&kutil.get_curthread().?.ipc_link);
                    err_code = c.EINTR;
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

    const t = dequeue(&obj.*.sendq);

    const len: usize = if (size < t.?.msgsize) size else t.?.msgsize;
    if (len > 0) {
        if (ffi.vm.copyout(t.?.msgaddr, msg, len) != 0) {
            enqueue(&obj.*.sendq, t);
            kutil.get_curthread().?.recvobj = null;
            sched.unlock();
            return c.EFAULT;
        }
    }

    kutil.get_curthread().?.sender = t;
    t.?.receiver = kutil.get_curthread();

    sched.unlock();
    return err_code;
}

pub fn reply(obj: c.object_t, msg: ?*anyopaque, size: usize) callconv(.c) c_int {
    if (!kutil.user_area(msg)) {
        return c.EFAULT;
    }

    sched.lock();

    if (object.valid(obj) == 0 or @intFromPtr(obj) != @intFromPtr(kutil.get_curthread().?.recvobj)) {
        sched.unlock();
        return c.EINVAL;
    }

    if (kutil.get_curthread().?.sender == null) {
        kutil.get_curthread().?.recvobj = null;
        sched.unlock();
        return c.EINVAL;
    }

    const t: ?*c.struct_thread = @ptrCast(kutil.get_curthread().?.sender);
    const len: usize = if (size < t.?.msgsize) size else t.?.msgsize;
    if (len > 0) {
        if (ffi.vm.copyin(msg, t.?.msgaddr, len) != 0) {
            sched.unlock();
            return c.EFAULT;
        }
    }

    sched.unsleep(t, 0);
    t.?.receiver = null;

    kutil.get_curthread().?.sender = null;
    kutil.get_curthread().?.recvobj = null;

    sched.unlock();
    return 0;
}

pub fn cancel(t: ?*c.struct_thread) callconv(.c) void {
    sched.lock();

    if (t.?.sendobj != null) {
        if (t.?.receiver != null) {
            const receiver: ?*c.struct_thread = @ptrCast(t.?.receiver);
            receiver.?.sender = null;
        } else {
            ffi.queue.remove(&t.?.ipc_link);
        }
    }
    if (t.?.recvobj != null) {
        if (t.?.sender != null) {
            const sender: ?*c.struct_thread = @ptrCast(t.?.sender);
            sched.unsleep(sender, c.SLP_BREAK);
            sender.?.receiver = null;
        } else {
            ffi.queue.remove(&t.?.ipc_link);
        }
    }
    sched.unlock();
}

pub fn abort(obj: c.object_t) callconv(.c) void {
    sched.lock();

    while (!queue_empty(&obj.*.sendq)) {
        const q = ffi.queue.dequeue(&obj.*.sendq);
        const t: ?*c.struct_thread = @fieldParentPtr("ipc_link", @as(*c.struct_queue, @ptrCast(q)));
        sched.unsleep(t, c.SLP_INVAL);
    }

    while (!queue_empty(&obj.*.recvq)) {
        const q = ffi.queue.dequeue(&obj.*.recvq);
        const t: ?*c.struct_thread = @fieldParentPtr("ipc_link", @as(*c.struct_queue, @ptrCast(q)));
        sched.unsleep(t, c.SLP_INVAL);
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
