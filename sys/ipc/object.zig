const std = @import("std");
const c = @import("c").c;

extern fn zig_memory_barrier() callconv(.c) void;

const ffi = @import("ffi");
const hal = ffi.hal;
const kern = ffi.kern;
const kutil = ffi.kutil;
const lib = ffi.lib;
const smp = ffi.smp;
const kmem = ffi.kmem;
const sched = ffi.sched;
const task = ffi.task;
const msg = ffi.msg;
const thread = ffi.thread;

var object_list: ffi.List = .{};

fn find(name: [*:0]const u8) ?*c.struct_object {
    var n = object_list.first();
    while (n != &object_list) {
        const obj = n.entry(c.struct_object, "link");
        if (lib.strncmp(&obj.name, name, c.MAXOBJNAME) == 0) {
            return obj;
        }
        n = n.nextNode();
    }
    return null;
}

fn deallocate(obj: *c.struct_object) void {
    msg.abort(obj);
    const owner = @as(*kern.Task, @ptrCast(obj.owner));
    owner.nobjects -|= 1;
    @as(*ffi.List, @ptrCast(&obj.task_link)).remove();
    @as(*ffi.List, @ptrCast(&obj.link)).remove();
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

    const cur = kutil.get_curtask().?;
    if (cur.nobjects >= c.MAXOBJECTS) {
        sched.unlock();
        return c.EAGAIN;
    }

    const null_obj: c.object_t = null;
    if (hal.copyout(@as(?*const anyopaque, @ptrCast(&null_obj)), @as(?*anyopaque, @ptrCast(objp)), @sizeOf(c.object_t)) != 0) {
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
    @as(*ffi.Queue, @ptrCast(&obj.?.sendq)).init();
    @as(*ffi.Queue, @ptrCast(&obj.?.recvq)).init();
    @as(*ffi.List, @ptrCast(&cur.objects)).insertAfter(@as(*ffi.List, @ptrCast(&obj.?.task_link)));
    cur.nobjects += 1;
    object_list.insertAfter(@as(*ffi.List, @ptrCast(&obj.?.link)));

    zig_memory_barrier();

    _ = hal.copyout(@as(?*const anyopaque, @ptrCast(&obj)), @as(?*anyopaque, @ptrCast(objp)), @sizeOf(c.object_t));

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

    if (hal.copyout(@as(?*const anyopaque, @ptrCast(&obj)), @as(?*anyopaque, @ptrCast(objp)), @sizeOf(c.object_t)) != 0) {
        return c.EFAULT;
    }
    return 0;
}

pub fn valid(obj: c.object_t) callconv(.c) c_int {
    var n = object_list.first();
    while (n != &object_list) {
        const tmp = n.entry(c.struct_object, "link");
        if (tmp == obj) {
            return 1;
        }
        n = n.nextNode();
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
    if (@intFromPtr(target_obj.owner) != @intFromPtr(kutil.get_curtask())) {
        sched.unlock();
        return c.EACCES;
    }
    deallocate(target_obj);
    sched.unlock();
    return 0;
}

pub fn cleanup(tsk: kern.TaskRef) callconv(.c) void {
    const t = @as(*kern.Task, @ptrCast(tsk));
    while (!@as(*ffi.List, @ptrCast(&t.objects)).isEmpty()) {
        const obj = @as(*ffi.List, @ptrCast(&t.objects)).first().entry(c.struct_object, "task_link");
        deallocate(obj);
    }
}

pub fn init() callconv(.c) void {
    object_list.init();
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
