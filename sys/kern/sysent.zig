// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
// OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
// HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
// LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
// OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
// SUCH DAMAGE.

const std = @import("std");
const builtin = @import("builtin");
const c = @import("c").c;

const ffi = @import("ffi");
const cond = ffi.cond;
const device = ffi.device;
const exception = ffi.exception;
const hal = ffi.hal;
const kern = ffi.kern;
const kutil = ffi.kutil;
const lib = ffi.lib;
const msg = ffi.msg;
const mutex = ffi.mutex;
const object = ffi.object;
const sem = ffi.sem;
const system = ffi.system;
const task = ffi.task;
const thread = ffi.thread;
const timer = ffi.timer;
const vm = ffi.vm;
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
    SysEnt.init("exception_return", 0, exception.@"return"),
    SysEnt.init("exception_setup", 1, exception.setup),
    SysEnt.init("exception_raise", 2, exception.raise),
    SysEnt.init("exception_wait", 1, exception.wait),
    SysEnt.init("task_create", 3, task.create),
    SysEnt.init("task_terminate", 1, task.terminate),
    SysEnt.init("task_self", 0, task.self),
    SysEnt.init("task_suspend", 1, task.@"suspend"),
    SysEnt.init("task_resume", 1, task.@"resume"),
    SysEnt.init("task_setname", 2, task.setname),
    SysEnt.init("task_setcap", 2, task.setcap),
    SysEnt.init("task_chkcap", 2, task.chkcap),
    SysEnt.init("thread_create", 2, thread.create),
    SysEnt.init("thread_terminate", 1, thread.terminate),
    SysEnt.init("thread_setup", 4, thread.setup),
    SysEnt.init("thread_self", 0, thread.self),
    SysEnt.init("thread_yield", 0, thread.yield),
    SysEnt.init("thread_suspend", 1, thread.@"suspend"),
    SysEnt.init("thread_resume", 1, thread.@"resume"),
    SysEnt.init("thread_schedparam", 3, thread.schedparam),
    SysEnt.init("vm_allocate", 4, vm.allocate),
    SysEnt.init("vm_free", 2, vm.free),
    SysEnt.init("vm_attribute", 3, vm.attribute),
    SysEnt.init("vm_map", 4, vm.map),
    SysEnt.init("object_create", 2, object.create),
    SysEnt.init("object_destroy", 1, object.destroy),
    SysEnt.init("object_lookup", 2, object.lookup),
    SysEnt.init("msg_send", 3, msg.send),
    SysEnt.init("msg_receive", 3, msg.receive),
    SysEnt.init("msg_reply", 3, msg.reply),
    SysEnt.init("timer_sleep", 2, timer.sleep),
    SysEnt.init("timer_alarm", 2, timer.alarm),
    SysEnt.init("timer_periodic", 3, timer.periodic),
    SysEnt.init("timer_waitperiod", 0, timer.waitperiod),
    SysEnt.init("device_open", 3, device.open),
    SysEnt.init("device_close", 1, device.close),
    SysEnt.init("device_read", 4, device.read),
    SysEnt.init("device_write", 4, device.write),
    SysEnt.init("device_ioctl", 3, c.device_ioctl),
    SysEnt.init("mutex_init", 1, mutex.init),
    SysEnt.init("mutex_destroy", 1, mutex.destroy),
    SysEnt.init("mutex_lock", 1, mutex.lock),
    SysEnt.init("mutex_trylock", 1, mutex.tryLock),
    SysEnt.init("mutex_unlock", 1, mutex.unlock),
    SysEnt.init("cond_init", 1, cond.init),
    SysEnt.init("cond_destroy", 1, cond.destroy),
    SysEnt.init("cond_wait", 2, cond.wait),
    SysEnt.init("cond_signal", 1, cond.signal),
    SysEnt.init("cond_broadcast", 1, cond.broadcast),
    SysEnt.init("sem_init", 2, sem.init),
    SysEnt.init("sem_destroy", 1, sem.destroy),
    SysEnt.init("sem_wait", 2, sem.wait),
    SysEnt.init("sem_trywait", 1, sem.tryWait),
    SysEnt.init("sem_post", 1, sem.post),
    SysEnt.init("sem_getvalue", 2, sem.getValue),
    SysEnt.init("sys_log", 1, system.log),
    SysEnt.init("sys_panic", 1, system.panic),
    SysEnt.init("sys_info", 2, system.info),
    SysEnt.init("sys_time", 1, system.time),
    SysEnt.init("sys_debug", 2, system.debug),
    SysEnt.init("device_gather_read", 4, c.device_gather_read),
    SysEnt.init("device_scatter_write", 4, c.device_scatter_write),
};

pub fn syscall_handler_std(a1: kern.Register, a2: kern.Register, a3: kern.Register, a4: kern.Register, id: kern.Register) callconv(.c) kern.Register {
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

pub fn syscall_handler_armv8m(regs: *hal.CpuRegs, id: kern.Register) callconv(.c) kern.Register {
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

