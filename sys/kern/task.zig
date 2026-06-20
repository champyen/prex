const std = @import("std");
const builtin = @import("builtin");

const c = @import("c").c;
const ffi = @import("ffi");
const kutil = ffi.kutil;
const hal = ffi.hal;
const lib = ffi.lib;
const sched = ffi.sched;
const kmem = ffi.kmem;
const vm = ffi.vm;
const thread = ffi.thread;
const smp = ffi.smp;

var task_list: c.struct_list = undefined;
var ntasks: c_int = 0;

var kernel_task: c.struct_task = std.mem.zeroes(c.struct_task);



inline fn list_init_fn(head: *c.struct_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

inline fn list_insert_fn(prev: *c.struct_list, node: *c.struct_list) void {
    node.prev = @ptrCast(prev);
    node.next = prev.next;
    prev.next.?.*.prev = @ptrCast(node);
    prev.next = @ptrCast(node);
}

inline fn list_remove_fn(node: *c.struct_list) void {
    node.prev.?.*.next = node.next;
    node.next.?.*.prev = node.prev;
}

inline fn list_empty(head: *c.struct_list) bool {
    return head.next == @as(?*c.struct_list, @ptrCast(head));
}

inline fn list_first(head: *c.struct_list) *c.struct_list {
    return @ptrCast(head.next.?);
}

inline fn list_next_node(node: *c.struct_list) *c.struct_list {
    return @ptrCast(node.next.?);
}

fn valid(task: c.task_t) callconv(.c) c_int {
    var n = list_first(&task_list);
    while (n != @as(*c.struct_list, @ptrCast(&task_list))) : (n = list_next_node(n)) {
        const tmp = @as(*c.struct_task, @fieldParentPtr("link", n));
        if (tmp == task) {
            return 1;
        }
    }
    return 0;
}

fn access(task: c.task_t) callconv(.c) c_int {
    if ((task.?.*.flags & c.TF_SYSTEM) != 0) {
        return 0;
    } else {
        if (task == kutil.cur_task() or task.?.*.parent == kutil.cur_task() or task == kutil.cur_task().*.parent or capable(c.CAP_TASKCTRL) != 0) {
            return 1;
        }
    }
    return 0;
}

fn capable(cap: c.cap_t) callconv(.c) c_int {
    var capable_val: c_int = 1;

    if ((kutil.cur_task().*.capability & cap) == 0) {
        if ((kutil.cur_task().*.flags & c.TF_AUDIT) != 0) {
            lib.panic("audit failed");
        }
        capable_val = 0;
    }
    return capable_val;
}

pub fn create(parent: c.task_t, vm_option: c_int, childp: ?*c.task_t) callconv(.c) c_int {
    var task: c.task_t = null;
    var map: c.vm_map_t = null;

    if (parent == null) return c.EINVAL;

    switch (vm_option) {
        c.VM_NEW, c.VM_SHARE => {},
        else => {
            if (vm_option == c.VM_COPY) {
            } else {
                return c.EINVAL;
            }
        },
    }

    if (ntasks >= c.MAXTASKS) return c.EAGAIN;

    sched.lock();
    if (valid(parent) == 0) {
        sched.unlock();
        return c.ESRCH;
    }

    if ((kutil.cur_task().*.flags & c.TF_SYSTEM) == 0) {
        if (access(parent) == 0) {
            sched.unlock();
            return c.EPERM;
        }

        task = null;
        if (ffi.vm.copyout(@as(?*const anyopaque, @ptrCast(&task)), @as(?*anyopaque, @ptrCast(childp)), @sizeOf(c.task_t)) != 0) {
            sched.unlock();
            return c.EFAULT;
        }
    }

    const mem = kmem.alloc(@sizeOf(c.struct_task));
    if (mem == null) {
        sched.unlock();
        return c.ENOMEM;
    }
    task = @ptrCast(@alignCast(mem));
    @memset(@as([*]u8, @ptrCast(task))[0..@sizeOf(c.struct_task)], 0);

    switch (vm_option) {
        c.VM_NEW => {
            map = vm.create();
        },
        c.VM_SHARE => {
            _ = vm.reference(parent.?.*.map);
            map = parent.?.*.map;
        },
        c.VM_COPY => {
            map = vm.dup(parent.?.*.map);
        },
        else => {},
    }

    if (map == null) {
        kmem.free(task);
        sched.unlock();
        return c.ENOMEM;
    }

    task.?.*.map = map;
    task.?.*.handler = parent.?.*.handler;
    task.?.*.capability = parent.?.*.capability;
    task.?.*.parent = parent;
    task.?.*.flags = c.TF_DEFAULT;
    _ = lib.strlcpy(@ptrCast(&task.?.*.name), "*noname", c.MAXTASKNAME);
    list_init_fn(&task.?.*.threads);
    list_init_fn(&task.?.*.objects);
    list_init_fn(&task.?.*.mutexes);
    list_init_fn(&task.?.*.conds);
    list_init_fn(&task.?.*.sems);
    list_insert_fn(&task_list, &task.?.*.link);
    ntasks += 1;

    if ((kutil.cur_task().*.flags & c.TF_SYSTEM) != 0) {
        childp.?.* = task;
    } else {
        _ = ffi.vm.copyout(@as(?*const anyopaque, @ptrCast(&task)), @as(?*anyopaque, @ptrCast(childp)), @sizeOf(c.task_t));
    }

    sched.unlock();
    return 0;
}

pub fn terminate(task: c.task_t) callconv(.c) c_int {
    sched.lock();
    if (valid(task) == 0) {
        sched.unlock();
        return c.ESRCH;
    }
    if (access(task) == 0) {
        sched.unlock();
        return c.EPERM;
    }

    list_remove_fn(&task.?.*.link);
    @as(*usize, @ptrCast(&task.?.*.handler)).* = @as(usize, @bitCast(@as(isize, -1)));

    c.timer_stop(&task.?.*.alarm);
    ffi.object.cleanup(task);
    ffi.mutex.cleanup(task);
    ffi.cond.cleanup(task);
    ffi.sem.cleanup(task);

    {
        var n = list_first(&task.?.*.threads);
        while (n != @as(*c.struct_list, @ptrCast(&task.?.*.threads))) {
            const next_node = list_next_node(n);
            const t = @as(*c.struct_thread, @fieldParentPtr("task_link", n));
            if (t != kutil.cur_thread()) {
                thread.destroy(t);
            }
            n = next_node;
        }
    }
    if (task == kutil.cur_task()) {
        thread.destroy(kutil.cur_thread());
    }

    vm.terminate(task.?.*.map);
    task.?.*.map = null;
    kmem.free(task);
    ntasks -= 1;
    sched.unlock();
    return 0;
}

pub fn self() callconv(.c) c.task_t {
    return kutil.cur_thread().*.task;
}

pub fn @"suspend"(task: c.task_t) callconv(.c) c_int {
    sched.lock();
    if (valid(task) == 0) {
        sched.unlock();
        return c.ESRCH;
    }
    if (access(task) == 0) {
        sched.unlock();
        return c.EPERM;
    }

    task.?.*.suscnt += 1;
    if (task.?.*.suscnt == 1) {
        var n = list_first(&task.?.*.threads);
        while (n != @as(*c.struct_list, @ptrCast(&task.?.*.threads))) : (n = list_next_node(n)) {
            const t = @as(*c.struct_thread, @fieldParentPtr("task_link", n));
            _ = thread.@"suspend"(t);
        }
    }
    sched.unlock();
    return 0;
}

pub fn @"resume"(task: c.task_t) callconv(.c) c_int {
    if (task == kutil.cur_task()) return c.EINVAL;

    sched.lock();
    if (valid(task) == 0) {
        sched.unlock();
        return c.ESRCH;
    }
    if (access(task) == 0) {
        sched.unlock();
        return c.EPERM;
    }
    if (task.?.*.suscnt == 0) {
        sched.unlock();
        return c.EINVAL;
    }

    task.?.*.suscnt -= 1;
    if (task.?.*.suscnt == 0) {
        var n = list_first(&task.?.*.threads);
        while (n != @as(*c.struct_list, @ptrCast(&task.?.*.threads))) : (n = list_next_node(n)) {
            const t = @as(*c.struct_thread, @fieldParentPtr("task_link", n));
            _ = thread.@"resume"(t);
        }
    }
    sched.unlock();
    return 0;
}

pub fn setname(task: c.task_t, name: [*:0]const u8) callconv(.c) c_int {
    var str: [c.MAXTASKNAME]u8 = undefined;

    sched.lock();
    if (valid(task) == 0) {
        sched.unlock();
        return c.ESRCH;
    }
    if (access(task) == 0) {
        sched.unlock();
        return c.EPERM;
    }

    if ((kutil.cur_task().*.flags & c.TF_SYSTEM) != 0) {
        _ = lib.strlcpy(@ptrCast(&task.?.*.name), @ptrCast(name), c.MAXTASKNAME);
    } else {
        const err = ffi.vm.copyinstr(@as(?*const anyopaque, @ptrCast(name)), @as(?*anyopaque, @ptrCast(&str)), c.MAXTASKNAME);
        if (err != 0) {
            sched.unlock();
            return err;
        }
        _ = lib.strlcpy(@ptrCast(&task.?.*.name), @ptrCast(&str), c.MAXTASKNAME);
    }
    sched.unlock();
    return 0;
}

pub fn setcap(task: c.task_t, cap: c.cap_t) callconv(.c) c_int {
    if (capable(c.CAP_SETPCAP) == 0) return c.EPERM;

    sched.lock();
    if (valid(task) == 0) {
        sched.unlock();
        return c.ESRCH;
    }
    if (access(task) == 0) {
        sched.unlock();
        return c.EPERM;
    }
    task.?.*.capability = cap;
    sched.unlock();
    return 0;
}

pub fn chkcap(task: c.task_t, cap: c.cap_t) callconv(.c) c_int {
    var err: c_int = 0;

    sched.lock();
    if (valid(task) == 0) {
        sched.unlock();
        return c.ESRCH;
    }
    if ((task.?.*.capability & cap) == 0) {
        if ((kutil.cur_task().*.flags & c.TF_AUDIT) != 0) {
            lib.panic("audit failed");
        }
        err = c.EPERM;
    }
    sched.unlock();
    return err;
}

pub fn info(task_info_ptr: ?*c.struct_taskinfo) callconv(.c) c_int {
    const target: c.u_long = task_info_ptr.?.*.cookie;
    var i: c.u_long = 0;

    sched.lock();
    var n = list_first(&task_list);
    while (true) : (n = list_next_node(n)) {
        if (i == target) {
            const task = @as(*c.struct_task, @fieldParentPtr("link", n));
            task_info_ptr.?.*.cookie = i + 1;
            task_info_ptr.?.*.id = task;
            task_info_ptr.?.*.flags = task.*.flags;
            task_info_ptr.?.*.suscnt = task.*.suscnt;
            task_info_ptr.?.*.capability = task.*.capability;
            task_info_ptr.?.*.vmsize = task.*.map.?.*.total;
            task_info_ptr.?.*.nthreads = task.*.nthreads;
            task_info_ptr.?.*.active = if (task == kutil.cur_task()) @as(c_int, 1) else @as(c_int, 0);
            _ = lib.strlcpy(@ptrCast(&task_info_ptr.?.*.taskname), @ptrCast(&task.*.name), c.MAXTASKNAME);
            sched.unlock();
            return 0;
        }
        i += 1;
        if (n == @as(*c.struct_list, @ptrCast(&task_list))) break;
    }
    sched.unlock();
    return c.ESRCH;
}

pub fn bootstrap() callconv(.c) void {
    var bi: ?*c.struct_bootinfo = null;
    hal.machine_bootinfo(&bi);

    var i: c_int = 0;
    while (i < bi.?.*.nr_tasks) : (i += 1) {
        const tasks_ptr: [*]c.struct_module = @ptrCast(&bi.?.*.tasks);
        const mod: *c.struct_module = &tasks_ptr[@intCast(i)];
        var task: c.task_t = null;
        var t: c.thread_t = null;
        var stack: ?*anyopaque = null;

        var err = create(&kernel_task, c.VM_NEW, &task);
        if (err != 0) {
            lib.panic("unable to load boot task");
        }
        err = vm.load(task.?.*.map, mod, &stack);
        if (err != 0) {
            lib.panic("unable to load boot task");
        }

        _ = setname(task, @ptrCast(&mod.*.name));

        task.?.*.capability = c.CAPSET_BOOT;
        if (lib.strncmp(@ptrCast(&task.?.*.name), "exec", c.MAXTASKNAME) == 0) {
            task.?.*.capability |= c.CAP_SETPCAP;
        }

        err = thread.create(task, &t);
        if (err != 0) {
            lib.panic("unable to load boot task");
        }

        const sp: ?*anyopaque = @ptrFromInt(@as(usize, @intFromPtr(stack)) + c.DFLSTKSZ - @sizeOf(c_int) * 3);
        const entry_fn: *const fn () callconv(.c) void = @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(usize, mod.*.entry)))));
        const gp: ?*anyopaque = if (@hasField(c.struct_module, "got_base")) (if (mod.*.got_base != 0) @ptrFromInt(mod.*.got_base) else null) else null;
        err = thread.setup(t, entry_fn, sp, gp);
        if (err != 0) {
            lib.panic("unable to load boot task");
        }
        t.?.*.priority = c.PRI_REALTIME;
        t.?.*.basepri = c.PRI_REALTIME;
        _ = thread.@"resume"(t);
    }
}

