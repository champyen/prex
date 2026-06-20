const std = @import("std");
const builtin = @import("builtin");
const c = @import("c").c;

const ffi = @import("ffi");
const lib = ffi.lib;
const smp = ffi.smp;
const thread = ffi.thread;

const TF_TRACE: c_int = 0x00000002;
const NSYSCALL: comptime_int = 62;

const sysfn_t = *const fn (c.register_t, c.register_t, c.register_t, c.register_t) callconv(.c) c.register_t;

const SysEnt = struct {
    narg: c_int,
    name: [*c]const u8,
    call: sysfn_t,

    fn init(name: [*c]const u8, narg: c_int, func: anytype) SysEnt {
        return SysEnt{
            .narg = narg,
            .name = name,
            .call = @ptrCast(&func),
        };
    }
};

extern fn exception_return() callconv(.c) void;
extern fn exception_setup(handler: ?*const fn (c_int) callconv(.c) void) callconv(.c) c_int;
extern fn exception_raise(task: c.task_t, excno: c_int) callconv(.c) c_int;
extern fn exception_wait(excno: [*c]c_int) callconv(.c) c_int;
extern fn task_create(parent: c.task_t, vm_option: c_int, childp: [*c]c.task_t) callconv(.c) c_int;
extern fn task_terminate(task: c.task_t) callconv(.c) c_int;
extern fn task_self() callconv(.c) c.task_t;
extern fn task_suspend(task: c.task_t) callconv(.c) c_int;
extern fn task_resume(task: c.task_t) callconv(.c) c_int;
extern fn task_setname(task: c.task_t, name: [*c]const u8) callconv(.c) c_int;
extern fn task_setcap(task: c.task_t, cap: c.cap_t) callconv(.c) c_int;
extern fn task_chkcap(task: c.task_t, cap: c.cap_t) callconv(.c) c_int;
extern fn thread_create(task: c.task_t, tp: [*c]c.thread_t) callconv(.c) c_int;
extern fn thread_terminate(t: c.thread_t) callconv(.c) c_int;
extern fn thread_setup(t: c.thread_t, entry: ?*const fn () callconv(.c) void, stack: ?*anyopaque, gp: ?*anyopaque) callconv(.c) c_int;
extern fn thread_self() callconv(.c) c.thread_t;
extern fn thread_yield() callconv(.c) void;
extern fn thread_suspend(t: c.thread_t) callconv(.c) c_int;
extern fn thread_resume(t: c.thread_t) callconv(.c) c_int;
extern fn thread_schedparam(t: c.thread_t, op: c_int, param: [*c]c_int) callconv(.c) c_int;
extern fn vm_allocate(task: c.task_t, addr: [*c]?*anyopaque, size: usize, anywhere: c_int) callconv(.c) c_int;
extern fn vm_free(task: c.task_t, addr: ?*anyopaque) callconv(.c) c_int;
extern fn vm_attribute(task: c.task_t, addr: ?*anyopaque, prot: c_int) callconv(.c) c_int;
extern fn vm_map(target: c.task_t, addr: ?*anyopaque, size: usize, alloc: [*c]?*anyopaque) callconv(.c) c_int;
extern fn object_create(name: [*c]const u8, objp: [*c]c.object_t) callconv(.c) c_int;
extern fn object_destroy(obj: c.object_t) callconv(.c) c_int;
extern fn object_lookup(name: [*c]const u8, objp: [*c]c.object_t) callconv(.c) c_int;
extern fn msg_send(obj: c.object_t, msg: ?*anyopaque, size: usize) callconv(.c) c_int;
extern fn msg_receive(obj: c.object_t, msg: ?*anyopaque, size: usize) callconv(.c) c_int;
extern fn msg_reply(obj: c.object_t, msg: ?*anyopaque, size: usize) callconv(.c) c_int;
extern fn timer_sleep(msec: c_ulong, remain: [*c]c_ulong) callconv(.c) c_int;
extern fn timer_alarm(msec: c_ulong, remain: [*c]c_ulong) callconv(.c) c_int;
extern fn timer_periodic(t: c.thread_t, start: c_ulong, period: c_ulong) callconv(.c) c_int;
extern fn timer_waitperiod() callconv(.c) c_int;
extern fn device_open(name: [*c]const u8, mode: c_int, dev: [*c]c.device_t) callconv(.c) c_int;
extern fn device_close(dev: c.device_t) callconv(.c) c_int;
extern fn device_read(dev: c.device_t, buf: ?*anyopaque, nbyte: [*c]usize, blkno: c_int) callconv(.c) c_int;
extern fn device_write(dev: c.device_t, buf: ?*anyopaque, nbyte: [*c]usize, blkno: c_int) callconv(.c) c_int;
extern fn device_ioctl(dev: c.device_t, cmd: c_ulong, arg: ?*anyopaque) callconv(.c) c_int;
extern fn mutex_init(mp: [*c]c.mutex_t) callconv(.c) c_int;
extern fn mutex_destroy(mp: [*c]c.mutex_t) callconv(.c) c_int;
extern fn mutex_lock(mp: [*c]c.mutex_t) callconv(.c) c_int;
extern fn mutex_trylock(mp: [*c]c.mutex_t) callconv(.c) c_int;
extern fn mutex_unlock(mp: [*c]c.mutex_t) callconv(.c) c_int;
extern fn cond_init(cp: [*c]c.cond_t) callconv(.c) c_int;
extern fn cond_destroy(cp: [*c]c.cond_t) callconv(.c) c_int;
extern fn cond_wait(cp: [*c]c.cond_t, mp: [*c]c.mutex_t) callconv(.c) c_int;
extern fn cond_signal(cp: [*c]c.cond_t) callconv(.c) c_int;
extern fn cond_broadcast(cp: [*c]c.cond_t) callconv(.c) c_int;
extern fn sem_init(sp: [*c]c.sem_t, value: c_uint) callconv(.c) c_int;
extern fn sem_destroy(sp: [*c]c.sem_t) callconv(.c) c_int;
extern fn sem_wait(sp: [*c]c.sem_t, timeout: c_ulong) callconv(.c) c_int;
extern fn sem_trywait(sp: [*c]c.sem_t) callconv(.c) c_int;
extern fn sem_post(sp: [*c]c.sem_t) callconv(.c) c_int;
extern fn sem_getvalue(sp: [*c]c.sem_t, value: [*c]c_uint) callconv(.c) c_int;
extern fn device_gather_read(dev: c.device_t, buf: ?*anyopaque, nbyte: [*c]usize, io: [*c]c.struct_dev_io) callconv(.c) c_int;
extern fn device_scatter_write(dev: c.device_t, buf: ?*anyopaque, nbyte: [*c]usize, io: [*c]c.struct_dev_io) callconv(.c) c_int;

