const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});

extern fn hal_get_cpu_control() callconv(.c) ?*c.struct_cpu_control;

var task_list: c.struct_list = undefined;
var ntasks: c_int = 0;

var kernel_task: c.struct_task = std.mem.zeroes(c.struct_task);

inline fn get_curthread() *c.struct_thread {
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        return @ptrCast(hal_get_cpu_control().?.*.active_thread.?);
    } else {
        const env = struct {
            extern var curthread: c.thread_t;
        };
        return @ptrCast(env.curthread.?);
    }
}

inline fn get_curtask() *c.struct_task {
    return @ptrCast(get_curthread().*.task.?);
}

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

fn task_valid(task: c.task_t) callconv(.c) c_int {
    var n = list_first(&task_list);
    while (n != @as(*c.struct_list, @ptrCast(&task_list))) : (n = list_next_node(n)) {
        const tmp = @as(*c.struct_task, @fieldParentPtr("link", n));
        if (tmp == task) {
            return 1;
        }
    }
    return 0;
}

fn task_access(task: c.task_t) callconv(.c) c_int {
    if ((task.?.*.flags & c.TF_SYSTEM) != 0) {
        return 0;
    } else {
        if (task == get_curtask() or task.?.*.parent == get_curtask() or task == get_curtask().*.parent or task_capable(c.CAP_TASKCTRL) != 0) {
            return 1;
        }
    }
    return 0;
}

fn task_capable(cap: c.cap_t) callconv(.c) c_int {
    var capable: c_int = 1;

    if ((get_curtask().*.capability & cap) == 0) {
        if ((get_curtask().*.flags & c.TF_AUDIT) != 0) {
            c.panic("audit failed");
        }
        capable = 0;
    }
    return capable;
}

pub fn task_create(parent: c.task_t, vm_option: c_int, childp: ?*c.task_t) callconv(.c) c_int {
    var task: c.task_t = null;
    var map: c.vm_map_t = null;

    if (parent == null) return c.EINVAL;

    switch (vm_option) {
        c.VM_NEW, c.VM_SHARE => {},
        else => {
            if (vm_option == c.VM_COPY) {
                // VM_COPY is valid with MMU, handled below
            } else {
                return c.EINVAL;
            }
        },
    }

    if (ntasks >= c.MAXTASKS) return c.EAGAIN;

    c.sched_lock();
    if (task_valid(parent) == 0) {
        c.sched_unlock();
        return c.ESRCH;
    }

    if ((get_curtask().*.flags & c.TF_SYSTEM) == 0) {
        if (task_access(parent) == 0) {
            c.sched_unlock();
            return c.EPERM;
        }

        task = null;
        if (c.copyout(@as(?*const anyopaque, @ptrCast(&task)), @as(?*anyopaque, @ptrCast(childp)), @sizeOf(c.task_t)) != 0) {
            c.sched_unlock();
            return c.EFAULT;
        }
    }

    const mem = c.kmem_alloc(@sizeOf(c.struct_task));
    if (mem == null) {
        c.sched_unlock();
        return c.ENOMEM;
    }
    task = @ptrCast(@alignCast(mem));
    @memset(@as([*]u8, @ptrCast(task))[0..@sizeOf(c.struct_task)], 0);

    switch (vm_option) {
        c.VM_NEW => {
            map = c.vm_create();
        },
        c.VM_SHARE => {
            _ = c.vm_reference(parent.?.*.map);
            map = parent.?.*.map;
        },
        c.VM_COPY => {
            map = c.vm_dup(parent.?.*.map);
        },
        else => {},
    }

    if (map == null) {
        c.kmem_free(task);
        c.sched_unlock();
        return c.ENOMEM;
    }

    task.?.*.map = map;
    task.?.*.handler = parent.?.*.handler;
    task.?.*.capability = parent.?.*.capability;
    task.?.*.parent = parent;
    task.?.*.flags = c.TF_DEFAULT;
    _ = c.strlcpy(@ptrCast(&task.?.*.name), "*noname", c.MAXTASKNAME);
    list_init_fn(&task.?.*.threads);
    list_init_fn(&task.?.*.objects);
    list_init_fn(&task.?.*.mutexes);
    list_init_fn(&task.?.*.conds);
    list_init_fn(&task.?.*.sems);
    list_insert_fn(&task_list, &task.?.*.link);
    ntasks += 1;

    if ((get_curtask().*.flags & c.TF_SYSTEM) != 0) {
        childp.?.* = task;
    } else {
        _ = c.copyout(@as(?*const anyopaque, @ptrCast(&task)), @as(?*anyopaque, @ptrCast(childp)), @sizeOf(c.task_t));
    }

    c.sched_unlock();
    return 0;
}