pub fn init() callconv(.c) void {
    list_init_fn(&task_list);

    _ = lib.strlcpy(@ptrCast(&kernel_task.name), "kernel", c.MAXTASKNAME);
    kernel_task.flags = c.TF_SYSTEM;
    kernel_task.nthreads = 0;
    list_init_fn(&kernel_task.threads);
    list_init_fn(&kernel_task.objects);
    list_init_fn(&kernel_task.mutexes);
    list_init_fn(&kernel_task.conds);
    list_init_fn(&kernel_task.sems);

    list_insert_fn(&task_list, &kernel_task.link);
    ntasks = 1;
}

comptime {
    if (@import("root") == @This()) {
        @export(&kernel_task, .{ .name = "kernel_task", .linkage = .strong });
        @export(&create, .{ .name = "task_create", .linkage = .strong });
        @export(&terminate, .{ .name = "task_terminate", .linkage = .strong });
        @export(&self, .{ .name = "task_self", .linkage = .strong });
        @export(&@"suspend", .{ .name = "task_suspend", .linkage = .strong });
        @export(&@"resume", .{ .name = "task_resume", .linkage = .strong });
        @export(&setname, .{ .name = "task_setname", .linkage = .strong });
        @export(&setcap, .{ .name = "task_setcap", .linkage = .strong });
        @export(&chkcap, .{ .name = "task_chkcap", .linkage = .strong });
        @export(&capable, .{ .name = "task_capable", .linkage = .strong });
        @export(&valid, .{ .name = "task_valid", .linkage = .strong });
        @export(&access, .{ .name = "task_access", .linkage = .strong });
        @export(&info, .{ .name = "task_info", .linkage = .strong });
        @export(&bootstrap, .{ .name = "task_bootstrap", .linkage = .strong });
        @export(&init, .{ .name = "task_init", .linkage = .strong });
    }
}
