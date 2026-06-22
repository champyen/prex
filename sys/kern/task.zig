const std = @import("std");
const builtin = @import("builtin");

const c = @import("c").c;
const ffi = @import("ffi");
const cond = ffi.cond;
const hal = ffi.hal;
const kern = ffi.kern;
const mutex = ffi.mutex;
const object = ffi.object;
const sem = ffi.sem;
const timer = ffi.timer;
const kutil = ffi.kutil;
const lib = ffi.lib;
const sched = ffi.sched;
const kmem = ffi.kmem;
const vm = ffi.vm;
const thread = ffi.thread;
const smp = ffi.smp;

var task_list: hal.List = undefined;
var ntasks: c_int = 0;

var kernel_task: kern.Task = std.mem.zeroes(kern.Task);



inline fn list_init_fn(head: *hal.List) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

inline fn list_insert_fn(prev: *hal.List, node: *hal.List) void {
    node.prev = @ptrCast(prev);
    node.next = prev.next;
    prev.next.?.*.prev = @ptrCast(node);
    prev.next = @ptrCast(node);
}

inline fn list_remove_fn(node: *hal.List) void {
    node.prev.?.*.next = node.next;
    node.next.?.*.prev = node.prev;
}

inline fn list_empty(head: *hal.List) bool {
    return head.next == @as(?*hal.List, @ptrCast(head));
}

inline fn list_first(head: *hal.List) *hal.List {
    return @ptrCast(head.next.?);
}

inline fn list_next_node(node: *hal.List) *hal.List {
    return @ptrCast(node.next.?);
}

fn valid(task: kern.TaskRef) callconv(.c) c_int {
    var n = list_first(&task_list);
    while (n != @as(*hal.List, @ptrCast(&task_list))) : (n = list_next_node(n)) {
        const tmp = ffi.IntrusiveList(kern.Task, hal.List, "link").parent(n);
        if (tmp == task) {
            return 1;
        }
    }
    return 0;
}

fn access(task: kern.TaskRef) callconv(.c) c_int {
    if ((task.?.*.flags & kern.TF_SYSTEM) != 0) {
        return 0;
    } else {
        if (task == kutil.cur_task() or task.?.*.parent == kutil.cur_task() or task == kutil.cur_task().*.parent or capable(kern.CAP_TASKCTRL) != 0) {
            return 1;
        }
    }
    return 0;
}

fn capable(cap: c.cap_t) callconv(.c) c_int {
    var capable_val: c_int = 1;

    if ((kutil.cur_task().*.capability & cap) == 0) {
        if ((kutil.cur_task().*.flags & kern.TF_AUDIT) != 0) {
            lib.panic("audit failed");
        }
        capable_val = 0;
    }
    return capable_val;
}

pub fn create(parent: kern.TaskRef, vm_option: c_int, childp: ?*kern.TaskRef) callconv(.c) c_int {
    var task: kern.TaskRef = null;
    var map: c.vm_map_t = null;

    if (parent == null) return kern.Errno.EINVAL;

    switch (vm_option) {
        kern.VM_NEW, kern.VM_SHARE => {},
        else => {
            if (vm_option == kern.VM_COPY) {
            } else {
                return kern.Errno.EINVAL;
            }
        },
    }

    if (ntasks >= hal.MAXTASKS) return kern.Errno.EAGAIN;

    sched.lock();
    defer sched.unlock();
    if (valid(parent) == 0) {
        return kern.Errno.ESRCH;
    }

    if ((kutil.cur_task().*.flags & kern.TF_SYSTEM) == 0) {
        if (access(parent) == 0) {
            return kern.Errno.EPERM;
        }

        task = null;
        if (hal.copyout(@as(?*const anyopaque, @ptrCast(&task)), @as(?*anyopaque, @ptrCast(childp)), @sizeOf(kern.TaskRef)) != 0) {
            return kern.Errno.EFAULT;
        }
    }

    const mem = kmem.alloc(@sizeOf(kern.Task)) orelse return kern.Errno.ENOMEM;
    task = @ptrCast(@alignCast(mem));
    errdefer kmem.free(mem);
    @memset(@as([*]u8, @ptrCast(task))[0..@sizeOf(kern.Task)], 0);

    switch (vm_option) {
        kern.VM_NEW => {
            map = vm.create();
        },
        kern.VM_SHARE => {
            _ = vm.reference(parent.?.*.map);
            map = parent.?.*.map;
        },
        kern.VM_COPY => {
            map = vm.dup(parent.?.*.map);
        },
        else => {},
    }

    if (map == null) {
        return kern.Errno.ENOMEM;
    }

    task.?.*.map = map;
    task.?.*.handler = parent.?.*.handler;
    task.?.*.capability = parent.?.*.capability;
    task.?.*.parent = parent;
    task.?.*.flags = kern.TF_DEFAULT;
    _ = lib.strlcpy(@ptrCast(&task.?.*.name), "*noname", hal.MAXTASKNAME);
    list_init_fn(&task.?.*.threads);
    list_init_fn(&task.?.*.objects);
    list_init_fn(&task.?.*.mutexes);
    list_init_fn(&task.?.*.conds);
    list_init_fn(&task.?.*.sems);
    list_insert_fn(&task_list, &task.?.*.link);
    ntasks += 1;

    if ((kutil.cur_task().*.flags & kern.TF_SYSTEM) != 0) {
        childp.?.* = task;
    } else {
        _ = hal.copyout(@as(?*const anyopaque, @ptrCast(&task)), @as(?*anyopaque, @ptrCast(childp)), @sizeOf(kern.TaskRef));
    }

    return 0;
}

