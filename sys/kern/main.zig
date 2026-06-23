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
const device_mod = @import("device_mod");
const exception_mod = @import("exception_mod");
const irq_mod = @import("irq_mod");
const sched_mod = @import("sched_mod");
const smp_mod = @import("smp_mod");
const sysent_mod = @import("sysent_mod");
const system_mod = @import("system_mod");
const task_mod = @import("task_mod");
const thread_mod = @import("thread_mod");
const timer_mod = @import("timer_mod");
const object_mod = @import("object_mod");
const msg_mod = @import("msg_mod");
const cond_mod = @import("cond_mod");
const mutex_mod = @import("mutex_mod");
const sem_mod = @import("sem_mod");
const kmem_mod = @import("kmem_mod");
const page_mod = @import("page_mod");
const vm_mod = @import("vm_mod");

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
        smp_mod.initEarly();
    }

    sched_mod.lock();
    hal.diag_init();
    _ = lib.printf("Prex+ version %s for %s (%s)\n", wrap_get_version(), wrap_get_machine(), wrap_get_build_date());
    _ = lib.printf("Copyright (c) 2005-2009 Kohsuke Ohtani\n");
    _ = lib.printf("Copyright (c) 2021      Champ Yen (champ.yen@gmail.com)\n");

    page_mod.init();
    kmem_mod.init();

    hal.machine_startup();

    vm_mod.init();
    deadlock.init();
    task_mod.init();
    thread_mod.init();
    sched_mod.init();
    exception_mod.init();
    timer_mod.init();
    object_mod.init();
    msg_mod.init();

    irq_mod.init();
    hal.clock_init();
    device_mod.init();

    task_mod.bootstrap();

    if (@hasDecl(c, "CONFIG_SMP")) {
        smp_mod.startAps();
        smp_mod.activate();
    }

    sched_mod.unlock();
    thread_mod.idle();

    return 0;
}

// ============================================================================
// C-ABI exports - consolidated from all kernel modules
// ============================================================================

