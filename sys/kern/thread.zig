const std = @import("std");
const builtin = @import("builtin");

const c = @import("c").c;

const ffi = @import("ffi");
const hal = ffi.hal;
const lib = ffi.lib;
const kmem = ffi.kmem;
const sched = ffi.sched;
const task = ffi.task;
const smp = ffi.smp;

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
        return @ptrCast(smp.get_cpu_control().*.active_thread);
    } else {
        return @ptrCast(curthread);
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

fn allocate(tsk: c.task_t) c.thread_t {
    const mem = kmem.alloc(@sizeOf(c.struct_thread));
    const t: c.thread_t = @ptrCast(@alignCast(mem));
    if (t == null) return null;

    const stack = kmem.alloc(c.KSTACKSZ);
    if (stack == null) {
        kmem.free(t);
        return null;
    }

    _ = lib.memset(t, 0, @sizeOf(c.struct_thread));
    t.*.kstack = stack;
    t.*.task = tsk;
    list_init(&t.*.mutexes);
    list_insert(&thread_list, &t.*.link);
    list_insert(&tsk.*.threads, &t.*.task_link);
    tsk.*.nthreads += 1;

    return t;
}

fn deallocate(t: c.thread_t) void {
    list_remove(&t.*.task_link);
    list_remove(&t.*.link);
    t.*.excbits = 0;
    t.*.task.*.nthreads -= 1;

    if (zombie) |z| {
        kmem.free(z.*.kstack);
        z.*.kstack = null;
        kmem.free(z);
        zombie = null;
    }

    if (t == get_curthread()) {
        zombie = t;
        return;
    }

    kmem.free(t.*.kstack);
    t.*.kstack = null;
    kmem.free(t);
}

pub fn create(tsk: c.task_t, tp: ?*c.thread_t) callconv(.c) c_int {
    sched.lock();
    defer sched.unlock();

    if (task.valid(tsk) == 0) {
        return c.ESRCH;
    }
    if (task.access(tsk) == 0) {
        return c.EPERM;
    }
    if (tsk.*.nthreads >= c.MAXTHREADS) {
        return c.EAGAIN;
    }

    if ((get_curtask().?.*.flags & c.TF_SYSTEM) == 0) {
        var tmp: c.thread_t = null;
        if (ffi.vm.copyout(@as(?*const anyopaque, @ptrCast(&tmp)), @as(?*anyopaque, @ptrCast(tp)), @sizeOf(c.thread_t)) != 0) {
            return c.EFAULT;
        }
    }

    const t = allocate(tsk) orelse {
        return c.ENOMEM;
    };

    if (comptime @hasDecl(c, "CONFIG_ARMV8M")) {
        _ = lib.memset(t.*.kstack, 0, c.KSTACKSZ);
        const parent_uregs = get_curthread().?.*.ctx.uregs;
        const child_uregs: *c.struct_cpu_regs = @ptrCast(@alignCast(@as(*anyopaque, @ptrFromInt(@intFromPtr(t.*.kstack) + c.KSTACKSZ - @sizeOf(c.struct_cpu_regs)))));
        _ = lib.memcpy(child_uregs, parent_uregs, @sizeOf(c.struct_cpu_regs));
    } else {
        _ = lib.memcpy(t.*.kstack, get_curthread().?.*.kstack, c.KSTACKSZ);
    }

    const sp: usize = @intFromPtr(t.*.kstack) + c.KSTACKSZ;
    hal.context_set(&t.*.ctx, c.CTX_KSTACK, toReg(sp));
    hal.context_set(&t.*.ctx, c.CTX_KENTRY, toReg(&c.syscall_ret));
    sched.start(t, get_curthread().?.*.basepri, c.SCHED_RR);
    t.*.suscnt = tsk.*.suscnt + 1;

    if (get_curtask().?.*.flags & c.TF_SYSTEM != 0) {
        if (tp) |tp_ptr| {
            tp_ptr.* = t;
        }
    } else {
        _ = ffi.vm.copyout(@as(?*const anyopaque, @ptrCast(&t)), @as(?*anyopaque, @ptrCast(tp)), @sizeOf(c.thread_t));
    }

    return 0;
}

pub fn terminate(t: c.thread_t) callconv(.c) c_int {
    sched.lock();
    defer sched.unlock();

    if (valid(t) == 0) {
        return c.ESRCH;
    }
    if (task.access(t.*.task) == 0) {
        return c.EPERM;
    }
    destroy(t);
    return 0;
}

pub fn destroy(th: c.thread_t) callconv(.c) void {
    ffi.msg.cancel(th);
    ffi.mutex.cancel(th);
    ffi.timer.cancel(th);
    sched.stop(th);
    deallocate(th);
}

pub fn setup(t: c.thread_t, entry: ?*anyopaque, stack: ?*anyopaque, gp: ?*anyopaque) callconv(.c) c_int {
    if (entry != null and !user_area(entry)) return c.EINVAL;
    if (stack != null and !user_area(stack)) return c.EINVAL;

    sched.lock();
    defer sched.unlock();

    if (valid(t) == 0) {
        return c.ESRCH;
    }
    if (task.access(t.*.task) == 0) {
        return c.EPERM;
    }

    const s = hal.splhigh();
    if (entry != null) {
        if (comptime @hasDecl(c, "CONFIG_ARMV8M")) {
            t.*.task.*.got_base = if (gp) |p| @intFromPtr(p) else 0;
        }
        hal.context_set(&t.*.ctx, c.CTX_UENTRY, toReg(entry));
    }
    if (stack != null) {
        hal.context_set(&t.*.ctx, c.CTX_USTACK, toReg(stack));
    }
    _ = hal.splx(s);

    return 0;
}

pub fn self() callconv(.c) c.thread_t {
    return get_curthread();
}

pub fn valid(t: c.thread_t) callconv(.c) c_int {
    const head = &thread_list;
    var n: *c.struct_list = @ptrCast(head.next);
    while (n != head) : (n = @ptrCast(n.next)) {
        const tmp: *c.struct_thread = @fieldParentPtr("link", n);
        if (tmp == t) return 1;
    }
    return 0;
}

pub fn yield() callconv(.c) void {
    sched.yield();
}

pub fn @"suspend"(t: c.thread_t) callconv(.c) c_int {
    sched.lock();
    defer sched.unlock();

    if (valid(t) == 0) {
        return c.ESRCH;
    }
    if (task.access(t.*.task) == 0) {
        return c.EPERM;
    }
    t.*.suscnt += 1;
    if (t.*.suscnt == 1) {
        sched.@"suspend"(t);
        if (comptime @hasDecl(c, "CONFIG_ARMV8M")) {
            if (t.*.ctx.uregs != null and t.*.ctx.saved_uregs_valid == 0) {
                _ = lib.memcpy(&t.*.ctx.saved_uregs, t.*.ctx.uregs, @sizeOf(c.struct_cpu_regs));
                t.*.ctx.saved_uregs_ptr = t.*.ctx.uregs;
                t.*.ctx.saved_uregs_valid = 1;
                t.*.ctx.uregs = &t.*.ctx.saved_uregs;
            }
        }
    }

    return 0;
}

pub fn @"resume"(t: c.thread_t) callconv(.c) c_int {
    sched.lock();
    defer sched.unlock();

    if (valid(t) == 0) {
        return c.ESRCH;
    }
    if (task.access(t.*.task) == 0) {
        return c.EPERM;
    }
    if (t.*.suscnt == 0) {
        return c.EINVAL;
    }
    t.*.suscnt -= 1;
    if (t.*.suscnt == 0 and t.*.task.*.suscnt == 0) {
        sched.@"resume"(t);
    }

    return 0;
}

pub fn schedparam(t: c.thread_t, op: c_int, param: ?*c_int) callconv(.c) c_int {
    var pri: c_int = undefined;
    var policy: c_int = undefined;
    var err: c_int = 0;

    sched.lock();
    defer sched.unlock();

    if (valid(t) == 0) {
        return c.ESRCH;
    }
    if (t.*.task.*.flags & c.TF_SYSTEM != 0) {
        return c.EINVAL;
    }

    if (!(t.*.task == get_curtask() or t.*.task.*.parent == get_curtask()) and task.capable(c.CAP_NICE) == 0) {
        return c.EPERM;
    }

    switch (op) {
        c.SOP_GETPRI => {
            pri = sched.get_pri(t);
            if (ffi.vm.copyout(&pri, param, @sizeOf(c_int)) != 0) {
                err = c.EINVAL;
            }
        },
        c.SOP_SETPRI => {
            if (ffi.vm.copyin(param, &pri, @sizeOf(c_int)) != 0) {
                err = c.EINVAL;
            } else {
                if (pri < 0) pri = 0;
                if (pri >= c.PRI_IDLE) pri = c.PRI_IDLE - 1;

                if (pri <= c.PRI_REALTIME and task.capable(c.CAP_NICE) == 0) {
                    err = c.EPERM;
                } else {
                    if (t.*.priority != t.*.basepri and pri > t.*.priority) {
                        pri = t.*.priority;
                    }

                    ffi.mutex.setpri(t, pri);
                    sched.set_pri(t, pri, pri);
                }
            }
        },
        c.SOP_GETPOLICY => {
            policy = sched.get_policy(t);
            if (ffi.vm.copyout(&policy, param, @sizeOf(c_int)) != 0) {
                err = c.EINVAL;
            }
        },
        c.SOP_SETPOLICY => {
            if (ffi.vm.copyin(param, &policy, @sizeOf(c_int)) != 0) {
                err = c.EINVAL;
            } else {
                err = sched.set_policy(t, policy);
            }
        },
        else => {
            err = c.EINVAL;
        },
    }

    return err;
}

pub fn idle() callconv(.c) void {
    while (true) {
        hal.machine_idle();
    }
}

pub fn info(tinfo: ?*c.struct_threadinfo) callconv(.c) c_int {
    const target = tinfo.?.cookie;
    var i: c_ulong = 0;

    sched.lock();
    defer sched.unlock();

    var n: *c.struct_list = @ptrCast(thread_list.prev);
    while (n != &thread_list) {
        if (i == target) {
            const t: *c.struct_thread = @fieldParentPtr("link", n);
            tinfo.?.cookie = i;
            tinfo.?.id = t;
            tinfo.?.state = t.state;
            tinfo.?.policy = t.policy;
            tinfo.?.priority = t.priority;
            tinfo.?.basepri = t.basepri;
            tinfo.?.time = t.time;
            tinfo.?.suscnt = t.suscnt;
            tinfo.?.task = t.task;
            tinfo.?.active = if (t == @as(?*c.struct_thread, @ptrCast(get_curthread().?))) 1 else 0;
            _ = lib.strlcpy(@ptrCast(&tinfo.?.taskname), @ptrCast(&t.task.*.name), c.MAXTASKNAME);
            _ = lib.strlcpy(@ptrCast(&tinfo.?.slpevt), if (t.slpevt) |evt| @as([*c]const u8, @ptrCast(evt.*.name)) else @as([*c]const u8, "-"), c.MAXEVTNAME);
            return 0;
        }
        i += 1;
        n = @ptrCast(n.prev);
    }

    return c.ESRCH;
}

pub fn createKernel(entry: ?*const fn (?*anyopaque) callconv(.c) void, arg: ?*anyopaque, pri: c_int) callconv(.c) c.thread_t {
    const t = allocate(&c.kernel_task) orelse return null;

    _ = lib.memset(t.*.kstack, 0, c.KSTACKSZ);
    const sp: usize = @intFromPtr(t.*.kstack) + c.KSTACKSZ;
    hal.context_set(&t.*.ctx, c.CTX_KSTACK, toReg(sp));
    hal.context_set(&t.*.ctx, c.CTX_KENTRY, toReg(entry));
    hal.context_set(&t.*.ctx, c.CTX_KARG, toReg(arg));
    sched.start(t, pri, c.SCHED_FIFO);
    t.*.suscnt = 1;
    sched.@"resume"(t);

    return t;
}

pub fn terminateKernel(t: c.thread_t) callconv(.c) void {
    sched.lock();
    defer sched.unlock();

    ffi.mutex.cancel(t);
    ffi.timer.cancel(t);
    sched.stop(t);
    deallocate(t);
}

pub fn createIdle() callconv(.c) c.thread_t {
    const t = allocate(&c.kernel_task) orelse @panic("thread_create_idle");

    _ = lib.memset(t.*.kstack, 0, c.KSTACKSZ);
    t.*.state = c.TS_RUN;
    t.*.locks = 1;
    t.*.priority = c.PRI_IDLE;

    return t;
}

pub fn init() callconv(.c) void {
    const stack = kmem.alloc(c.KSTACKSZ) orelse @panic("thread_init");
    list_init(&thread_list);

    _ = lib.memset(stack, 0, c.KSTACKSZ);
    const sp: usize = @intFromPtr(stack) + c.KSTACKSZ;
    hal.context_set(&idle_thread.ctx, c.CTX_KSTACK, toReg(sp));
    sched.start(&idle_thread, c.PRI_IDLE, c.SCHED_FIFO);
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
    if (@import("root") == @This()) {
        @export(&idle_thread, .{ .name = "idle_thread", .linkage = .strong });
        if (!@hasDecl(c, "CONFIG_SMP")) {
            @export(&curthread, .{ .name = "curthread", .linkage = .strong });
            @export(&irq_nesting, .{ .name = "irq_nesting", .linkage = .strong });
            @export(&curspl, .{ .name = "curspl", .linkage = .strong });
        }
        @export(&create, .{ .name = "thread_create", .linkage = .strong });
        @export(&terminate, .{ .name = "thread_terminate", .linkage = .strong });
        @export(&destroy, .{ .name = "thread_destroy", .linkage = .strong });
        @export(&setup, .{ .name = "thread_setup", .linkage = .strong });
        @export(&self, .{ .name = "thread_self", .linkage = .strong });
        @export(&valid, .{ .name = "thread_valid", .linkage = .strong });
        @export(&yield, .{ .name = "thread_yield", .linkage = .strong });
        @export(&@"suspend", .{ .name = "thread_suspend", .linkage = .strong });
        @export(&@"resume", .{ .name = "thread_resume", .linkage = .strong });
        @export(&schedparam, .{ .name = "thread_schedparam", .linkage = .strong });
        @export(&idle, .{ .name = "thread_idle", .linkage = .strong });
        @export(&info, .{ .name = "thread_info", .linkage = .strong });
        @export(&createKernel, .{ .name = "kthread_create", .linkage = .strong });
        @export(&terminateKernel, .{ .name = "kthread_terminate", .linkage = .strong });
        @export(&createIdle, .{ .name = "thread_create_idle", .linkage = .strong });
        @export(&init, .{ .name = "thread_init", .linkage = .strong });
    }
}