fn sys_nosys() callconv(.c) c.register_t {
    return c.EINVAL;
}

const sysent: [NSYSCALL]SysEnt = .{
    SysEnt.init("exception_return", 0, exception_return),
    SysEnt.init("exception_setup", 1, exception_setup),
    SysEnt.init("exception_raise", 2, exception_raise),
    SysEnt.init("exception_wait", 1, exception_wait),
    SysEnt.init("task_create", 3, task_create),
    SysEnt.init("task_terminate", 1, task_terminate),
    SysEnt.init("task_self", 0, task_self),
    SysEnt.init("task_suspend", 1, task_suspend),
    SysEnt.init("task_resume", 1, task_resume),
    SysEnt.init("task_setname", 2, task_setname),
    SysEnt.init("task_setcap", 2, task_setcap),
    SysEnt.init("task_chkcap", 2, task_chkcap),
    SysEnt.init("thread_create", 2, thread_create),
    SysEnt.init("thread_terminate", 1, thread_terminate),
    SysEnt.init("thread_setup", 4, thread_setup),
    SysEnt.init("thread_self", 0, thread_self),
    SysEnt.init("thread_yield", 0, thread_yield),
    SysEnt.init("thread_suspend", 1, thread_suspend),
    SysEnt.init("thread_resume", 1, thread_resume),
    SysEnt.init("thread_schedparam", 3, thread_schedparam),
    SysEnt.init("vm_allocate", 4, vm_allocate),
    SysEnt.init("vm_free", 2, vm_free),
    SysEnt.init("vm_attribute", 3, vm_attribute),
    SysEnt.init("vm_map", 4, vm_map),
    SysEnt.init("object_create", 2, object_create),
    SysEnt.init("object_destroy", 1, object_destroy),
    SysEnt.init("object_lookup", 2, object_lookup),
    SysEnt.init("msg_send", 3, msg_send),
    SysEnt.init("msg_receive", 3, msg_receive),
    SysEnt.init("msg_reply", 3, msg_reply),
    SysEnt.init("timer_sleep", 2, timer_sleep),
    SysEnt.init("timer_alarm", 2, timer_alarm),
    SysEnt.init("timer_periodic", 3, timer_periodic),
    SysEnt.init("timer_waitperiod", 0, timer_waitperiod),
    SysEnt.init("device_open", 3, device_open),
    SysEnt.init("device_close", 1, device_close),
    SysEnt.init("device_read", 4, device_read),
    SysEnt.init("device_write", 4, device_write),
    SysEnt.init("device_ioctl", 3, device_ioctl),
    SysEnt.init("mutex_init", 1, mutex_init),
    SysEnt.init("mutex_destroy", 1, mutex_destroy),
    SysEnt.init("mutex_lock", 1, mutex_lock),
    SysEnt.init("mutex_trylock", 1, mutex_trylock),
    SysEnt.init("mutex_unlock", 1, mutex_unlock),
    SysEnt.init("cond_init", 1, cond_init),
    SysEnt.init("cond_destroy", 1, cond_destroy),
    SysEnt.init("cond_wait", 2, cond_wait),
    SysEnt.init("cond_signal", 1, cond_signal),
    SysEnt.init("cond_broadcast", 1, cond_broadcast),
    SysEnt.init("sem_init", 2, sem_init),
    SysEnt.init("sem_destroy", 1, sem_destroy),
    SysEnt.init("sem_wait", 2, sem_wait),
    SysEnt.init("sem_trywait", 1, sem_trywait),
    SysEnt.init("sem_post", 1, sem_post),
    SysEnt.init("sem_getvalue", 2, sem_getvalue),
    SysEnt.init("sys_log", 1, sys_log),
    SysEnt.init("sys_panic", 1, sys_panic),
    SysEnt.init("sys_info", 2, sys_info),
    SysEnt.init("sys_time", 1, sys_time),
    SysEnt.init("sys_debug", 2, sys_debug),
    SysEnt.init("device_gather_read", 4, device_gather_read),
    SysEnt.init("device_scatter_write", 4, device_scatter_write),
};

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