pub fn task_terminate(task: c.task_t) callconv(.c) c_int {
    c.sched_lock();
    if (task_valid(task) == 0) {
        c.sched_unlock();
        return c.ESRCH;
    }
    if (task_access(task) == 0) {
        c.sched_unlock();
        return c.EPERM;
    }

    list_remove_fn(&task.?.*.link);
    @as(*usize, @ptrCast(&task.?.*.handler)).* = @as(usize, @bitCast(@as(isize, -1)));

    c.timer_stop(&task.?.*.alarm);
    c.object_cleanup(task);
    c.mutex_cleanup(task);
    c.cond_cleanup(task);
    c.sem_cleanup(task);

    {
        var n = list_first(&task.?.*.threads);
        while (n != @as(*c.struct_list, @ptrCast(&task.?.*.threads))) {
            const next_node = list_next_node(n);
            const t = @as(*c.struct_thread, @fieldParentPtr("task_link", n));
            if (t != get_curthread()) {
                c.thread_destroy(t);
            }
            n = next_node;
        }
    }
    if (task == get_curtask()) {
        c.thread_destroy(get_curthread());
    }

    c.vm_terminate(task.?.*.map);
    task.?.*.map = null;
    c.kmem_free(task);
    ntasks -= 1;
    c.sched_unlock();
    return 0;
}

pub fn task_self() callconv(.c) c.task_t {
    return get_curthread().*.task;
}

pub fn task_suspend(task: c.task_t) callconv(.c) c_int {
    c.sched_lock();
    if (task_valid(task) == 0) {
        c.sched_unlock();
        return c.ESRCH;
    }
    if (task_access(task) == 0) {
        c.sched_unlock();
        return c.EPERM;
    }

    task.?.*.suscnt += 1;
    if (task.?.*.suscnt == 1) {
        var n = list_first(&task.?.*.threads);
        while (n != @as(*c.struct_list, @ptrCast(&task.?.*.threads))) : (n = list_next_node(n)) {
            const t = @as(*c.struct_thread, @fieldParentPtr("task_link", n));
            _ = c.thread_suspend(t);
        }
    }
    c.sched_unlock();
    return 0;
}

pub fn task_resume(task: c.task_t) callconv(.c) c_int {
    if (task == get_curtask()) return c.EINVAL;

    c.sched_lock();
    if (task_valid(task) == 0) {
        c.sched_unlock();
        return c.ESRCH;
    }
    if (task_access(task) == 0) {
        c.sched_unlock();
        return c.EPERM;
    }
    if (task.?.*.suscnt == 0) {
        c.sched_unlock();
        return c.EINVAL;
    }

    task.?.*.suscnt -= 1;
    if (task.?.*.suscnt == 0) {
        var n = list_first(&task.?.*.threads);
        while (n != @as(*c.struct_list, @ptrCast(&task.?.*.threads))) : (n = list_next_node(n)) {
            const t = @as(*c.struct_thread, @fieldParentPtr("task_link", n));
            _ = c.thread_resume(t);
        }
    }
    c.sched_unlock();
    return 0;
}

pub fn task_setname(task: c.task_t, name: [*:0]const u8) callconv(.c) c_int {
    var str: [c.MAXTASKNAME]u8 = undefined;

    c.sched_lock();
    if (task_valid(task) == 0) {
        c.sched_unlock();
        return c.ESRCH;
    }
    if (task_access(task) == 0) {
        c.sched_unlock();
        return c.EPERM;
    }

    if ((get_curtask().*.flags & c.TF_SYSTEM) != 0) {
        _ = c.strlcpy(@ptrCast(&task.?.*.name), @ptrCast(name), c.MAXTASKNAME);
    } else {
        const err = c.copyinstr(@as(?*const anyopaque, @ptrCast(name)), @as(?*anyopaque, @ptrCast(&str)), c.MAXTASKNAME);
        if (err != 0) {
            c.sched_unlock();
            return err;
        }
        _ = c.strlcpy(@ptrCast(&task.?.*.name), @ptrCast(&str), c.MAXTASKNAME);
    }
    c.sched_unlock();
    return 0;
}

pub fn task_setcap(task: c.task_t, cap: c.cap_t) callconv(.c) c_int {
    if (task_capable(c.CAP_SETPCAP) == 0) return c.EPERM;

    c.sched_lock();
    if (task_valid(task) == 0) {
        c.sched_unlock();
        return c.ESRCH;
    }
    if (task_access(task) == 0) {
        c.sched_unlock();
        return c.EPERM;
    }
    task.?.*.capability = cap;
    c.sched_unlock();
    return 0;
}

pub fn task_chkcap(task: c.task_t, cap: c.cap_t) callconv(.c) c_int {
    var err: c_int = 0;

    c.sched_lock();
    if (task_valid(task) == 0) {
        c.sched_unlock();
        return c.ESRCH;
    }
    if ((task.?.*.capability & cap) == 0) {
        if ((get_curtask().*.flags & c.TF_AUDIT) != 0) {
            c.panic("audit failed");
        }
        err = c.EPERM;
    }
    c.sched_unlock();
    return err;
}

