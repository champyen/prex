const std = @import("std");

const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});

extern fn hal_get_cpu_control() callconv(.c) ?*c.struct_cpu_control;

var ipc_event: c.struct_event = undefined;

inline fn toReg(val: anytype) c.register_t {
    const T = @TypeOf(val);
    const u: usize = switch (@typeInfo(T)) {
        .pointer => @intFromPtr(val),
        .optional => if (val) |p| @intFromPtr(p) else 0,
        else => @intCast(val),
    };
    return @intCast(@as(isize, @bitCast(u)));
}

fn get_curthread() ?*c.struct_thread {
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        return @ptrCast(hal_get_cpu_control().?.active_thread);
    } else {
        const env = struct {
            extern var curthread: c.thread_t;
        };
        return @ptrCast(env.curthread);
    }
}

fn get_curtask() ?*c.struct_task {
    if (get_curthread()) |curr| {
        return @ptrCast(curr.task);
    }
    return null;
}

fn user_area(a: anytype) bool {
    const val = switch (@typeInfo(@TypeOf(a))) {
        .pointer => @intFromPtr(a),
        .optional => if (a) |p| @intFromPtr(p) else 0,
        else => a,
    };
    if (comptime @hasDecl(c, "CONFIG_MMU")) {
        return val < c.USERLIMIT;
    } else {
        return true;
    }
}

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

inline fn msg_dequeue(head: c.queue_t) ?*c.struct_thread {
    var q = queue_first(head);
    var top: ?*c.struct_thread = @fieldParentPtr("ipc_link", @as(*c.struct_queue, @ptrCast(q)));

    while (!queue_end(head, q)) {
        const t: ?*c.struct_thread = @fieldParentPtr("ipc_link", @as(*c.struct_queue, @ptrCast(q)));
        if (t.?.priority < top.?.priority) {
            top = t;
        }
        q = queue_next(q);
    }
    c.queue_remove(&top.?.ipc_link);
    return top;
}

inline fn msg_enqueue(head: c.queue_t, t: ?*c.struct_thread) void {
    c.enqueue(head, &t.?.ipc_link);
}

