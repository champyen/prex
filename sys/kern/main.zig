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

// Unified root for the Prex+ kernel.
//
// This file is the single compilation unit for all kernel .zig modules
// under sys/kern, sys/ipc, sys/sync, and sys/mem. Other .zig files are
// imported here via @import so the Zig compiler sees the whole kernel
// as one translation unit, enabling cross-module inlining, dead code
// elimination, and comptime validation.
//
// Every C-ABI symbol that was previously @export'd from each module's
// per-file root is consolidated here. The @comptime { if (@import("root")
// == @This()) { ... } } guards that used to be at the end of each file
// have been removed.

const std = @import("std");

const c = @import("c").c;
const ffi = @import("ffi");

// Single-import the whole kernel. Each module is wired in via a
// separate --dep module declaration in the build system so that the
// Zig compiler can resolve cross-directory imports under one root.
// (deadlock remains C - see sys/kern/deadlock.c)
const device = @import("device_mod");
const exception = @import("exception_mod");
const irq = @import("irq_mod");
const sched = @import("sched_mod");
const smp = @import("smp_mod");
const sysent = @import("sysent_mod");
const system = @import("system_mod");
const task = @import("task_mod");
const thread = @import("thread_mod");
const timer = @import("timer_mod");
const object = @import("object_mod");
const msg = @import("msg_mod");
const cond = @import("cond_mod");
const mutex = @import("mutex_mod");
const sem = @import("sem_mod");
const kmem = @import("kmem_mod");
const page = @import("page_mod");
const vm = @import("vm_mod");

// Local namespace aliases for the FFI helpers used by main().
const hal = ffi.hal;
const lib = ffi.lib;
const kern = ffi.kern;
const deadlock = ffi.deadlock;

extern fn wrap_get_version() callconv(.c) [*c]const u8;
extern fn wrap_get_machine() callconv(.c) [*c]const u8;
extern fn wrap_get_build_date() callconv(.c) [*c]const u8;

fn main() callconv(.c) c_int {
    if (@hasDecl(c, "CONFIG_SMP")) {
        smp.initEarly();
    }

    sched.lock();
    hal.diag_init();
    _ = lib.printf("Prex+ version %s for %s (%s)\n", wrap_get_version(), wrap_get_machine(), wrap_get_build_date());
    _ = lib.printf("Copyright (c) 2005-2009 Kohsuke Ohtani\n");
    _ = lib.printf("Copyright (c) 2021      Champ Yen (champ.yen@gmail.com)\n");

    page.init();
    kmem.init();

    hal.machine_startup();

    vm.init();
    deadlock.init();
    task.init();
    thread.init();
    sched.init();
    exception.init();
    timer.init();
    object.init();
    msg.init();

    irq.init();
    hal.clock_init();
    device.init();

    task.bootstrap();

    if (@hasDecl(c, "CONFIG_SMP")) {
        smp.startAps();
        smp.activate();
    }

    sched.unlock();
    thread.idle();

    return 0;
}

// ============================================================================
// C-ABI exports - consolidated from all kernel modules
// ============================================================================

