const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});

extern fn hal_get_cpu_control() callconv(.c) ?*c.struct_cpu_control;

var idle_thread: c.struct_thread = std.mem.zeroes(c.struct_thread);
var zombie: c.thread_t = null;
var thread_list: c.struct_list = undefined;

pub var curthread: c.thread_t = &idle_thread;
pub var irq_nesting: c_int = 0;
pub var curspl: c_int = 15;

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

inline fn list_init(head: *c.struct_list) void {
    head.next = @ptrCast(head);
    head.prev = @ptrCast(head);
}

inline fn list_insert(prev: *c.struct_list, node: *c.struct_list) void {
    node.prev = @ptrCast(prev);
    node.next = prev.next;
    prev.next.?.*.prev = @ptrCast(node);
    prev.next = @ptrCast(node);
}

inline fn list_remove(node: *c.struct_list) void {
    node.prev.?.*.next = node.next;
    node.next.?.*.prev = node.prev;
}

fn thread_allocate(task: c.task_t) c.thread_t {
    const mem = c.kmem_alloc(@sizeOf(c.struct_thread));
    const t: c.thread_t = @ptrCast(@alignCast(mem));
    if (t == null) return null;

    const stack = c.kmem_alloc(c.KSTACKSZ);
    if (stack == null) {
        c.kmem_free(t);
        return null;
    }

    _ = c.memset(t, 0, @sizeOf(c.struct_thread));
    t.*.kstack = stack;
    t.*.task = task;
    list_init(&t.*.mutexes);
    list_insert(&thread_list, &t.*.link);
    list_insert(&task.*.threads, &t.*.task_link);
    task.*.nthreads += 1;

    return t;
}

fn thread_deallocate(t: c.thread_t) void {
    list_remove(&t.*.task_link);
    list_remove(&t.*.link);
    t.*.excbits = 0;
    t.*.task.*.nthreads -= 1;

    if (zombie) |z| {
        c.kmem_free(z.*.kstack);
        z.*.kstack = null;
        c.kmem_free(z);
        zombie = null;
    }

    if (t == get_curthread()) {
        zombie = t;
        return;
    }

    c.kmem_free(t.*.kstack);
    t.*.kstack = null;
    c.kmem_free(t);
}

pub fn thread_create(task: c.task_t, tp: ?*c.thread_t) callconv(.c) c_int {
    c.sched_lock();
    defer c.sched_unlock();

    if (c.task_valid(task) == 0) {
        return c.ESRCH;
    }
    if (c.task_access(task) == 0) {
        return c.EPERM;
    }
    if (task.*.nthreads >= c.MAXTHREADS) {
        return c.EAGAIN;
    }

    if ((get_curtask().?.*.flags & c.TF_SYSTEM) == 0) {
        var tmp: c.thread_t = null;
        if (c.copyout(@as(?*const anyopaque, @ptrCast(&tmp)), @as(?*anyopaque, @ptrCast(tp)), @sizeOf(c.thread_t)) != 0) {
            return c.EFAULT;
        }
    }

    const t = thread_allocate(task) orelse {
        return c.ENOMEM;
    };

    if (comptime @hasDecl(c, "CONFIG_ARMV8M")) {
        _ = c.memset(t.*.kstack, 0, c.KSTACKSZ);
        const parent_uregs = get_curthread().?.*.ctx.uregs;
        const child_uregs: *c.struct_cpu_regs = @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(@intFromPtr(t.*.kstack) + c.KSTACKSZ - @sizeOf(c.struct_cpu_regs)))));
        _ = c.memcpy(child_uregs, parent_uregs, @sizeOf(c.struct_cpu_regs));
    } else {
        _ = c.memcpy(t.*.kstack, get_curthread().?.*.kstack, c.KSTACKSZ);
    }

    const sp: usize = @intFromPtr(t.*.kstack) + c.KSTACKSZ;
    c.context_set(&t.*.ctx, c.CTX_KSTACK, toReg(sp));
    c.context_set(&t.*.ctx, c.CTX_KENTRY, toReg(&c.syscall_ret));
    c.sched_start(t, get_curthread().?.*.basepri, c.SCHED_RR);
    t.*.suscnt = task.*.suscnt + 1;

    if (get_curtask().?.*.flags & c.TF_SYSTEM != 0) {
        if (tp) |tp_ptr| {
            tp_ptr.* = t;
        }
    } else {
        _ = c.copyout(@as(?*const anyopaque, @ptrCast(&t)), @as(?*anyopaque, @ptrCast(tp)), @sizeOf(c.thread_t));
    }

    return 0;
}

