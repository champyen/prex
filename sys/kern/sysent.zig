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

const sysfn_t = *const fn (kern.Register, kern.Register, kern.Register, kern.Register) callconv(.c) kern.Register;

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
    SysEnt.init("exception_return", 0, ffi.exception.@"return"),
    SysEnt.init("exception_setup", 1, ffi.exception.setup),
    SysEnt.init("exception_raise", 2, ffi.exception.raise),
    SysEnt.init("exception_wait", 1, ffi.exception.wait),
    SysEnt.init("task_create", 3, task.create),
    SysEnt.init("task_terminate", 1, task.terminate),
    SysEnt.init("task_self", 0, task.self),
    SysEnt.init("task_suspend", 1, ffi.task.@"suspend"),
    SysEnt.init("task_resume", 1, ffi.task.@"resume"),
    SysEnt.init("task_setname", 2, ffi.task.setname),
    SysEnt.init("task_setcap", 2, ffi.task.setcap),
    SysEnt.init("task_chkcap", 2, ffi.task.chkcap),
    SysEnt.init("thread_create", 2, thread.create),
    SysEnt.init("thread_terminate", 1, thread.terminate),
    SysEnt.init("thread_setup", 4, thread.setup),
    SysEnt.init("thread_self", 0, thread.self),
    SysEnt.init("thread_yield", 0, thread.yield),
    SysEnt.init("thread_suspend", 1, thread.@"suspend"),
    SysEnt.init("thread_resume", 1, thread.@"resume"),
    SysEnt.init("thread_schedparam", 3, ffi.thread.schedparam),
    SysEnt.init("vm_allocate", 4, ffi.vm.allocate),
    SysEnt.init("vm_free", 2, ffi.vm.free),
    SysEnt.init("vm_attribute", 3, ffi.vm.attribute),
    SysEnt.init("vm_map", 4, ffi.vm.map),
    SysEnt.init("object_create", 2, ffi.object.create),
    SysEnt.init("object_destroy", 1, ffi.object.destroy),
    SysEnt.init("object_lookup", 2, ffi.object.lookup),
    SysEnt.init("msg_send", 3, ffi.msg.send),
    SysEnt.init("msg_receive", 3, ffi.msg.receive),
    SysEnt.init("msg_reply", 3, ffi.msg.reply),
    SysEnt.init("timer_sleep", 2, ffi.timer.sleep),
    SysEnt.init("timer_alarm", 2, ffi.timer.alarm),
    SysEnt.init("timer_periodic", 3, ffi.timer.periodic),
    SysEnt.init("timer_waitperiod", 0, ffi.timer.waitperiod),
    SysEnt.init("device_open", 3, ffi.device.open),
    SysEnt.init("device_close", 1, ffi.device.close),
    SysEnt.init("device_read", 4, ffi.device.read),
    SysEnt.init("device_write", 4, ffi.device.write),
    SysEnt.init("device_ioctl", 3, c.device_ioctl),
    SysEnt.init("mutex_init", 1, ffi.mutex.init),
    SysEnt.init("mutex_destroy", 1, ffi.mutex.destroy),
    SysEnt.init("mutex_lock", 1, ffi.mutex.lock),
    SysEnt.init("mutex_trylock", 1, ffi.mutex.tryLock),
    SysEnt.init("mutex_unlock", 1, ffi.mutex.unlock),
    SysEnt.init("cond_init", 1, ffi.cond.init),
    SysEnt.init("cond_destroy", 1, ffi.cond.destroy),
    SysEnt.init("cond_wait", 2, ffi.cond.wait),
    SysEnt.init("cond_signal", 1, ffi.cond.signal),
    SysEnt.init("cond_broadcast", 1, ffi.cond.broadcast),
    SysEnt.init("sem_init", 2, ffi.sem.init),
    SysEnt.init("sem_destroy", 1, ffi.sem.destroy),
    SysEnt.init("sem_wait", 2, ffi.sem.wait),
    SysEnt.init("sem_trywait", 1, ffi.sem.tryWait),
    SysEnt.init("sem_post", 1, ffi.sem.post),
    SysEnt.init("sem_getvalue", 2, ffi.sem.getValue),
    SysEnt.init("sys_log", 1, ffi.system.log),
    SysEnt.init("sys_panic", 1, ffi.system.panic),
    SysEnt.init("sys_info", 2, ffi.system.info),
    SysEnt.init("sys_time", 1, ffi.system.time),
    SysEnt.init("sys_debug", 2, ffi.system.debug),
    SysEnt.init("device_gather_read", 4, c.device_gather_read),
    SysEnt.init("device_scatter_write", 4, c.device_scatter_write),
};

fn syscall_handler_std(a1: kern.Register, a2: kern.Register, a3: kern.Register, a4: kern.Register, id: kern.Register) callconv(.c) kern.Register {
    var retval: kern.Register = kern.Errno.EINVAL;

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

fn syscall_handler_armv8m(regs: *hal.CpuRegs, id: kern.Register) callconv(.c) kern.Register {
    var retval: kern.Register = kern.Errno.EINVAL;

    if (kutil.get_curthread()) |cur| {
        cur.*.ctx.uregs = regs;
    }

    const r0: kern.Register = @intCast(regs.r0);
    const r1: kern.Register = @intCast(regs.r1);
    const r2: kern.Register = @intCast(regs.r2);
    const r3: kern.Register = @intCast(regs.r3);

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

fn strace_entry(a1: kern.Register, a2: kern.Register, a3: kern.Register, a4: kern.Register, id: kern.Register) void {
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

fn strace_return(retval: kern.Register, id: kern.Register) void {
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