pub fn task_info(info: ?*c.struct_taskinfo) callconv(.c) c_int {
    const target: c.u_long = info.?.*.cookie;
    var i: c.u_long = 0;

    c.sched_lock();
    var n = list_first(&task_list);
    while (true) : (n = list_next_node(n)) {
        if (i == target) {
            const task = @as(*c.struct_task, @fieldParentPtr("link", n));
            info.?.*.cookie = i + 1;
            info.?.*.id = task;
            info.?.*.flags = task.*.flags;
            info.?.*.suscnt = task.*.suscnt;
            info.?.*.capability = task.*.capability;
            info.?.*.vmsize = task.*.map.?.*.total;
            info.?.*.nthreads = task.*.nthreads;
            info.?.*.active = if (task == get_curtask()) @as(c_int, 1) else @as(c_int, 0);
            _ = c.strlcpy(@ptrCast(&info.?.*.taskname), @ptrCast(&task.*.name), c.MAXTASKNAME);
            c.sched_unlock();
            return 0;
        }
        i += 1;
        if (n == @as(*c.struct_list, @ptrCast(&task_list))) break;
    }
    c.sched_unlock();
    return c.ESRCH;
}

pub fn task_bootstrap() callconv(.c) void {
    var bi: ?*c.struct_bootinfo = null;
    c.machine_bootinfo(&bi);

    var i: c_int = 0;
    while (i < bi.?.*.nr_tasks) : (i += 1) {
        const tasks_ptr: [*]c.struct_module = @ptrCast(&bi.?.*.tasks);
        const mod: *c.struct_module = &tasks_ptr[@intCast(i)];
        var task: c.task_t = null;
        var t: c.thread_t = null;
        var stack: ?*anyopaque = null;

        var err = task_create(&kernel_task, c.VM_NEW, &task);
        if (err != 0) {
            c.panic("unable to load boot task");
        }
        err = c.vm_load(task.?.*.map, mod, &stack);
        if (err != 0) {
            c.panic("unable to load boot task");
        }

        _ = task_setname(task, @ptrCast(&mod.*.name));

        task.?.*.capability = c.CAPSET_BOOT;
        if (c.strncmp(@ptrCast(&task.?.*.name), "exec", c.MAXTASKNAME) == 0) {
            task.?.*.capability |= c.CAP_SETPCAP;
        }

        err = c.thread_create(task, &t);
        if (err != 0) {
            c.panic("unable to load boot task");
        }

        const sp: ?*anyopaque = @ptrFromInt(@as(usize, @intFromPtr(stack)) + c.DFLSTKSZ - @sizeOf(c_int) * 3);
        const entry_fn: *const fn () callconv(.c) void = @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(usize, mod.*.entry)))));
        const gp: ?*anyopaque = if (@hasField(c.struct_module, "got_base")) (if (mod.*.got_base != 0) @ptrFromInt(mod.*.got_base) else null) else null;
        err = c.thread_setup(t, entry_fn, sp, gp);
        if (err != 0) {
            c.panic("unable to load boot task");
        }
        t.?.*.priority = c.PRI_REALTIME;
        t.?.*.basepri = c.PRI_REALTIME;
        _ = c.thread_resume(t);
    }
}

pub fn task_init() callconv(.c) void {
    list_init_fn(&task_list);

    _ = c.strlcpy(@ptrCast(&kernel_task.name), "kernel", c.MAXTASKNAME);
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
    @export(&kernel_task, .{ .name = "kernel_task", .linkage = .strong });
    @export(&task_create, .{ .name = "task_create", .linkage = .strong });
    @export(&task_terminate, .{ .name = "task_terminate", .linkage = .strong });
    @export(&task_self, .{ .name = "task_self", .linkage = .strong });
    @export(&task_suspend, .{ .name = "task_suspend", .linkage = .strong });
    @export(&task_resume, .{ .name = "task_resume", .linkage = .strong });
    @export(&task_setname, .{ .name = "task_setname", .linkage = .strong });
    @export(&task_setcap, .{ .name = "task_setcap", .linkage = .strong });
    @export(&task_chkcap, .{ .name = "task_chkcap", .linkage = .strong });
    @export(&task_capable, .{ .name = "task_capable", .linkage = .strong });
    @export(&task_valid, .{ .name = "task_valid", .linkage = .strong });
    @export(&task_access, .{ .name = "task_access", .linkage = .strong });
    @export(&task_info, .{ .name = "task_info", .linkage = .strong });
    @export(&task_bootstrap, .{ .name = "task_bootstrap", .linkage = .strong });
    @export(&task_init, .{ .name = "task_init", .linkage = .strong });
}