pub fn msg_send(obj: c.object_t, msg: ?*anyopaque, size: usize) callconv(.c) c_int {
    if (!user_area(msg)) {
        return c.EFAULT;
    }
    if (size < @sizeOf(c.struct_msg_header)) {
        return c.EINVAL;
    }

    c.sched_lock();

    if (c.object_valid(obj) == 0) {
        c.sched_unlock();
        return c.EINVAL;
    }

    if (obj == get_curthread().?.recvobj) {
        c.sched_unlock();
        return c.EDEADLK;
    }

    const kmsg = c.kmem_map(msg, size);
    if (kmsg == null) {
        c.sched_unlock();
        return c.EFAULT;
    }
    get_curthread().?.msgaddr = kmsg;
    get_curthread().?.msgsize = size;

    const hdr: *c.struct_msg_header = @ptrCast(@alignCast(kmsg));
    hdr.task = get_curtask();

    if (!queue_empty(&obj.*.recvq)) {
        const t = msg_dequeue(&obj.*.recvq);
        c.sched_unsleep(t, 0);
    }

    get_curthread().?.sendobj = obj;
    msg_enqueue(&obj.*.sendq, get_curthread());
    const rc = c.sched_sleep(&ipc_event);
    if (rc == c.SLP_INTR) {
        c.queue_remove(&get_curthread().?.ipc_link);
    }
    get_curthread().?.sendobj = null;

    c.sched_unlock();

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

pub fn msg_receive(obj: c.object_t, msg: ?*anyopaque, size: usize) callconv(.c) c_int {
    var rc: c_int = undefined;
    var err_code: c_int = 0;

    if (!user_area(msg)) {
        return c.EFAULT;
    }

    c.sched_lock();

    if (c.object_valid(obj) == 0) {
        c.sched_unlock();
        return c.EINVAL;
    }
    if (obj.*.owner != get_curtask()) {
        c.sched_unlock();
        return c.EACCES;
    }

    if (get_curthread().?.recvobj != null) {
        c.sched_unlock();
        return c.EBUSY;
    }
    get_curthread().?.recvobj = obj;

    while (queue_empty(&obj.*.sendq)) {
        msg_enqueue(&obj.*.recvq, get_curthread());
        rc = c.sched_sleep(&ipc_event);
        if (rc != 0) {
            switch (rc) {
                c.SLP_INVAL => {
                    err_code = c.EINVAL;
                },
                c.SLP_INTR => {
                    c.queue_remove(&get_curthread().?.ipc_link);
                    err_code = c.EINTR;
                },
                else => {
                    @panic("msg_receive");
                },
            }
            get_curthread().?.recvobj = null;
            c.sched_unlock();
            return err_code;
        }
    }

    const t = msg_dequeue(&obj.*.sendq);

    const len: usize = if (size < t.?.msgsize) size else t.?.msgsize;
    if (len > 0) {
        if (c.copyout(t.?.msgaddr, msg, len) != 0) {
            msg_enqueue(&obj.*.sendq, t);
            get_curthread().?.recvobj = null;
            c.sched_unlock();
            return c.EFAULT;
        }
    }

    get_curthread().?.sender = t;
    t.?.receiver = get_curthread();

    c.sched_unlock();
    return err_code;
}

pub fn msg_reply(obj: c.object_t, msg: ?*anyopaque, size: usize) callconv(.c) c_int {
    if (!user_area(msg)) {
        return c.EFAULT;
    }

    c.sched_lock();

    if (c.object_valid(obj) == 0 or @intFromPtr(obj) != @intFromPtr(get_curthread().?.recvobj)) {
        c.sched_unlock();
        return c.EINVAL;
    }

    if (get_curthread().?.sender == null) {
        get_curthread().?.recvobj = null;
        c.sched_unlock();
        return c.EINVAL;
    }

    const t: ?*c.struct_thread = @ptrCast(get_curthread().?.sender);
    const len: usize = if (size < t.?.msgsize) size else t.?.msgsize;
    if (len > 0) {
        if (c.copyin(msg, t.?.msgaddr, len) != 0) {
            c.sched_unlock();
            return c.EFAULT;
        }
    }

    c.sched_unsleep(t, 0);
    t.?.receiver = null;

    get_curthread().?.sender = null;
    get_curthread().?.recvobj = null;

    c.sched_unlock();
    return 0;
}

pub fn msg_cancel(t: ?*c.struct_thread) callconv(.c) void {
    c.sched_lock();

    if (t.?.sendobj != null) {
        if (t.?.receiver != null) {
            const receiver: ?*c.struct_thread = @ptrCast(t.?.receiver);
            receiver.?.sender = null;
        } else {
            c.queue_remove(&t.?.ipc_link);
        }
    }
    if (t.?.recvobj != null) {
        if (t.?.sender != null) {
            const sender: ?*c.struct_thread = @ptrCast(t.?.sender);
            c.sched_unsleep(sender, c.SLP_BREAK);
            sender.?.receiver = null;
        } else {
            c.queue_remove(&t.?.ipc_link);
        }
    }
    c.sched_unlock();
}

pub fn msg_abort(obj: c.object_t) callconv(.c) void {
    c.sched_lock();

    while (!queue_empty(&obj.*.sendq)) {
        const q = c.dequeue(&obj.*.sendq);
        const t: ?*c.struct_thread = @fieldParentPtr("ipc_link", @as(*c.struct_queue, @ptrCast(q)));
        c.sched_unsleep(t, c.SLP_INVAL);
    }

    while (!queue_empty(&obj.*.recvq)) {
        const q = c.dequeue(&obj.*.recvq);
        const t: ?*c.struct_thread = @fieldParentPtr("ipc_link", @as(*c.struct_queue, @ptrCast(q)));
        c.sched_unsleep(t, c.SLP_INVAL);
    }
    c.sched_unlock();
}

pub fn msg_init() callconv(.c) void {
    c.event_init(@as(?*anyopaque, @ptrCast(&ipc_event)), "ipc");
}

comptime {
    @export(&msg_send, .{ .name = "msg_send", .linkage = .strong });
    @export(&msg_receive, .{ .name = "msg_receive", .linkage = .strong });
    @export(&msg_reply, .{ .name = "msg_reply", .linkage = .strong });
    @export(&msg_cancel, .{ .name = "msg_cancel", .linkage = .strong });
    @export(&msg_abort, .{ .name = "msg_abort", .linkage = .strong });
    @export(&msg_init, .{ .name = "msg_init", .linkage = .strong });
}
