const std = @import("std");

const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});

extern fn zig_memory_barrier() callconv(.c) void;
extern fn hal_get_cpu_control() callconv(.c) ?*c.struct_cpu_control;

var object_list: c.struct_list = undefined;

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

inline fn list_first(head: *c.struct_list) ?*c.struct_list {
    return @ptrCast(head.*.next);
}

inline fn list_next(node: *c.struct_list) ?*c.struct_list {
    return @ptrCast(node.*.next);
}

inline fn list_empty(head: *c.struct_list) bool {
    return head.*.next == @as(?*c.struct_list, @ptrCast(head));
}

inline fn list_insert(prev: *c.struct_list, node: *c.struct_list) void {
    node.prev = @ptrCast(prev);
    node.next = prev.next;
    prev.next.?.*.prev = @ptrCast(node);
    prev.next = @ptrCast(node);
}

inline fn queue_init(head: c.queue_t) void {
    head.?.*.next = head;
    head.?.*.prev = head;
}

inline fn list_init(head: *c.struct_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

inline fn list_remove(node: *c.struct_list) void {
    node.prev.?.*.next = node.next;
    node.next.?.*.prev = node.prev;
}

fn object_find(name: [*:0]const u8) ?*c.struct_object {
    var n: ?*c.struct_list = list_first(&object_list);
    while (n != null and n.? != @as(?*c.struct_list, @ptrCast(&object_list))) {
        const obj: *c.struct_object = @fieldParentPtr("link", n.?);
        if (c.strncmp(&obj.name, name, c.MAXOBJNAME) == 0) {
            return obj;
        }
        n = list_next(n.?);
    }
    return null;
}

fn object_deallocate(obj: *c.struct_object) void {
    _ = c.msg_abort(obj);
    const owner = @as(*c.struct_task, @ptrCast(obj.owner));
    owner.nobjects -|= 1;
    list_remove(&obj.task_link);
    list_remove(&obj.link);
    c.kmem_free(obj);
}

pub fn object_create(name: ?[*:0]const u8, objp: ?*c.object_t) callconv(.c) c_int {
    var str: [c.MAXOBJNAME:0]u8 = undefined;

    if (name == null) {
        str[0] = 0;
    } else {
        const name_ptr = name.?;
        var i: usize = 0;
        while (i < c.MAXOBJNAME - 1 and name_ptr[i] != 0) : (i += 1) {
            str[i] = name_ptr[i];
        }
        str[i] = 0;

        if (name_ptr[0] == '!' and c.task_capable(c.CAP_PROTSERV) == 0) {
            return c.EPERM;
        }
    }

    c.sched_lock();

    const cur = get_curtask().?;
    if (cur.nobjects >= c.MAXOBJECTS) {
        c.sched_unlock();
        return c.EAGAIN;
    }

    const null_obj: c.object_t = null;
    if (c.copyout(@as(?*const anyopaque, @ptrCast(&null_obj)), @as(?*anyopaque, @ptrCast(objp)), @sizeOf(c.object_t)) != 0) {
        c.sched_unlock();
        return c.EFAULT;
    }

    if (object_find(&str) != null) {
        c.sched_unlock();
        return c.EEXIST;
    }

    const mem = c.kmem_alloc(@sizeOf(c.struct_object));
    const obj: ?*c.struct_object = @ptrCast(@alignCast(mem));
    if (obj == null) {
        c.sched_unlock();
        return c.ENOMEM;
    }

    if (name != null) {
        _ = c.strlcpy(&obj.?.name, &str, c.MAXOBJNAME);
    }

    obj.?.owner = cur;
    queue_init(&obj.?.sendq);
    queue_init(&obj.?.recvq);
    list_insert(&cur.objects, &obj.?.task_link);
    cur.nobjects += 1;
    list_insert(&object_list, &obj.?.link);

    zig_memory_barrier();

    _ = c.copyout(@as(?*const anyopaque, @ptrCast(&obj)), @as(?*anyopaque, @ptrCast(objp)), @sizeOf(c.object_t));

    c.sched_unlock();
    return 0;
}

pub fn object_lookup(name: [*:0]const u8, objp: ?*c.object_t) callconv(.c) c_int {
    var str: [c.MAXOBJNAME:0]u8 = undefined;

    var i: usize = 0;
    while (i < c.MAXOBJNAME - 1 and name[i] != 0) : (i += 1) {
        str[i] = name[i];
    }
    str[i] = 0;

    c.sched_lock();
    const obj = object_find(&str);
    c.sched_unlock();

    if (obj == null) {
        return c.ENOENT;
    }

    if (c.copyout(@as(?*const anyopaque, @ptrCast(&obj)), @as(?*anyopaque, @ptrCast(objp)), @sizeOf(c.object_t)) != 0) {
        return c.EFAULT;
    }
    return 0;
}

pub fn object_valid(obj: c.object_t) callconv(.c) c_int {
    var n: ?*c.struct_list = list_first(&object_list);
    while (n != null and n.? != @as(?*c.struct_list, @ptrCast(&object_list))) {
        const tmp: *c.struct_object = @fieldParentPtr("link", n.?);
        if (tmp == obj) {
            return 1;
        }
        n = list_next(n.?);
    }
    return 0;
}

pub fn object_destroy(obj: c.object_t) callconv(.c) c_int {
    c.sched_lock();
    if (object_valid(obj) == 0) {
        c.sched_unlock();
        return c.EINVAL;
    }
    const target_obj = @as(*c.struct_object, @ptrCast(obj));
    if (@intFromPtr(target_obj.owner) != @intFromPtr(get_curtask())) {
        c.sched_unlock();
        return c.EACCES;
    }
    object_deallocate(target_obj);
    c.sched_unlock();
    return 0;
}

pub fn object_cleanup(task: c.task_t) callconv(.c) void {
    const t = @as(*c.struct_task, @ptrCast(task));
    while (!list_empty(&t.objects)) {
        const obj: *c.struct_object = @fieldParentPtr("task_link", list_first(&t.objects).?);
        object_deallocate(obj);
    }
}

pub fn object_init() callconv(.c) void {
    list_init(&object_list);
}

comptime {
    @export(&object_create, .{ .name = "object_create", .linkage = .strong });
    @export(&object_lookup, .{ .name = "object_lookup", .linkage = .strong });
    @export(&object_valid, .{ .name = "object_valid", .linkage = .strong });
    @export(&object_destroy, .{ .name = "object_destroy", .linkage = .strong });
    @export(&object_cleanup, .{ .name = "object_cleanup", .linkage = .strong });
    @export(&object_init, .{ .name = "object_init", .linkage = .strong });
}