comptime {
    // ---- main ----
    @export(&main, .{ .name = "main", .linkage = .strong });

    // ---- device ----
    @export(&device_mod.open, .{ .name = "device_open", .linkage = .strong });
    @export(&device_mod.close, .{ .name = "device_close", .linkage = .strong });
    @export(&device_mod.read, .{ .name = "device_read", .linkage = .strong });
    @export(&device_mod.write, .{ .name = "device_write", .linkage = .strong });
    @export(&device_mod.gatherRead, .{ .name = "device_gather_read", .linkage = .strong });
    @export(&device_mod.scatterWrite, .{ .name = "device_scatter_write", .linkage = .strong });
    @export(&device_mod.ioctl, .{ .name = "device_ioctl", .linkage = .strong });
    @export(&device_mod.info, .{ .name = "device_info", .linkage = .strong });
    @export(&device_mod.init, .{ .name = "device_init", .linkage = .strong });

    // ---- exception ----
    @export(&exception_mod.setup, .{ .name = "exception_setup", .linkage = .strong });
    @export(&exception_mod.raise, .{ .name = "exception_raise", .linkage = .strong });
    @export(&exception_mod.post, .{ .name = "exception_post", .linkage = .strong });
    @export(&exception_mod.wait, .{ .name = "exception_wait", .linkage = .strong });
    @export(&exception_mod.mark, .{ .name = "exception_mark", .linkage = .strong });
    @export(&exception_mod.deliver, .{ .name = "exception_deliver", .linkage = .strong });
    @export(&exception_mod.@"return", .{ .name = "exception_return", .linkage = .strong });
    @export(&exception_mod.init, .{ .name = "exception_init", .linkage = .strong });

    // ---- irq ----
    @export(&irq_mod.attach, .{ .name = "irq_attach", .linkage = .strong });
    @export(&irq_mod.detach, .{ .name = "irq_detach", .linkage = .strong });
    @export(&irq_mod.handler, .{ .name = "irq_handler", .linkage = .strong });
    @export(&irq_mod.info, .{ .name = "irq_info", .linkage = .strong });
    @export(&irq_mod.init, .{ .name = "irq_init", .linkage = .strong });

    // ---- sched ----
    @export(&sched_mod.sleep_timeout, .{ .name = "sleep_timeout", .linkage = .strong });
    @export(&sched_mod.dpc_thread, .{ .name = "dpc_thread", .linkage = .strong });
    @export(&sched_mod.wakeq_flush, .{ .name = "wakeq_flush", .linkage = .strong });
    @export(&sched_mod.setrun, .{ .name = "sched_setrun", .linkage = .strong });
    @export(&sched_mod.swtch, .{ .name = "sched_swtch", .linkage = .strong });
    @export(&sched_mod.tsleep, .{ .name = "sched_tsleep", .linkage = .strong });
    @export(&sched_mod.wakeup, .{ .name = "sched_wakeup", .linkage = .strong });
    @export(&sched_mod.wakeone, .{ .name = "sched_wakeone", .linkage = .strong });
    @export(&sched_mod.unsleep, .{ .name = "sched_unsleep", .linkage = .strong });
    @export(&sched_mod.yield, .{ .name = "sched_yield", .linkage = .strong });
    @export(&sched_mod.@"suspend", .{ .name = "sched_suspend", .linkage = .strong });
    @export(&sched_mod.@"resume", .{ .name = "sched_resume", .linkage = .strong });
    @export(&sched_mod.tick, .{ .name = "sched_tick", .linkage = .strong });
    @export(&sched_mod.start, .{ .name = "sched_start", .linkage = .strong });
    @export(&sched_mod.stop, .{ .name = "sched_stop", .linkage = .strong });
    @export(&sched_mod.lock, .{ .name = "sched_lock", .linkage = .strong });
    @export(&sched_mod.unlock, .{ .name = "sched_unlock", .linkage = .strong });
    @export(&sched_mod.bklUnlock, .{ .name = "sched_bkl_unlock", .linkage = .strong });
    @export(&sched_mod.getpri, .{ .name = "sched_getpri", .linkage = .strong });
    @export(&sched_mod.setpri, .{ .name = "sched_setpri", .linkage = .strong });
    @export(&sched_mod.getpolicy, .{ .name = "sched_getpolicy", .linkage = .strong });
    @export(&sched_mod.setpolicy, .{ .name = "sched_setpolicy", .linkage = .strong });
    @export(&sched_mod.dpc, .{ .name = "sched_dpc", .linkage = .strong });
    @export(&sched_mod.init, .{ .name = "sched_init", .linkage = .strong });

    // ---- smp (vars always needed for C-side refs; fns only when SMP) ----
    @export(&smp_mod.cpu_table, .{ .name = "cpu_table", .linkage = .strong });
    @export(&smp_mod.ap_boot_stacks, .{ .name = "ap_boot_stacks", .linkage = .strong });
    if (@hasDecl(c, "CONFIG_SMP")) {
        @export(&smp_mod.initEarly, .{ .name = "smp_init_early", .linkage = .strong });
        @export(&smp_mod.hal_set_cpu_control, .{ .name = "hal_set_cpu_control", .linkage = .strong });
        @export(&smp_mod.hal_get_cpu_control, .{ .name = "hal_get_cpu_control", .linkage = .strong });
        @export(&smp_mod.startAps, .{ .name = "smp_start_aps", .linkage = .strong });
        @export(&smp_mod.activate, .{ .name = "smp_activate", .linkage = .strong });
        @export(&smp_mod.apBoot, .{ .name = "smp_ap_boot", .linkage = .strong });
    }

    // ---- sysent (arch-conditional syscall handler) ----
    if (@hasDecl(c, "CONFIG_ARMV8M")) {
        @export(&sysent_mod.syscall_handler_armv8m, .{ .name = "syscall_handler", .linkage = .strong });
    } else {
        @export(&sysent_mod.syscall_handler_std, .{ .name = "syscall_handler", .linkage = .strong });
    }

    // ---- system ----
    @export(&system_mod.sysinfo, .{ .name = "sysinfo", .linkage = .strong });
    @export(&system_mod.sysInfo, .{ .name = "sys_info", .linkage = .strong });
    @export(&system_mod.sysLog, .{ .name = "sys_log", .linkage = .strong });
    @export(&system_mod.sysDebug, .{ .name = "sys_debug", .linkage = .strong });
    @export(&system_mod.sysPanic, .{ .name = "sys_panic", .linkage = .strong });
    @export(&system_mod.sysTime, .{ .name = "sys_time", .linkage = .strong });
    @export(&system_mod.sysNosys, .{ .name = "sys_nosys", .linkage = .strong });

    // ---- task ----
    @export(&task_mod.kernel_task, .{ .name = "kernel_task", .linkage = .strong });
    @export(&task_mod.create, .{ .name = "task_create", .linkage = .strong });
    @export(&task_mod.terminate, .{ .name = "task_terminate", .linkage = .strong });
    @export(&task_mod.self, .{ .name = "task_self", .linkage = .strong });
    @export(&task_mod.@"suspend", .{ .name = "task_suspend", .linkage = .strong });
    @export(&task_mod.@"resume", .{ .name = "task_resume", .linkage = .strong });
    @export(&task_mod.setname, .{ .name = "task_setname", .linkage = .strong });
    @export(&task_mod.setcap, .{ .name = "task_setcap", .linkage = .strong });
    @export(&task_mod.chkcap, .{ .name = "task_chkcap", .linkage = .strong });
    @export(&task_mod.capable, .{ .name = "task_capable", .linkage = .strong });
    @export(&task_mod.valid, .{ .name = "task_valid", .linkage = .strong });
    @export(&task_mod.access, .{ .name = "task_access", .linkage = .strong });
    @export(&task_mod.info, .{ .name = "task_info", .linkage = .strong });
    @export(&task_mod.bootstrap, .{ .name = "task_bootstrap", .linkage = .strong });
    @export(&task_mod.init, .{ .name = "task_init", .linkage = .strong });

    // ---- thread ----
    @export(&thread_mod.idle_thread, .{ .name = "idle_thread", .linkage = .strong });
    if (!@hasDecl(c, "CONFIG_SMP")) {
        @export(&thread_mod.curthread, .{ .name = "curthread", .linkage = .strong });
        @export(&thread_mod.irq_nesting, .{ .name = "irq_nesting", .linkage = .strong });
        @export(&thread_mod.curspl, .{ .name = "curspl", .linkage = .strong });
    }
    @export(&thread_mod.create, .{ .name = "thread_create", .linkage = .strong });
    @export(&thread_mod.terminate, .{ .name = "thread_terminate", .linkage = .strong });
    @export(&thread_mod.destroy, .{ .name = "thread_destroy", .linkage = .strong });
    @export(&thread_mod.setup, .{ .name = "thread_setup", .linkage = .strong });
    @export(&thread_mod.self, .{ .name = "thread_self", .linkage = .strong });
    @export(&thread_mod.valid, .{ .name = "thread_valid", .linkage = .strong });
    @export(&thread_mod.yield, .{ .name = "thread_yield", .linkage = .strong });
    @export(&thread_mod.@"suspend", .{ .name = "thread_suspend", .linkage = .strong });
    @export(&thread_mod.@"resume", .{ .name = "thread_resume", .linkage = .strong });
    @export(&thread_mod.schedparam, .{ .name = "thread_schedparam", .linkage = .strong });
    @export(&thread_mod.idle, .{ .name = "thread_idle", .linkage = .strong });
    @export(&thread_mod.info, .{ .name = "thread_info", .linkage = .strong });
    @export(&thread_mod.createKernel, .{ .name = "kthread_create", .linkage = .strong });
    @export(&thread_mod.terminateKernel, .{ .name = "kthread_terminate", .linkage = .strong });
    @export(&thread_mod.createIdle, .{ .name = "thread_create_idle", .linkage = .strong });

    // ---- timer ----
    @export(&timer_mod.stop, .{ .name = "timer_stop", .linkage = .strong });
    @export(&timer_mod.callout, .{ .name = "timer_callout", .linkage = .strong });
    @export(&timer_mod.delay, .{ .name = "timer_delay", .linkage = .strong });
    @export(&timer_mod.sleep, .{ .name = "timer_sleep", .linkage = .strong });
    @export(&timer_mod.alarm, .{ .name = "timer_alarm", .linkage = .strong });
    @export(&timer_mod.periodic, .{ .name = "timer_periodic", .linkage = .strong });
    @export(&timer_mod.waitperiod, .{ .name = "timer_waitperiod", .linkage = .strong });
    @export(&timer_mod.cancel, .{ .name = "timer_cancel", .linkage = .strong });
    @export(&timer_mod.handler, .{ .name = "timer_handler", .linkage = .strong });
    @export(&timer_mod.ticks, .{ .name = "timer_ticks", .linkage = .strong });
    @export(&timer_mod.info, .{ .name = "timer_info", .linkage = .strong });
    @export(&timer_mod.init, .{ .name = "timer_init", .linkage = .strong });
    if (@hasDecl(c, "CONFIG_SMP")) {
        @export(&timer_mod.__broken_spinlock_lock, .{ .name = "__broken_spinlock_lock", .linkage = .strong });
        @export(&timer_mod.__broken_spinlock_unlock, .{ .name = "__broken_spinlock_unlock", .linkage = .strong });
    }

    // ---- object ----
    @export(&object_mod.create, .{ .name = "object_create", .linkage = .strong });
    @export(&object_mod.lookup, .{ .name = "object_lookup", .linkage = .strong });
    @export(&object_mod.valid, .{ .name = "object_valid", .linkage = .strong });
    @export(&object_mod.destroy, .{ .name = "object_destroy", .linkage = .strong });
    @export(&object_mod.cleanup, .{ .name = "object_cleanup", .linkage = .strong });
    @export(&object_mod.init, .{ .name = "object_init", .linkage = .strong });

    // ---- msg ----
    @export(&msg_mod.send, .{ .name = "msg_send", .linkage = .strong });
    @export(&msg_mod.receive, .{ .name = "msg_receive", .linkage = .strong });
    @export(&msg_mod.reply, .{ .name = "msg_reply", .linkage = .strong });
    @export(&msg_mod.cancel, .{ .name = "msg_cancel", .linkage = .strong });
    @export(&msg_mod.abort, .{ .name = "msg_abort", .linkage = .strong });
    @export(&msg_mod.init, .{ .name = "msg_init", .linkage = .strong });

    // ---- cond ----
    @export(&cond_mod.init, .{ .name = "cond_init", .linkage = .strong });
    @export(&cond_mod.destroy, .{ .name = "cond_destroy", .linkage = .strong });
    @export(&cond_mod.cleanup, .{ .name = "cond_cleanup", .linkage = .strong });
    @export(&cond_mod.wait, .{ .name = "cond_wait", .linkage = .strong });
    @export(&cond_mod.signal, .{ .name = "cond_signal", .linkage = .strong });
    @export(&cond_mod.broadcast, .{ .name = "cond_broadcast", .linkage = .strong });

    // ---- mutex ----
    @export(&mutex_mod.init, .{ .name = "mutex_init", .linkage = .strong });
    @export(&mutex_mod.destroy, .{ .name = "mutex_destroy", .linkage = .strong });
    @export(&mutex_mod.cleanup, .{ .name = "mutex_cleanup", .linkage = .strong });
    @export(&mutex_mod.lock, .{ .name = "mutex_lock", .linkage = .strong });
    @export(&mutex_mod.tryLock, .{ .name = "mutex_trylock", .linkage = .strong });
    @export(&mutex_mod.unlock, .{ .name = "mutex_unlock", .linkage = .strong });
    @export(&mutex_mod.cancel, .{ .name = "mutex_cancel", .linkage = .strong });
    @export(&mutex_mod.setpri, .{ .name = "mutex_setpri", .linkage = .strong });

    // ---- sem ----
    @export(&sem_mod.init, .{ .name = "sem_init", .linkage = .strong });
    @export(&sem_mod.destroy, .{ .name = "sem_destroy", .linkage = .strong });
    @export(&sem_mod.wait, .{ .name = "sem_wait", .linkage = .strong });
    @export(&sem_mod.tryWait, .{ .name = "sem_trywait", .linkage = .strong });
    @export(&sem_mod.post, .{ .name = "sem_post", .linkage = .strong });
    @export(&sem_mod.postKernel, .{ .name = "ksem_post", .linkage = .strong });
    @export(&sem_mod.getValue, .{ .name = "sem_getvalue", .linkage = .strong });
    @export(&sem_mod.cleanup, .{ .name = "sem_cleanup", .linkage = .strong });

    // ---- kmem ----
    @export(&kmem_mod.alloc, .{ .name = "kmem_alloc", .linkage = .strong });
    @export(&kmem_mod.free, .{ .name = "kmem_free", .linkage = .strong });
    @export(&kmem_mod.map, .{ .name = "kmem_map", .linkage = .strong });
    @export(&kmem_mod.init, .{ .name = "kmem_init", .linkage = .strong });

    // ---- page ----
    @export(&page_mod.alloc, .{ .name = "page_alloc", .linkage = .strong });
    @export(&page_mod.free, .{ .name = "page_free", .linkage = .strong });
    @export(&page_mod.reserve, .{ .name = "page_reserve", .linkage = .strong });
    @export(&page_mod.info, .{ .name = "page_info", .linkage = .strong });
    @export(&page_mod.init, .{ .name = "page_init", .linkage = .strong });

    // ---- vm (either vm.zig or vm_nommu.zig) ----
    @export(&vm_mod.create, .{ .name = "vm_create", .linkage = .strong });
    @export(&vm_mod.allocate, .{ .name = "vm_allocate", .linkage = .strong });
    @export(&vm_mod.free, .{ .name = "vm_free", .linkage = .strong });
    @export(&vm_mod.attribute, .{ .name = "vm_attribute", .linkage = .strong });
    @export(&vm_mod.map, .{ .name = "vm_map", .linkage = .strong });
    @export(&vm_mod.terminate, .{ .name = "vm_terminate", .linkage = .strong });
    @export(&vm_mod.dup, .{ .name = "vm_dup", .linkage = .strong });
    @export(&vm_mod.@"switch", .{ .name = "vm_switch", .linkage = .strong });
    @export(&vm_mod.reference, .{ .name = "vm_reference", .linkage = .strong });
    @export(&vm_mod.load, .{ .name = "vm_load", .linkage = .strong });
    @export(&vm_mod.translate, .{ .name = "vm_translate", .linkage = .strong });
    @export(&vm_mod.info, .{ .name = "vm_info", .linkage = .strong });
    @export(&vm_mod.init, .{ .name = "vm_init", .linkage = .strong });
}