pub fn thread_terminate(t: c.thread_t) callconv(.c) c_int {
    c.sched_lock();
    defer c.sched_unlock();

    if (c.thread_valid(t) == 0) {
        return c.ESRCH;
    }
    if (c.task_access(t.*.task) == 0) {
        return c.EPERM;
    }
    thread_destroy(t);
    return 0;
}

pub fn thread_destroy(th: c.thread_t) callconv(.c) void {
    c.msg_cancel(th);
    c.mutex_cancel(th);
    c.timer_cancel(th);
    c.sched_stop(th);
    thread_deallocate(th);
}

pub fn thread_setup(t: c.thread_t, entry: ?*anyopaque, stack: ?*anyopaque, gp: ?*anyopaque) callconv(.c) c_int {
    if (entry != null and !user_area(entry)) return c.EINVAL;
    if (stack != null and !user_area(stack)) return c.EINVAL;

    c.sched_lock();
    defer c.sched_unlock();

    if (c.thread_valid(t) == 0) {
        return c.ESRCH;
    }
    if (c.task_access(t.*.task) == 0) {
        return c.EPERM;
    }

    const s = c.splhigh();
    if (entry != null) {
        if (comptime @hasDecl(c, "CONFIG_ARMV8M")) {
            t.*.task.*.got_base = if (gp) |p| @intFromPtr(p) else 0;
        }
        c.context_set(&t.*.ctx, c.CTX_UENTRY, toReg(entry));
    }
    if (stack != null) {
        c.context_set(&t.*.ctx, c.CTX_USTACK, toReg(stack));
    }
    _ = c.splx(s);

    return 0;
}

pub fn thread_self() callconv(.c) c.thread_t {
    return get_curthread();
}

pub fn thread_valid(t: c.thread_t) callconv(.c) c_int {
    const head = &thread_list;
    var n: *c.struct_list = @ptrCast(head.next);
    while (n != head) : (n = @ptrCast(n.next)) {
        const tmp: *c.struct_thread = @fieldParentPtr("link", n);
        if (tmp == t) return 1;
    }
    return 0;
}

pub fn thread_yield() callconv(.c) void {
    c.sched_yield();
}

pub fn thread_suspend(t: c.thread_t) callconv(.c) c_int {
    c.sched_lock();
    defer c.sched_unlock();

    if (c.thread_valid(t) == 0) {
        return c.ESRCH;
    }
    if (c.task_access(t.*.task) == 0) {
        return c.EPERM;
    }
    t.*.suscnt += 1;
    if (t.*.suscnt == 1) {
        c.sched_suspend(t);
        if (comptime @hasDecl(c, "CONFIG_ARMV8M")) {
            if (t.*.ctx.uregs != null and t.*.ctx.saved_uregs_valid == 0) {
                _ = c.memcpy(&t.*.ctx.saved_uregs, t.*.ctx.uregs, @sizeOf(c.struct_cpu_regs));
                t.*.ctx.saved_uregs_ptr = t.*.ctx.uregs;
                t.*.ctx.saved_uregs_valid = 1;
                t.*.ctx.uregs = &t.*.ctx.saved_uregs;
            }
        }
    }

    return 0;
}

pub fn thread_resume(t: c.thread_t) callconv(.c) c_int {
    c.sched_lock();
    defer c.sched_unlock();

    if (c.thread_valid(t) == 0) {
        return c.ESRCH;
    }
    if (c.task_access(t.*.task) == 0) {
        return c.EPERM;
    }
    if (t.*.suscnt == 0) {
        return c.EINVAL;
    }
    t.*.suscnt -= 1;
    if (t.*.suscnt == 0 and t.*.task.*.suscnt == 0) {
        c.sched_resume(t);
    }

    return 0;
}

