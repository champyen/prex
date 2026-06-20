const std = @import("std");
const c = @import("c").c;

extern fn zig_memory_barrier() callconv(.c) void;

const ffi = @import("ffi");
const lib = ffi.lib;
const smp = ffi.smp;
const kmem = ffi.kmem;
const sched = ffi.sched;
const task = ffi.task;
const msg = ffi.msg;
const thread = ffi.thread;

var object_list: c.struct_list = undefined;

fn get_curthread() ?*c.struct_thread {
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        return @ptrCast(smp.get_cpu_control().*.active_thread);
    } else {
        return @ptrCast(thread.curthread);
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

fn find(name: [*:0]const u8) ?*c.struct_object {
    var n: ?*c.struct_list = list_first(&object_list);
    while (n != null and n.? != @as(?*c.struct_list, @ptrCast(&object_list))) {
        const obj: *c.struct_object = @fieldParentPtr("link", n.?);
        if (lib.strncmp(&obj.name, name, c.MAXOBJNAME) == 0) {
            return obj;
        }
        n = list_next(n.?);
    }
    return null;
}

fn deallocate(obj: *c.struct_object) void {
    msg.abort(obj);
    const owner = @as(*c.struct_task, @ptrCast(obj.owner));
    owner.nobjects -|= 1;
    list_remove(&obj.task_link);
    list_remove(&obj.link);
    kmem.free(obj);
}

pub fn create(name: ?[*:0]const u8, objp: ?*c.object_t) callconv(.c) c_int {
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

        if (name_ptr[0] == '!' and task.capable(c.CAP_PROTSERV) == 0) {
            return c.EPERM;
        }
    }

    sched.lock();

    const cur = get_curtask().?;
    if (cur.nobjects >= c.MAXOBJECTS) {
        sched.unlock();
        return c.EAGAIN;
    }

    const null_obj: c.object_t = null;
    if (ffi.vm.copyout(@as(?*const anyopaque, @ptrCast(&null_obj)), @as(?*anyopaque, @ptrCast(objp)), @sizeOf(c.object_t)) != 0) {
        sched.unlock();
        return c.EFAULT;
    }

    if (find(&str) != null) {
        sched.unlock();
        return c.EEXIST;
    }

    const mem = kmem.alloc(@sizeOf(c.struct_object));
    const obj: ?*c.struct_object = @ptrCast(@alignCast(mem));
    if (obj == null) {
        sched.unlock();
        return c.ENOMEM;
    }

    if (name != null) {
        _ = lib.strlcpy(&obj.?.name, &str, c.MAXOBJNAME);
    }

    obj.?.owner = cur;
    queue_init(&obj.?.sendq);
    queue_init(&obj.?.recvq);
    list_insert(&cur.objects, &obj.?.task_link);
    cur.nobjects += 1;
    list_insert(&object_list, &obj.?.link);

    zig_memory_barrier();

    _ = ffi.vm.copyout(@as(?*const anyopaque, @ptrCast(&obj)), @as(?*anyopaque, @ptrCast(objp)), @sizeOf(c.object_t));

    sched.unlock();
    return 0;
}

pub fn lookup(name: [*:0]const u8, objp: ?*c.object_t) callconv(.c) c_int {
    var str: [c.MAXOBJNAME:0]u8 = undefined;

    var i: usize = 0;
    while (i < c.MAXOBJNAME - 1 and name[i] != 0) : (i += 1) {
        str[i] = name[i];
    }
    str[i] = 0;

    sched.lock();
    const obj = find(&str);
    sched.unlock();

    if (obj == null) {
        return c.ENOENT;
    }

    if (ffi.vm.copyout(@as(?*const anyopaque, @ptrCast(&obj)), @as(?*anyopaque, @ptrCast(objp)), @sizeOf(c.object_t)) != 0) {
        return c.EFAULT;
    }
    return 0;
}

pub fn valid(obj: c.object_t) callconv(.c) c_int {
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

pub fn destroy(obj: c.object_t) callconv(.c) c_int {
    sched.lock();
    if (valid(obj) == 0) {
        sched.unlock();
        return c.EINVAL;
    }
    const target_obj = @as(*c.struct_object, @ptrCast(obj));
    if (@intFromPtr(target_obj.owner) != @intFromPtr(get_curtask())) {
        sched.unlock();
        return c.EACCES;
    }
    deallocate(target_obj);
    sched.unlock();
    return 0;
}

pub fn cleanup(tsk: c.task_t) callconv(.c) void {
    const t = @as(*c.struct_task, @ptrCast(tsk));
    while (!list_empty(&t.objects)) {
        const obj: *c.struct_object = @fieldParentPtr("task_link", list_first(&t.objects).?);
        deallocate(obj);
    }
}

pub fn init() callconv(.c) void {
    list_init(&object_list);
}

comptime {
    if (@import("root") == @This()) {
        @export(&create, .{ .name = "object_create", .linkage = .strong });
        @export(&lookup, .{ .name = "object_lookup", .linkage = .strong });
        @export(&valid, .{ .name = "object_valid", .linkage = .strong });
        @export(&destroy, .{ .name = "object_destroy", .linkage = .strong });
        @export(&cleanup, .{ .name = "object_cleanup", .linkage = .strong });
        @export(&init, .{ .name = "object_init", .linkage = .strong });
    }
}
