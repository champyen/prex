const std = @import("std");
const builtin = @import("builtin");
const c = @import("c").c;

const ffi = @import("ffi");
const hal = ffi.hal;
const kern = ffi.kern;
const task = ffi.task;
const thread = ffi.thread;
const lib = ffi.lib;
const kutil = ffi.kutil;

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

const sysent: [NSYSCALL]SysEnt = .{
    SysEnt.init("exception_return", 0, c.exception_return),
    SysEnt.init("exception_setup", 1, c.exception_setup),
    SysEnt.init("exception_raise", 2, c.exception_raise),
    SysEnt.init("exception_wait", 1, c.exception_wait),
    SysEnt.init("task_create", 3, task.create),
    SysEnt.init("task_terminate", 1, task.terminate),
    SysEnt.init("task_self", 0, task.self),
    SysEnt.init("task_suspend", 1, c.task_suspend),
    SysEnt.init("task_resume", 1, c.task_resume),
    SysEnt.init("task_setname", 2, c.task_setname),
    SysEnt.init("task_setcap", 2, c.task_setcap),
    SysEnt.init("task_chkcap", 2, c.task_chkcap),
    SysEnt.init("thread_create", 2, thread.create),
    SysEnt.init("thread_terminate", 1, thread.terminate),
    SysEnt.init("thread_setup", 4, thread.setup),
    SysEnt.init("thread_self", 0, thread.self),
    SysEnt.init("thread_yield", 0, thread.yield),
    SysEnt.init("thread_suspend", 1, thread.@"suspend"),
    SysEnt.init("thread_resume", 1, thread.@"resume"),
    SysEnt.init("thread_schedparam", 3, c.thread_schedparam),
    SysEnt.init("vm_allocate", 4, c.vm_allocate),
    SysEnt.init("vm_free", 2, c.vm_free),
    SysEnt.init("vm_attribute", 3, c.vm_attribute),
    SysEnt.init("vm_map", 4, c.vm_map),
    SysEnt.init("object_create", 2, c.object_create),
    SysEnt.init("object_destroy", 1, c.object_destroy),
    SysEnt.init("object_lookup", 2, c.object_lookup),
    SysEnt.init("msg_send", 3, c.msg_send),
    SysEnt.init("msg_receive", 3, c.msg_receive),
    SysEnt.init("msg_reply", 3, c.msg_reply),
    SysEnt.init("timer_sleep", 2, c.timer_sleep),
    SysEnt.init("timer_alarm", 2, c.timer_alarm),
    SysEnt.init("timer_periodic", 3, c.timer_periodic),
    SysEnt.init("timer_waitperiod", 0, c.timer_waitperiod),
    SysEnt.init("device_open", 3, c.device_open),
    SysEnt.init("device_close", 1, c.device_close),
    SysEnt.init("device_read", 4, c.device_read),
    SysEnt.init("device_write", 4, c.device_write),
    SysEnt.init("device_ioctl", 3, c.device_ioctl),
    SysEnt.init("mutex_init", 1, c.mutex_init),
    SysEnt.init("mutex_destroy", 1, c.mutex_destroy),
    SysEnt.init("mutex_lock", 1, c.mutex_lock),
    SysEnt.init("mutex_trylock", 1, c.mutex_trylock),
    SysEnt.init("mutex_unlock", 1, c.mutex_unlock),
    SysEnt.init("cond_init", 1, c.cond_init),
    SysEnt.init("cond_destroy", 1, c.cond_destroy),
    SysEnt.init("cond_wait", 2, c.cond_wait),
    SysEnt.init("cond_signal", 1, c.cond_signal),
    SysEnt.init("cond_broadcast", 1, c.cond_broadcast),
    SysEnt.init("sem_init", 2, c.sem_init),
    SysEnt.init("sem_destroy", 1, c.sem_destroy),
    SysEnt.init("sem_wait", 2, c.sem_wait),
    SysEnt.init("sem_trywait", 1, c.sem_trywait),
    SysEnt.init("sem_post", 1, c.sem_post),
    SysEnt.init("sem_getvalue", 2, c.sem_getvalue),
    SysEnt.init("sys_log", 1, c.sys_log),
    SysEnt.init("sys_panic", 1, c.sys_panic),
    SysEnt.init("sys_info", 2, c.sys_info),
    SysEnt.init("sys_time", 1, c.sys_time),
    SysEnt.init("sys_debug", 2, c.sys_debug),
    SysEnt.init("device_gather_read", 4, c.device_gather_read),
    SysEnt.init("device_scatter_write", 4, c.device_scatter_write),
};

fn syscall_handler_std(a1: c.register_t, a2: c.register_t, a3: c.register_t, a4: c.register_t, id: c.register_t) callconv(.c) c.register_t {
    var retval: c.register_t = kern.Errno.EINVAL;

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

fn syscall_handler_armv8m(regs: *hal.CpuRegs, id: c.register_t) callconv(.c) c.register_t {
    var retval: c.register_t = kern.Errno.EINVAL;

    if (kutil.get_curthread()) |cur| {
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
    const cur_task = kutil.get_curtask() orelse return;

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
    const cur_task = kutil.get_curtask() orelse return;

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