comptime {
    // ---- main ----
    @export(&main, .{ .name = "main", .linkage = .strong });

    // ---- device ----
    @export(&device.open, .{ .name = "device_open", .linkage = .strong });
    @export(&device.close, .{ .name = "device_close", .linkage = .strong });
    @export(&device.read, .{ .name = "device_read", .linkage = .strong });
    @export(&device.write, .{ .name = "device_write", .linkage = .strong });
    @export(&device.gatherRead, .{ .name = "device_gather_read", .linkage = .strong });
    @export(&device.scatterWrite, .{ .name = "device_scatter_write", .linkage = .strong });
    @export(&device.ioctl, .{ .name = "device_ioctl", .linkage = .strong });
    @export(&device.info, .{ .name = "device_info", .linkage = .strong });
    @export(&device.init, .{ .name = "device_init", .linkage = .strong });

    // ---- exception ----
    @export(&exception.setup, .{ .name = "exception_setup", .linkage = .strong });
    @export(&exception.raise, .{ .name = "exception_raise", .linkage = .strong });
    @export(&exception.post, .{ .name = "exception_post", .linkage = .strong });
    @export(&exception.wait, .{ .name = "exception_wait", .linkage = .strong });
    @export(&exception.mark, .{ .name = "exception_mark", .linkage = .strong });
    @export(&exception.deliver, .{ .name = "exception_deliver", .linkage = .strong });
    @export(&exception.@"return", .{ .name = "exception_return", .linkage = .strong });
    @export(&exception.init, .{ .name = "exception_init", .linkage = .strong });

    // ---- irq ----
    @export(&irq.attach, .{ .name = "irq_attach", .linkage = .strong });
    @export(&irq.detach, .{ .name = "irq_detach", .linkage = .strong });
    @export(&irq.handler, .{ .name = "irq_handler", .linkage = .strong });
    @export(&irq.info, .{ .name = "irq_info", .linkage = .strong });
    @export(&irq.init, .{ .name = "irq_init", .linkage = .strong });

    // ---- sched ----
    @export(&sched.sleep_timeout, .{ .name = "sleep_timeout", .linkage = .strong });
    @export(&sched.dpc_thread, .{ .name = "dpc_thread", .linkage = .strong });
    @export(&sched.wakeq_flush, .{ .name = "wakeq_flush", .linkage = .strong });
    @export(&sched.setrun, .{ .name = "sched_setrun", .linkage = .strong });
    @export(&sched.swtch, .{ .name = "sched_swtch", .linkage = .strong });
    @export(&sched.tsleep, .{ .name = "sched_tsleep", .linkage = .strong });
    @export(&sched.wakeup, .{ .name = "sched_wakeup", .linkage = .strong });
    @export(&sched.wakeone, .{ .name = "sched_wakeone", .linkage = .strong });
    @export(&sched.unsleep, .{ .name = "sched_unsleep", .linkage = .strong });
    @export(&sched.yield, .{ .name = "sched_yield", .linkage = .strong });
    @export(&sched.@"suspend", .{ .name = "sched_suspend", .linkage = .strong });
    @export(&sched.@"resume", .{ .name = "sched_resume", .linkage = .strong });
    @export(&sched.tick, .{ .name = "sched_tick", .linkage = .strong });
    @export(&sched.start, .{ .name = "sched_start", .linkage = .strong });
    @export(&sched.stop, .{ .name = "sched_stop", .linkage = .strong });
    @export(&sched.lock, .{ .name = "sched_lock", .linkage = .strong });
    @export(&sched.unlock, .{ .name = "sched_unlock", .linkage = .strong });
    @export(&sched.bklUnlock, .{ .name = "sched_bkl_unlock", .linkage = .strong });
    @export(&sched.getpri, .{ .name = "sched_getpri", .linkage = .strong });
    @export(&sched.setpri, .{ .name = "sched_setpri", .linkage = .strong });
    @export(&sched.getpolicy, .{ .name = "sched_getpolicy", .linkage = .strong });
    @export(&sched.setpolicy, .{ .name = "sched_setpolicy", .linkage = .strong });
    @export(&sched.dpc, .{ .name = "sched_dpc", .linkage = .strong });
    @export(&sched.init, .{ .name = "sched_init", .linkage = .strong });

    // ---- smp (vars always needed for C-side refs; fns only when SMP) ----
    @export(&smp.cpu_table, .{ .name = "cpu_table", .linkage = .strong });
    @export(&smp.ap_boot_stacks, .{ .name = "ap_boot_stacks", .linkage = .strong });
    if (@hasDecl(c, "CONFIG_SMP")) {
        @export(&smp.initEarly, .{ .name = "smp_init_early", .linkage = .strong });
        @export(&smp.hal_set_cpu_control, .{ .name = "hal_set_cpu_control", .linkage = .strong });
        @export(&smp.hal_get_cpu_control, .{ .name = "hal_get_cpu_control", .linkage = .strong });
        @export(&smp.startAps, .{ .name = "smp_start_aps", .linkage = .strong });
        @export(&smp.activate, .{ .name = "smp_activate", .linkage = .strong });
        @export(&smp.apBoot, .{ .name = "smp_ap_boot", .linkage = .strong });
    }

    // ---- sysent (arch-conditional syscall handler) ----
    if (@hasDecl(c, "CONFIG_ARMV8M")) {
        @export(&sysent.syscall_handler_armv8m, .{ .name = "syscall_handler", .linkage = .strong });
    } else {
        @export(&sysent.syscall_handler_std, .{ .name = "syscall_handler", .linkage = .strong });
    }

    // ---- system ----
    @export(&system.sysinfo, .{ .name = "sysinfo", .linkage = .strong });
    @export(&system.sysInfo, .{ .name = "sys_info", .linkage = .strong });
    @export(&system.sysLog, .{ .name = "sys_log", .linkage = .strong });
    @export(&system.sysDebug, .{ .name = "sys_debug", .linkage = .strong });
    @export(&system.sysPanic, .{ .name = "sys_panic", .linkage = .strong });
    @export(&system.sysTime, .{ .name = "sys_time", .linkage = .strong });
    @export(&system.sysNosys, .{ .name = "sys_nosys", .linkage = .strong });

    // ---- task ----
    @export(&task.kernel_task, .{ .name = "kernel_task", .linkage = .strong });
    @export(&task.create, .{ .name = "task_create", .linkage = .strong });
    @export(&task.terminate, .{ .name = "task_terminate", .linkage = .strong });
    @export(&task.self, .{ .name = "task_self", .linkage = .strong });
    @export(&task.@"suspend", .{ .name = "task_suspend", .linkage = .strong });
    @export(&task.@"resume", .{ .name = "task_resume", .linkage = .strong });
    @export(&task.setname, .{ .name = "task_setname", .linkage = .strong });
    @export(&task.setcap, .{ .name = "task_setcap", .linkage = .strong });
    @export(&task.chkcap, .{ .name = "task_chkcap", .linkage = .strong });
    @export(&task.capable, .{ .name = "task_capable", .linkage = .strong });
    @export(&task.valid, .{ .name = "task_valid", .linkage = .strong });
    @export(&task.access, .{ .name = "task_access", .linkage = .strong });
    @export(&task.info, .{ .name = "task_info", .linkage = .strong });
    @export(&task.bootstrap, .{ .name = "task_bootstrap", .linkage = .strong });
    @export(&task.init, .{ .name = "task_init", .linkage = .strong });

    // ---- thread ----
    @export(&thread.idle_thread, .{ .name = "idle_thread", .linkage = .strong });
    if (!@hasDecl(c, "CONFIG_SMP")) {
        @export(&thread.curthread, .{ .name = "curthread", .linkage = .strong });
        @export(&thread.irq_nesting, .{ .name = "irq_nesting", .linkage = .strong });
        @export(&thread.curspl, .{ .name = "curspl", .linkage = .strong });
    }
    @export(&thread.create, .{ .name = "thread_create", .linkage = .strong });
    @export(&thread.terminate, .{ .name = "thread_terminate", .linkage = .strong });
    @export(&thread.destroy, .{ .name = "thread_destroy", .linkage = .strong });
    @export(&thread.setup, .{ .name = "thread_setup", .linkage = .strong });
    @export(&thread.self, .{ .name = "thread_self", .linkage = .strong });
    @export(&thread.valid, .{ .name = "thread_valid", .linkage = .strong });
    @export(&thread.yield, .{ .name = "thread_yield", .linkage = .strong });
    @export(&thread.@"suspend", .{ .name = "thread_suspend", .linkage = .strong });
    @export(&thread.@"resume", .{ .name = "thread_resume", .linkage = .strong });
    @export(&thread.schedparam, .{ .name = "thread_schedparam", .linkage = .strong });
    @export(&thread.idle, .{ .name = "thread_idle", .linkage = .strong });
    @export(&thread.info, .{ .name = "thread_info", .linkage = .strong });
    @export(&thread.createKernel, .{ .name = "kthread_create", .linkage = .strong });
    @export(&thread.terminateKernel, .{ .name = "kthread_terminate", .linkage = .strong });
    @export(&thread.createIdle, .{ .name = "thread_create_idle", .linkage = .strong });

    // ---- timer ----
    @export(&timer.stop, .{ .name = "timer_stop", .linkage = .strong });
    @export(&timer.callout, .{ .name = "timer_callout", .linkage = .strong });
    @export(&timer.delay, .{ .name = "timer_delay", .linkage = .strong });
    @export(&timer.sleep, .{ .name = "timer_sleep", .linkage = .strong });
    @export(&timer.alarm, .{ .name = "timer_alarm", .linkage = .strong });
    @export(&timer.periodic, .{ .name = "timer_periodic", .linkage = .strong });
    @export(&timer.waitperiod, .{ .name = "timer_waitperiod", .linkage = .strong });
    @export(&timer.cancel, .{ .name = "timer_cancel", .linkage = .strong });
    @export(&timer.handler, .{ .name = "timer_handler", .linkage = .strong });
    @export(&timer.ticks, .{ .name = "timer_ticks", .linkage = .strong });
    @export(&timer.info, .{ .name = "timer_info", .linkage = .strong });
    @export(&timer.init, .{ .name = "timer_init", .linkage = .strong });
    if (@hasDecl(c, "CONFIG_SMP")) {
        @export(&timer.__broken_spinlock_lock, .{ .name = "__broken_spinlock_lock", .linkage = .strong });
        @export(&timer.__broken_spinlock_unlock, .{ .name = "__broken_spinlock_unlock", .linkage = .strong });
    }

    // ---- object ----
    @export(&object.create, .{ .name = "object_create", .linkage = .strong });
    @export(&object.lookup, .{ .name = "object_lookup", .linkage = .strong });
    @export(&object.valid, .{ .name = "object_valid", .linkage = .strong });
    @export(&object.destroy, .{ .name = "object_destroy", .linkage = .strong });
    @export(&object.cleanup, .{ .name = "object_cleanup", .linkage = .strong });
    @export(&object.init, .{ .name = "object_init", .linkage = .strong });

    // ---- msg ----
    @export(&msg.send, .{ .name = "msg_send", .linkage = .strong });
    @export(&msg.receive, .{ .name = "msg_receive", .linkage = .strong });
    @export(&msg.reply, .{ .name = "msg_reply", .linkage = .strong });
    @export(&msg.cancel, .{ .name = "msg_cancel", .linkage = .strong });
    @export(&msg.abort, .{ .name = "msg_abort", .linkage = .strong });
    @export(&msg.init, .{ .name = "msg_init", .linkage = .strong });

    // ---- cond ----
    @export(&cond.init, .{ .name = "cond_init", .linkage = .strong });
    @export(&cond.destroy, .{ .name = "cond_destroy", .linkage = .strong });
    @export(&cond.cleanup, .{ .name = "cond_cleanup", .linkage = .strong });
    @export(&cond.wait, .{ .name = "cond_wait", .linkage = .strong });
    @export(&cond.signal, .{ .name = "cond_signal", .linkage = .strong });
    @export(&cond.broadcast, .{ .name = "cond_broadcast", .linkage = .strong });

    // ---- mutex ----
    @export(&mutex.init, .{ .name = "mutex_init", .linkage = .strong });
    @export(&mutex.destroy, .{ .name = "mutex_destroy", .linkage = .strong });
    @export(&mutex.cleanup, .{ .name = "mutex_cleanup", .linkage = .strong });
    @export(&mutex.lock, .{ .name = "mutex_lock", .linkage = .strong });
    @export(&mutex.tryLock, .{ .name = "mutex_trylock", .linkage = .strong });
    @export(&mutex.unlock, .{ .name = "mutex_unlock", .linkage = .strong });
    @export(&mutex.cancel, .{ .name = "mutex_cancel", .linkage = .strong });
    @export(&mutex.setpri, .{ .name = "mutex_setpri", .linkage = .strong });

    // ---- sem ----
    @export(&sem.init, .{ .name = "sem_init", .linkage = .strong });
    @export(&sem.destroy, .{ .name = "sem_destroy", .linkage = .strong });
    @export(&sem.wait, .{ .name = "sem_wait", .linkage = .strong });
    @export(&sem.tryWait, .{ .name = "sem_trywait", .linkage = .strong });
    @export(&sem.post, .{ .name = "sem_post", .linkage = .strong });
    @export(&sem.postKernel, .{ .name = "ksem_post", .linkage = .strong });
    @export(&sem.getValue, .{ .name = "sem_getvalue", .linkage = .strong });
    @export(&sem.cleanup, .{ .name = "sem_cleanup", .linkage = .strong });

    // ---- kmem ----
    @export(&kmem.alloc, .{ .name = "kmem_alloc", .linkage = .strong });
    @export(&kmem.free, .{ .name = "kmem_free", .linkage = .strong });
    @export(&kmem.map, .{ .name = "kmem_map", .linkage = .strong });
    @export(&kmem.init, .{ .name = "kmem_init", .linkage = .strong });

    // ---- page ----
    @export(&page.alloc, .{ .name = "page_alloc", .linkage = .strong });
    @export(&page.free, .{ .name = "page_free", .linkage = .strong });
    @export(&page.reserve, .{ .name = "page_reserve", .linkage = .strong });
    @export(&page.info, .{ .name = "page_info", .linkage = .strong });
    @export(&page.init, .{ .name = "page_init", .linkage = .strong });

    // ---- vm (either vm.zig or vm_nommu.zig) ----
    @export(&vm.create, .{ .name = "vm_create", .linkage = .strong });
    @export(&vm.allocate, .{ .name = "vm_allocate", .linkage = .strong });
    @export(&vm.free, .{ .name = "vm_free", .linkage = .strong });
    @export(&vm.attribute, .{ .name = "vm_attribute", .linkage = .strong });
    @export(&vm.map, .{ .name = "vm_map", .linkage = .strong });
    @export(&vm.terminate, .{ .name = "vm_terminate", .linkage = .strong });
    @export(&vm.dup, .{ .name = "vm_dup", .linkage = .strong });
    @export(&vm.@"switch", .{ .name = "vm_switch", .linkage = .strong });
    @export(&vm.reference, .{ .name = "vm_reference", .linkage = .strong });
    @export(&vm.load, .{ .name = "vm_load", .linkage = .strong });
    @export(&vm.translate, .{ .name = "vm_translate", .linkage = .strong });
    @export(&vm.info, .{ .name = "vm_info", .linkage = .strong });
    @export(&vm.init, .{ .name = "vm_init", .linkage = .strong });
}