pub fn thread_schedparam(t: c.thread_t, op: c_int, param: ?*c_int) callconv(.c) c_int {
    var pri: c_int = undefined;
    var policy: c_int = undefined;
    var err: c_int = 0;

    c.sched_lock();
    defer c.sched_unlock();

    if (c.thread_valid(t) == 0) {
        return c.ESRCH;
    }
    if (t.*.task.*.flags & c.TF_SYSTEM != 0) {
        return c.EINVAL;
    }

    if (!(t.*.task == get_curtask() or t.*.task.*.parent == get_curtask()) and c.task_capable(c.CAP_NICE) == 0) {
        return c.EPERM;
    }

    switch (op) {
        c.SOP_GETPRI => {
            pri = c.sched_getpri(t);
            if (c.copyout(&pri, param, @sizeOf(c_int)) != 0) {
                err = c.EINVAL;
            }
        },
        c.SOP_SETPRI => {
            if (c.copyin(param, &pri, @sizeOf(c_int)) != 0) {
                err = c.EINVAL;
            } else {
                if (pri < 0) pri = 0;
                if (pri >= c.PRI_IDLE) pri = c.PRI_IDLE - 1;

                if (pri <= c.PRI_REALTIME and c.task_capable(c.CAP_NICE) == 0) {
                    err = c.EPERM;
                } else {
                    if (t.*.priority != t.*.basepri and pri > t.*.priority) {
                        pri = t.*.priority;
                    }

                    c.mutex_setpri(t, pri);
                    c.sched_setpri(t, pri, pri);
                }
            }
        },
        c.SOP_GETPOLICY => {
            policy = c.sched_getpolicy(t);
            if (c.copyout(&policy, param, @sizeOf(c_int)) != 0) {
                err = c.EINVAL;
            }
        },
        c.SOP_SETPOLICY => {
            if (c.copyin(param, &policy, @sizeOf(c_int)) != 0) {
                err = c.EINVAL;
            } else {
                err = c.sched_setpolicy(t, policy);
            }
        },
        else => {
            err = c.EINVAL;
        },
    }

    return err;
}

pub fn thread_idle() callconv(.c) void {
    while (true) {
        c.machine_idle();
    }
}

pub fn thread_info(info: ?*c.struct_threadinfo) callconv(.c) c_int {
    const target = info.?.cookie;
    var i: c_ulong = 0;

    c.sched_lock();
    defer c.sched_unlock();

    var n: *c.struct_list = @ptrCast(thread_list.prev);
    while (n != &thread_list) {
        if (i == target) {
            const t: *c.struct_thread = @fieldParentPtr("link", n);
            info.?.cookie = i;
            info.?.id = t;
            info.?.state = t.state;
            info.?.policy = t.policy;
            info.?.priority = t.priority;
            info.?.basepri = t.basepri;
            info.?.time = t.time;
            info.?.suscnt = t.suscnt;
            info.?.task = t.task;
            info.?.active = if (t == @as(?*c.struct_thread, @ptrCast(get_curthread().?))) 1 else 0;
            _ = c.strlcpy(@ptrCast(&info.?.taskname), @ptrCast(&t.task.*.name), c.MAXTASKNAME);
            _ = c.strlcpy(@ptrCast(&info.?.slpevt), if (t.slpevt) |evt| @as([*c]const u8, @ptrCast(evt.*.name)) else @as([*c]const u8, "-"), c.MAXEVTNAME);
            return 0;
        }
        i += 1;
        n = @ptrCast(n.prev);
    }

    return c.ESRCH;
}