extern fn sys_log(msg: [*c]const u8) callconv(.c) c_int;
extern fn sys_panic(msg: [*c]const u8) callconv(.c) c_int;
extern fn sys_info(@"type": c_int, buf: ?*anyopaque) callconv(.c) c_int;
extern fn sys_time(ticks: [*c]c_ulong) callconv(.c) c_int;
extern fn sys_debug(cmd: c_int, data: ?*anyopaque) callconv(.c) c_int;

fn syscall_handler_std(a1: c.register_t, a2: c.register_t, a3: c.register_t, a4: c.register_t, id: c.register_t) callconv(.c) c.register_t {
    var retval: c.register_t = c.EINVAL;

    if (comptime builtin.mode == .Debug) {
        strace_entry(a1, a2, a3, a4, id);
    }

    if (id < NSYSCALL) {
        retval = sysent[@intCast(id)].call(a1, a2, a3, a4);
    }

    if (comptime builtin.mode == .Debug) {
        strace_return(retval, id);
    }

    return retval;
}

fn syscall_handler_armv8m(regs: *c.struct_cpu_regs, id: c.register_t) callconv(.c) c.register_t {
    var retval: c.register_t = c.EINVAL;

    if (get_curthread()) |cur| {
        cur.*.ctx.uregs = regs;
    }

    const r0: c.register_t = @intCast(regs.r0);
    const r1: c.register_t = @intCast(regs.r1);
    const r2: c.register_t = @intCast(regs.r2);
    const r3: c.register_t = @intCast(regs.r3);

    if (comptime builtin.mode == .Debug) {
        strace_entry(r0, r1, r2, r3, id);
    }

    if (id < NSYSCALL) {
        retval = sysent[@intCast(id)].call(r0, r1, r2, r3);
    }

    if (comptime builtin.mode == .Debug) {
        strace_return(retval, id);
    }

    return retval;
}

fn strace_entry(a1: c.register_t, a2: c.register_t, a3: c.register_t, a4: c.register_t, id: c.register_t) void {
    const cur_task = get_curtask() orelse return;

    if (cur_task.*.flags & TF_TRACE != 0) {
        if (id >= NSYSCALL) {
            lib.printf("%s: OUT OF RANGE (%d)\n", &cur_task.*.name, id);
            return;
        }

        const callp = &sysent[@intCast(id)];
        switch (callp.narg) {
            0 => lib.printf("%s: %s()\n", &cur_task.*.name, callp.name),
            1 => lib.printf("%s: %s(0x%08x)\n", &cur_task.*.name, callp.name, a1),
            2 => lib.printf("%s: %s(0x%08x, 0x%08x)\n", &cur_task.*.name, callp.name, a1, a2),
            3 => lib.printf("%s: %s(0x%08x, 0x%08x, 0x%08x)\n", &cur_task.*.name, callp.name, a1, a2, a3),
            4 => lib.printf("%s: %s(0x%08x, 0x%08x, 0x%08x, 0x%08x)\n", &cur_task.*.name, callp.name, a1, a2, a3, a4),
            else => {},
        }
    }
}

fn strace_return(retval: c.register_t, id: c.register_t) void {
    const cur_task = get_curtask() orelse return;

    if (cur_task.*.flags & TF_TRACE != 0) {
        if (id >= NSYSCALL) return;
        const callp = &sysent[@intCast(id)];
        if (callp.narg != 0 and retval != 0) {
            lib.printf("%s: !!! %s() = 0x%08x\n", &cur_task.*.name, callp.name, retval);
        }
    }
}

comptime {
    if (@hasDecl(c, "CONFIG_ARMV8M")) {
        @export(&syscall_handler_armv8m, .{ .name = "syscall_handler", .linkage = .strong });
    } else {
        @export(&syscall_handler_std, .{ .name = "syscall_handler", .linkage = .strong });
    }
}