pub fn terminate(task: kern.TaskRef) callconv(.c) c_int {
    sched.lock();
    defer sched.unlock();
    if (valid(task) == 0) {
        return kern.Errno.ESRCH;
    }
    if (access(task) == 0) {
        return kern.Errno.EPERM;
    }

    list_remove_fn(&task.?.*.link);
    @as(*usize, @ptrCast(&task.?.*.handler)).* = @as(usize, @bitCast(@as(isize, -1)));

    timer.stop(&task.?.*.alarm);
    object.cleanup(task);
    mutex.cleanup(task);
    cond.cleanup(task);
    sem.cleanup(task);

    {
        var n = list_first(&task.?.*.threads);
        while (n != @as(*hal.List, @ptrCast(&task.?.*.threads))) {
            const next_node = list_next_node(n);
            const t = ffi.IntrusiveList(kern.Thread, hal.List, "task_link").parent(n);
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
    return 0;
}

pub fn self() callconv(.c) kern.TaskRef {
    return kutil.cur_thread().*.task;
}

pub fn @"suspend"(task: kern.TaskRef) callconv(.c) c_int {
    sched.lock();
    defer sched.unlock();
    if (valid(task) == 0) {
        return kern.Errno.ESRCH;
    }
    if (access(task) == 0) {
        return kern.Errno.EPERM;
    }

    task.?.*.suscnt += 1;
    if (task.?.*.suscnt == 1) {
        var n = list_first(&task.?.*.threads);
        while (n != @as(*hal.List, @ptrCast(&task.?.*.threads))) : (n = list_next_node(n)) {
            const t = ffi.IntrusiveList(kern.Thread, hal.List, "task_link").parent(n);
            _ = thread.@"suspend"(t);
        }
    }
    return 0;
}

pub fn @"resume"(task: kern.TaskRef) callconv(.c) c_int {
    if (task == kutil.cur_task()) return kern.Errno.EINVAL;

    sched.lock();
    defer sched.unlock();
    if (valid(task) == 0) {
        return kern.Errno.ESRCH;
    }
    if (access(task) == 0) {
        return kern.Errno.EPERM;
    }
    if (task.?.*.suscnt == 0) {
        return kern.Errno.EINVAL;
    }

    task.?.*.suscnt -= 1;
    if (task.?.*.suscnt == 0) {
        var n = list_first(&task.?.*.threads);
        while (n != @as(*hal.List, @ptrCast(&task.?.*.threads))) : (n = list_next_node(n)) {
            const t = ffi.IntrusiveList(kern.Thread, hal.List, "task_link").parent(n);
            _ = thread.@"resume"(t);
        }
    }
    return 0;
}

pub fn setname(task: kern.TaskRef, name: [*:0]const u8) callconv(.c) c_int {
    var str: [hal.MAXTASKNAME]u8 = undefined;

    sched.lock();
    defer sched.unlock();
    if (valid(task) == 0) {
        return kern.Errno.ESRCH;
    }
    if (access(task) == 0) {
        return kern.Errno.EPERM;
    }

    if ((kutil.cur_task().*.flags & kern.TF_SYSTEM) != 0) {
        _ = lib.strlcpy(@ptrCast(&task.?.*.name), @ptrCast(name), hal.MAXTASKNAME);
    } else {
        const err = hal.copyinstr(@as(?*const anyopaque, @ptrCast(name)), @as(?*anyopaque, @ptrCast(&str)), hal.MAXTASKNAME);
        if (err != 0) {
            return err;
        }
        _ = lib.strlcpy(@ptrCast(&task.?.*.name), @ptrCast(&str), hal.MAXTASKNAME);
    }
    return 0;
}

pub fn setcap(task: kern.TaskRef, cap: c.cap_t) callconv(.c) c_int {
    if (capable(kern.CAP_SETPCAP) == 0) return kern.Errno.EPERM;

    sched.lock();
    defer sched.unlock();
    if (valid(task) == 0) {
        return kern.Errno.ESRCH;
    }
    if (access(task) == 0) {
        return kern.Errno.EPERM;
    }
    task.?.*.capability = cap;
    return 0;
}

pub fn chkcap(task: kern.TaskRef, cap: c.cap_t) callconv(.c) c_int {
    var err: c_int = 0;

    sched.lock();
    defer sched.unlock();
    if (valid(task) == 0) {
        return kern.Errno.ESRCH;
    }
    if ((task.?.*.capability & cap) == 0) {
        if ((kutil.cur_task().*.flags & kern.TF_AUDIT) != 0) {
            lib.panic("audit failed");
        }
        err = kern.Errno.EPERM;
    }
    return err;
}

pub fn info(task_info_ptr: ?*hal.TaskInfo) callconv(.c) c_int {
    const target: c.u_long = task_info_ptr.?.*.cookie;
    var i: c.u_long = 0;

    sched.lock();
    defer sched.unlock();
    var n = list_first(&task_list);
    while (true) : (n = list_next_node(n)) {
        if (i == target) {
            const task = ffi.IntrusiveList(kern.Task, hal.List, "link").parent(n);
            task_info_ptr.?.*.cookie = i + 1;
            task_info_ptr.?.*.id = task;
            task_info_ptr.?.*.flags = task.*.flags;
            task_info_ptr.?.*.suscnt = task.*.suscnt;
            task_info_ptr.?.*.capability = task.*.capability;
            task_info_ptr.?.*.vmsize = task.*.map.?.*.total;
            task_info_ptr.?.*.nthreads = task.*.nthreads;
            task_info_ptr.?.*.active = if (task == kutil.cur_task()) @as(c_int, 1) else @as(c_int, 0);
            _ = lib.strlcpy(@ptrCast(&task_info_ptr.?.*.taskname), @ptrCast(&task.*.name), hal.MAXTASKNAME);
            return 0;
        }
        i += 1;
        if (n == @as(*hal.List, @ptrCast(&task_list))) break;
    }
    return kern.Errno.ESRCH;
}

pub fn bootstrap() callconv(.c) void {
    var bi: ?*hal.BootInfo = null;
    hal.machine_bootinfo(&bi);

    var i: c_int = 0;
    while (i < bi.?.*.nr_tasks) : (i += 1) {
        const tasks_ptr: [*]hal.Module = @ptrCast(&bi.?.*.tasks);
        const mod: *hal.Module = &tasks_ptr[@intCast(i)];
        var task: kern.TaskRef = null;
        var t: kern.ThreadRef = null;
        var stack: ?*anyopaque = null;

        var err = create(&kernel_task, kern.VM_NEW, &task);
        if (err != 0) {
            lib.panic("unable to load boot task");
        }
        err = vm.load(task.?.*.map, mod, &stack);
        if (err != 0) {
            lib.panic("unable to load boot task");
        }

        _ = setname(task, @ptrCast(&mod.*.name));

        task.?.*.capability = kern.CAPSET_BOOT;
        if (lib.strncmp(@ptrCast(&task.?.*.name), "exec", hal.MAXTASKNAME) == 0) {
            task.?.*.capability |= kern.CAP_SETPCAP;
        }

        err = thread.create(task, &t);
        if (err != 0) {
            lib.panic("unable to load boot task");
        }

        const sp: ?*anyopaque = @ptrFromInt(@as(usize, @intFromPtr(stack)) + hal.DFLSTKSZ - @sizeOf(c_int) * 3);
        const entry_fn: *const fn () callconv(.c) void = @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(@as(usize, mod.*.entry)))));
        const gp: ?*anyopaque = if (@hasField(hal.Module, "got_base")) (if (mod.*.got_base != 0) @ptrFromInt(mod.*.got_base) else null) else null;
        err = thread.setup(t, entry_fn, sp, gp);
        if (err != 0) {
            lib.panic("unable to load boot task");
        }
        t.?.*.priority = hal.PRI_REALTIME;
        t.?.*.basepri = hal.PRI_REALTIME;
        _ = thread.@"resume"(t);
    }
}

pub fn init() callconv(.c) void {
    list_init_fn(&task_list);

    _ = lib.strlcpy(@ptrCast(&kernel_task.name), "kernel", hal.MAXTASKNAME);
    kernel_task.flags = kern.TF_SYSTEM;
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