pub fn kthread_create(entry: ?*const fn (?*anyopaque) callconv(.c) void, arg: ?*anyopaque, pri: c_int) callconv(.c) c.thread_t {
    const t = thread_allocate(&c.kernel_task) orelse return null;

    _ = c.memset(t.*.kstack, 0, c.KSTACKSZ);
    const sp: usize = @intFromPtr(t.*.kstack) + c.KSTACKSZ;
    c.context_set(&t.*.ctx, c.CTX_KSTACK, toReg(sp));
    c.context_set(&t.*.ctx, c.CTX_KENTRY, toReg(entry));
    c.context_set(&t.*.ctx, c.CTX_KARG, toReg(arg));
    c.sched_start(t, pri, c.SCHED_FIFO);
    t.*.suscnt = 1;
    c.sched_resume(t);

    return t;
}

pub fn kthread_terminate(t: c.thread_t) callconv(.c) void {
    c.sched_lock();
    defer c.sched_unlock();

    c.mutex_cancel(t);
    c.timer_cancel(t);
    c.sched_stop(t);
    thread_deallocate(t);
}

pub fn thread_create_idle() callconv(.c) c.thread_t {
    const t = thread_allocate(&c.kernel_task) orelse @panic("thread_create_idle");

    _ = c.memset(t.*.kstack, 0, c.KSTACKSZ);
    t.*.state = c.TS_RUN;
    t.*.locks = 1;
    t.*.priority = c.PRI_IDLE;

    return t;
}

pub fn thread_init() callconv(.c) void {
    const stack = c.kmem_alloc(c.KSTACKSZ) orelse @panic("thread_init");
    list_init(&thread_list);

    _ = c.memset(stack, 0, c.KSTACKSZ);
    const sp: usize = @intFromPtr(stack) + c.KSTACKSZ;
    c.context_set(&idle_thread.ctx, c.CTX_KSTACK, toReg(sp));
    c.sched_start(&idle_thread, c.PRI_IDLE, c.SCHED_FIFO);
    idle_thread.kstack = stack;
    idle_thread.task = &c.kernel_task;
    idle_thread.state = c.TS_RUN;
    list_init(&idle_thread.mutexes);

    list_insert(&thread_list, &idle_thread.link);
    list_insert(&c.kernel_task.threads, &idle_thread.task_link);
    c.kernel_task.nthreads = 1;
}

inline fn user_area(a: ?*const anyopaque) bool {
    if (a == null) return false;
    if (comptime @hasDecl(c, "CONFIG_MMU")) {
        return @intFromPtr(a) < c.USERLIMIT;
    } else {
        return true;
    }
}

comptime {
    @export(&idle_thread, .{ .name = "idle_thread", .linkage = .strong });
    if (!@hasDecl(c, "CONFIG_SMP")) {
        @export(&curthread, .{ .name = "curthread", .linkage = .strong });
        @export(&irq_nesting, .{ .name = "irq_nesting", .linkage = .strong });
        @export(&curspl, .{ .name = "curspl", .linkage = .strong });
    }
    @export(&thread_create, .{ .name = "thread_create", .linkage = .strong });
    @export(&thread_terminate, .{ .name = "thread_terminate", .linkage = .strong });
    @export(&thread_destroy, .{ .name = "thread_destroy", .linkage = .strong });
    @export(&thread_setup, .{ .name = "thread_setup", .linkage = .strong });
    @export(&thread_self, .{ .name = "thread_self", .linkage = .strong });
    @export(&thread_valid, .{ .name = "thread_valid", .linkage = .strong });
    @export(&thread_yield, .{ .name = "thread_yield", .linkage = .strong });
    @export(&thread_suspend, .{ .name = "thread_suspend", .linkage = .strong });
    @export(&thread_resume, .{ .name = "thread_resume", .linkage = .strong });
    @export(&thread_schedparam, .{ .name = "thread_schedparam", .linkage = .strong });
    @export(&thread_idle, .{ .name = "thread_idle", .linkage = .strong });
    @export(&thread_info, .{ .name = "thread_info", .linkage = .strong });
    @export(&kthread_create, .{ .name = "kthread_create", .linkage = .strong });
    @export(&kthread_terminate, .{ .name = "kthread_terminate", .linkage = .strong });
    @export(&thread_create_idle, .{ .name = "thread_create_idle", .linkage = .strong });
    @export(&thread_init, .{ .name = "thread_init", .linkage = .strong });
}
