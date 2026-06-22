const std = @import("std");
const c = @import("c").c;

pub const smp = struct {
    pub extern fn smp_init_early() callconv(.c) void;
    pub extern fn smp_start_aps() callconv(.c) void;
    pub extern fn smp_activate() callconv(.c) void;

    pub const init_early = smp_init_early;
    pub const start_aps = smp_start_aps;
    pub const activate = smp_activate;
    pub const get_cpu_control = c.hal_get_cpu_control;
};

pub const thread = struct {
    pub extern var curthread: c.thread_t;
    pub extern var idle_thread: c.struct_thread;

    pub const create_idle = c.thread_create_idle;
    pub const info = c.thread_info;
    pub const create = c.thread_create;
    pub const terminate = c.thread_terminate;
    pub const setup = c.thread_setup;
    pub const destroy = c.thread_destroy;
    pub const self = c.thread_self;
    pub const yield = c.thread_yield;
    pub const @"suspend" = c.thread_suspend;
    pub const @"resume" = c.thread_resume;
    pub const kcreate = c.kthread_create;
    pub const kterminate = c.kthread_terminate;
    pub const init = c.thread_init;
    pub const idle = c.thread_idle;
    pub const valid = c.thread_valid;
};

pub const sched = struct {
    pub const lock = c.sched_lock;
    pub const unlock = c.sched_unlock;
    pub const start = c.sched_start;
    pub const stop = c.sched_stop;
    pub const yield = c.sched_yield;
    pub const @"suspend" = c.sched_suspend;
    pub const @"resume" = c.sched_resume;
    pub const get_pri = c.sched_getpri;
    pub const set_pri = c.sched_setpri;
    pub const get_policy = c.sched_getpolicy;
    pub const set_policy = c.sched_setpolicy;
    pub fn tsleep(ev: *sync.Event, timeout: c_ulong) callconv(.c) c_int {
        return c.sched_tsleep(@ptrCast(ev), timeout);
    }
    pub fn wakeup(ev: *sync.Event) callconv(.c) void {
        c.sched_wakeup(@ptrCast(ev));
    }
    pub const unsleep = c.sched_unsleep;
    pub fn wakeone(ev: *sync.Event) callconv(.c) c.thread_t {
        return c.sched_wakeone(@ptrCast(ev));
    }
    pub const init = c.sched_init;
    pub const tick = c.sched_tick;
    pub const sleep = c.sched_sleep;
};

pub const kmem = struct {
    pub const alloc = c.kmem_alloc;
    pub const free = c.kmem_free;
    pub const map = c.kmem_map;
    pub const init = c.kmem_init;
};

pub const task = struct {
    pub const valid = c.task_valid;
    pub const access = c.task_access;
    pub const capable = c.task_capable;
    pub const init = c.task_init;
    pub const bootstrap = c.task_bootstrap;
    pub const info = c.task_info;
    pub const terminate = c.task_terminate;
    pub const create = c.task_create;
    pub const self = c.task_self;
    pub const @"suspend" = c.task_suspend;
    pub const @"resume" = c.task_resume;
};

pub const page = struct {
    pub const alloc = c.page_alloc;
    pub const free = c.page_free;
    pub const reserve = c.page_reserve;
    pub const init = c.page_init;
    pub const info = c.page_info;
};

pub const vm = struct {
    pub const create = c.vm_create;
    pub const terminate = c.vm_terminate;
    pub const dup = c.vm_dup;
    pub const reference = c.vm_reference;
    pub const translate = c.vm_translate;
    pub const load = c.vm_load;
    pub const init = c.vm_init;
    pub const info = c.vm_info;
    pub const switch_map = c.vm_switch;
};

pub const timer = struct {
    pub const callout = c.timer_callout;
    pub const stop = c.timer_stop;
    pub const init = c.timer_init;
    pub const cancel = c.timer_cancel;
    pub const info = c.timer_info;
    pub const ticks = c.timer_ticks;
    pub const hztoms = c.hztoms;
    pub const mstohz = c.mstohz;
};

pub const irq = struct {
    pub const attach = c.irq_attach;
    pub const detach = c.irq_detach;
    pub const init = c.irq_init;
    pub const info = c.irq_info;
};

pub const device = struct {
    pub const init = c.device_init;
    pub const info = c.device_info;
};

pub const exception = struct {
    pub const init = c.exception_init;
    pub const post = c.exception_post;
};

pub const object = struct {
    pub const valid = c.object_valid;
    pub const init = c.object_init;
    pub const cleanup = c.object_cleanup;
};

pub const msg = struct {
    pub const abort = c.msg_abort;
    pub const init = c.msg_init;
    pub const cancel = c.msg_cancel;
};

pub const deadlock = struct {
    pub const init = c.deadlock_init;
    pub const check_loop = c.deadlock_check_loop;
    pub const heartbeat = c.deadlock_heartbeat;
    pub const mutex_stop_wait = c.deadlock_mutex_stop_wait;
    pub const mutex_wait = c.deadlock_mutex_wait;
    pub const proactive_check = c.deadlock_proactive_check;
    pub const record_lock = c.deadlock_record_lock;
    pub const record_unlock = c.deadlock_record_unlock;
    pub const sleep = c.deadlock_sleep;
    pub const stop_sleep = c.deadlock_stop_sleep;
};

pub const mutex = struct {
    pub const lock = c.mutex_lock;
    pub const unlock = c.mutex_unlock;
    pub const cleanup = c.mutex_cleanup;
    pub const cancel = c.mutex_cancel;
    pub const setpri = c.mutex_setpri;
};

pub const cond = struct {
    pub const cleanup = c.cond_cleanup;
};

pub const sem = struct {
    pub const cleanup = c.sem_cleanup;
};

pub const Queue = @import("lib/queue.zig").Queue;

pub const lib = struct {
    pub const memcpy = c.memcpy;
    pub const memset = c.memset;
    pub const memmove = c.memmove;
    pub const strlen = c.strlen;
    pub const strnlen = c.strnlen;
    pub const strlcpy = c.strlcpy;
    pub const strncmp = c.strncmp;
    pub const printf = c.printf;
    pub const panic = c.panic;
};

pub const kutil = @import("lib/kutil.zig");
pub const List = @import("lib/list.zig").List;

pub const hal = struct {
    pub const machine_startup = c.machine_startup;
    pub const machine_idle = c.machine_idle;
    pub const machine_powerdown = c.machine_powerdown;
    pub const machine_reset = c.machine_reset;
    pub const machine_bootinfo = c.machine_bootinfo;
    pub const machine_abort = c.machine_abort;

    pub const clock_init = c.clock_init;
    pub const clock_ap_init = c.clock_ap_init;

    pub const diag_init = c.diag_init;
    pub const diag_puts = c.diag_puts;

    pub const interrupt_cpu_init = c.interrupt_cpu_init;
    pub const interrupt_init = c.interrupt_init;
    pub const interrupt_setup = c.interrupt_setup;
    pub const interrupt_mask = c.interrupt_mask;
    pub const interrupt_unmask = c.interrupt_unmask;

    pub const hal_cpu_id = c.hal_cpu_id;
    pub const hal_cpu_start = c.hal_cpu_start;

    pub const spl0 = c.spl0;
    pub const splhigh = c.splhigh;
    pub const splx = c.splx;

    pub const context_save = c.context_save;
    pub const context_restore = c.context_restore;
    pub const context_set = c.context_set;
    pub const context_switch = c.context_switch;

    pub const mmu_init = c.mmu_init;
    pub const mmu_map = c.mmu_map;
    pub const mmu_newmap = c.mmu_newmap;
    pub const mmu_switch = c.mmu_switch;
    pub const mmu_terminate = c.mmu_terminate;
    pub const mmu_extract = c.mmu_extract;

    pub const flush_cache = c.flush_cache;
    pub const dbgctl = c.dbgctl;
    pub const dump_backtrace = c.dump_backtrace;
    pub const zig_memory_barrier = c.zig_memory_barrier;

    pub const copyin = c.copyin;
    pub const copyout = c.copyout;
    pub const copyinstr = c.copyinstr;

    // Single canonical place for all c.struct_* type aliases.
    // These are direct aliases to the C struct types, used for
    // C-compatible function parameters and field types.
    pub const List = c.struct_list;
    pub const Queue = c.struct_queue;
    pub const Event = c.struct_event;
    pub const Mutex = c.struct_mutex;
    pub const Cond = c.struct_cond;
    pub const Sem = c.struct_sem;
    pub const Segment = c.struct_seg;
    pub const VmMap = c.struct_vm_map;
    pub const Thread = c.struct_thread;
    pub const Task = c.struct_task;
    pub const Device = c.struct_device;
    pub const IRQ = c.struct_irq;
    pub const Timer = c.struct_timer;
    pub const Driver = c.struct_driver;
    pub const DevOps = c.struct_devops;
    pub const DevIO = c.struct_dev_io;
    pub const BootInfo = c.struct_bootinfo;
    pub const MemInfo = c.struct_meminfo;
    pub const Module = c.struct_module;
    pub const Context = c.struct_context;
    pub const CpuRegs = c.struct_cpu_regs;
    pub const ThreadInfo = c.struct_threadinfo;
    pub const TaskInfo = c.struct_taskinfo;
    pub const VmInfo = c.struct_vminfo;
    pub const DeviceInfo = c.struct_devinfo;
    pub const IrqInfo = c.struct_irqinfo;
    pub const TimerInfo = c.struct_timerinfo;
    pub const RiscvCpu = c.struct_riscv_cpu;
    pub const KernInfo = c.struct_kerninfo;
    pub const Object = c.struct_object;
    pub const MsgHeader = c.struct_msg_header;
    pub const Dpc = c.struct_dpc;
    pub const CpuControl = c.struct_cpu_control;

    // Constants from sys/include/hal.h
    pub const CTX_KARG = c.CTX_KARG;
    pub const CTX_KENTRY = c.CTX_KENTRY;
    pub const CTX_KSTACK = c.CTX_KSTACK;
    pub const CTX_UARG = c.CTX_UARG;
    pub const CTX_UENTRY = c.CTX_UENTRY;
    pub const CTX_USTACK = c.CTX_USTACK;
    pub const IMODE_EDGE = c.IMODE_EDGE;
    pub const IMODE_LEVEL = c.IMODE_LEVEL;
    pub const INT_CONTINUE = c.INT_CONTINUE;
    pub const INT_DONE = c.INT_DONE;
    pub const NO_PGD = c.NO_PGD;
    pub const PG_READ = c.PG_READ;
    pub const PG_UNMAP = c.PG_UNMAP;
    pub const PG_WRITE = c.PG_WRITE;

    // Constants from include/sys/dbgctl.h and sys/include/debug.h
    pub const DBGC_FLUSHCACHE = c.DBGC_FLUSHCACHE;
    pub const DBGC_GETLOG = c.DBGC_GETLOG;
    pub const DBGC_LOGSIZE = c.DBGC_LOGSIZE;
    pub const DBGC_SAVEBT = c.DBGC_SAVEBT;
    pub const DBGC_TRACE = c.DBGC_TRACE;
    pub const DBGMSGSZ = c.DBGMSGSZ;

    // Constants from include/sys/param.h
    pub const DFLSTKSZ = c.DFLSTKSZ;
    pub const HZ = c.HZ;
    pub const KSTACKSZ = c.KSTACKSZ;
    pub const MAXDEVNAME = c.MAXDEVNAME;
    pub const MAXEVTNAME = c.MAXEVTNAME;
    pub const MAXIRQS = c.MAXIRQS;
    pub const MAXMEM = c.MAXMEM;
    pub const MAXOBJECTS = c.MAXOBJECTS;
    pub const MAXOBJNAME = c.MAXOBJNAME;
    pub const MAXSYNCS = c.MAXSYNCS;
    pub const MAXTASKNAME = c.MAXTASKNAME;
    pub const MAXTASKS = c.MAXTASKS;
    pub const MAXTHREADS = c.MAXTHREADS;
    pub const MINPRI = c.MINPRI;
    pub const NPRI = c.NPRI;
    pub const PRI_DPC = c.PRI_DPC;
    pub const PRI_IDLE = c.PRI_IDLE;
    pub const PRI_IST = c.PRI_IST;
    pub const PRI_REALTIME = c.PRI_REALTIME;
    pub const PRI_TIMER = c.PRI_TIMER;
    pub const USRSTACK = c.USRSTACK;

    // Constants from sys/include/sched.h
    pub const DPC_FREE = c.DPC_FREE;
    pub const DPC_PENDING = c.DPC_PENDING;
    pub const QUANTUM = c.QUANTUM;

    // Constants from include/sys/sysinfo.h
    pub const INFO_DEVICE = c.INFO_DEVICE;
    pub const INFO_IRQ = c.INFO_IRQ;
    pub const INFO_KERNEL = c.INFO_KERNEL;
    pub const INFO_MEMORY = c.INFO_MEMORY;
    pub const INFO_TASK = c.INFO_TASK;
    pub const INFO_THREAD = c.INFO_THREAD;
    pub const INFO_TIMER = c.INFO_TIMER;
    pub const INFO_VM = c.INFO_VM;
    pub const MAXINFOSZ = c.MAXINFOSZ;

    // Constants from include/sys/ipl.h
    pub const IPL_HIGH = c.IPL_HIGH;

    // Arch-specific constants (include/arm/memory.h, etc.)
    pub const INTSTKTOP = c.INTSTKTOP;
    pub const KERNOFFSET = c.KERNOFFSET;
    pub const PAGE_SIZE = c.PAGE_SIZE;
    pub const USERLIMIT = c.USERLIMIT;

    // Constants from sys/include/deadlock.h
    pub const LOCK_TYPE_MUTEX = c.LOCK_TYPE_MUTEX;

    // Constants from include/sys/bootinfo.h
    pub const MT_BOOTDISK = c.MT_BOOTDISK;
    pub const MT_MEMHOLE = c.MT_MEMHOLE;
    pub const MT_RESERVED = c.MT_RESERVED;
    pub const MT_USABLE = c.MT_USABLE;

    // Constants from sys/include/exception.h
    pub const NEXC = c.NEXC;

    // Constants from sys/include/smp.h
    pub const SPINLOCK_INITIALIZER = c.SPINLOCK_INITIALIZER;

    // Spinlock with inline methods (moved from sys/kern/timer.zig)
    pub const Spinlock = extern struct {
        value: c.spinlock_t,

        pub inline fn lock(self: *Spinlock) void {
            if (comptime @hasDecl(c, "__broken_spinlock_lock")) {
                c.__broken_spinlock_lock(&self.value);
            }
        }

        pub inline fn unlock(self: *Spinlock) void {
            if (comptime @hasDecl(c, "__broken_spinlock_unlock")) {
                c.__broken_spinlock_unlock(&self.value);
            }
        }

        pub inline fn lock_irq(self: *Spinlock, s: *c_int) void {
            s.* = splhigh();
            if (comptime @hasDecl(c, "__broken_spinlock_lock")) {
                c.__broken_spinlock_lock(&self.value);
            }
        }

        pub inline fn unlock_irq(self: *Spinlock, s: c_int) void {
            if (comptime @hasDecl(c, "__broken_spinlock_unlock")) {
                c.__broken_spinlock_unlock(&self.value);
            }
            _ = splx(s);
        }
    };
};

pub const sync = struct {
    pub const Event = extern struct {
        sleepq: Queue,
        name: [*:0]const u8,

        pub fn init(self: *Event, name: [*:0]const u8) void {
            self.sleepq.init();
            self.name = name;
        }

        pub fn isWaiting(self: *const Event) bool {
            return !self.sleepq.isEmpty();
        }
    };

    pub const Mutex = extern struct {
        task_link: List,
        owner: kern.TaskRef,
        event: Event,
        link: List,
        holder: kern.ThreadRef,
        priority: c_int,
        locks: c_int,

        pub fn lock(self: *Mutex) void {
            _ = c.mutex_lock(@ptrCast(self));
        }

        pub fn unlock(self: *Mutex) void {
            _ = c.mutex_unlock(@ptrCast(self));
        }
    };

    pub const Cond = extern struct {
        task_link: List,
        owner: kern.TaskRef,
        event: Event,
    };

    pub const Sem = extern struct {
        next: ?*Sem,
        task_link: List,
        owner: kern.TaskRef,
        event: Event,
        value: kern.Uint,
        refcnt: c_int,
    };

    comptime {
        std.debug.assert(@sizeOf(Event) == @sizeOf(c.struct_event));
        std.debug.assert(@sizeOf(Mutex) == @sizeOf(c.struct_mutex));
        std.debug.assert(@sizeOf(Cond) == @sizeOf(c.struct_cond));
        std.debug.assert(@sizeOf(Sem) == @sizeOf(c.struct_sem));
    }

    // Constants from include/sys/sync.h
    pub const MAXINHERIT = c.MAXINHERIT;
    pub const MAXSEMVAL = c.MAXSEMVAL;
};

pub const kern = struct {
    // Single canonical place for all c.*_t handle type aliases.
    pub const TaskRef = c.task_t;
    pub const ThreadRef = c.thread_t;
    pub const Task = c.struct_task;
    pub const Thread = c.struct_thread;
    pub const DeviceRef = c.device_t;
    pub const ObjectRef = c.object_t;
    pub const MutexRef = c.mutex_t;
    pub const CondRef = c.cond_t;
    pub const SemRef = c.sem_t;
    pub const VmMapRef = c.vm_map_t;
    pub const Pgd = c.pgd_t;
    pub const Register = c.register_t;
    pub const QueueRef = c.queue_t;
    pub const Cap = c.cap_t;
    pub const Uint = c.u_int;
    pub const Ulong = c.u_long;
    pub const Vaddr = c.vaddr_t;
    pub const Paddr = c.paddr_t;
    pub const Vsize = c.vsize_t;
    pub const Psize = c.psize_t;

    pub const Device = extern struct {
        next: ?*Device,
        driver: ?*c.struct_driver,
        name: [c.MAXDEVNAME]u8,
        flags: c_int,
        active: c_int,
        refcnt: c_int,
        private: ?*anyopaque,
    };

    pub const IRQ = extern struct {
        vector: c_int,
        isr: ?*const fn (?*anyopaque) callconv(.c) c_int,
        ist: ?*const fn (?*anyopaque) callconv(.c) void,
        data: ?*anyopaque,
        priority: c_int,
        count: Uint,
        istreq: c_int,
        thread: ThreadRef,
        istevt: sync.Event,
    };

    pub const Timer = extern struct {
        link: hal.List,
        state: c_int,
        expire: Ulong,
        interval: Ulong,
        func: ?*const fn (?*anyopaque) callconv(.c) void,
        arg: ?*anyopaque,
        event: sync.Event,
    };

    comptime {
        std.debug.assert(@sizeOf(Device) == @sizeOf(c.struct_device));
        std.debug.assert(@sizeOf(IRQ) == @sizeOf(c.struct_irq));
        std.debug.assert(@sizeOf(Timer) == @sizeOf(c.struct_timer));
    }

    // Constants from include/sys/capability.h
    pub const CAP_EXTMEM = c.CAP_EXTMEM;
    pub const CAP_KILL = c.CAP_KILL;
    pub const CAP_NICE = c.CAP_NICE;
    pub const CAP_PROTSERV = c.CAP_PROTSERV;
    pub const CAP_RAWIO = c.CAP_RAWIO;
    pub const CAP_SETPCAP = c.CAP_SETPCAP;
    pub const CAP_TASKCTRL = c.CAP_TASKCTRL;
    pub const CAPSET_BOOT = c.CAPSET_BOOT;

    // POSIX errno constants from include/sys/errno.h
    pub const Errno = struct {
        pub const EPERM = c.EPERM;
        pub const ENOENT = c.ENOENT;
        pub const EAGAIN = c.EAGAIN;
        pub const ENOMEM = c.ENOMEM;
        pub const EACCES = c.EACCES;
        pub const EFAULT = c.EFAULT;
        pub const EBUSY = c.EBUSY;
        pub const EEXIST = c.EEXIST;
        pub const ENODEV = c.ENODEV;
        pub const EINVAL = c.EINVAL;
        pub const ENOSPC = c.ENOSPC;
        pub const ERANGE = c.ERANGE;
        pub const ENOSYS = c.ENOSYS;
        pub const EIO = c.EIO;
        pub const ENXIO = c.ENXIO;
        pub const ESRCH = c.ESRCH;
        pub const EDEADLK = c.EDEADLK;
        pub const EINTR = c.EINTR;
        pub const ETIMEDOUT = c.ETIMEDOUT;
    };

    // Constants from sys/include/task.h
    pub const TF_AUDIT = c.TF_AUDIT;
    pub const TF_DEFAULT = c.TF_DEFAULT;
    pub const TF_SYSTEM = c.TF_SYSTEM;

    // Constants from sys/include/thread.h (thread states and sleep results)
    pub const SLP_BREAK = c.SLP_BREAK;
    pub const SLP_INTR = c.SLP_INTR;
    pub const SLP_INVAL = c.SLP_INVAL;
    pub const SLP_SUCCESS = c.SLP_SUCCESS;
    pub const SLP_TIMEOUT = c.SLP_TIMEOUT;
    pub const SOP_GETPOLICY = c.SOP_GETPOLICY;
    pub const SOP_GETPRI = c.SOP_GETPRI;
    pub const SOP_SETPOLICY = c.SOP_SETPOLICY;
    pub const SOP_SETPRI = c.SOP_SETPRI;
    pub const TS_EXIT = c.TS_EXIT;
    pub const TS_RUN = c.TS_RUN;
    pub const TS_SLEEP = c.TS_SLEEP;
    pub const TS_SUSP = c.TS_SUSP;

    // Constants from include/sys/prex.h (scheduling policies, VM options, protection)
    pub const PROT_READ = c.PROT_READ;
    pub const PROT_WRITE = c.PROT_WRITE;
    pub const SCHED_FIFO = c.SCHED_FIFO;
    pub const SCHED_RR = c.SCHED_RR;
    pub const VM_COPY = c.VM_COPY;
    pub const VM_NEW = c.VM_NEW;
    pub const VM_SHARE = c.VM_SHARE;
};

pub const mem = struct {
    // Constants from sys/include/vm.h (VM segment flags)
    pub const SEG_FREE = c.SEG_FREE;
    pub const SEG_MAPPED = c.SEG_MAPPED;
    pub const SEG_READ = c.SEG_READ;
    pub const SEG_SHARED = c.SEG_SHARED;
    pub const SEG_WRITE = c.SEG_WRITE;

    pub const Segment = extern struct {
        prev: *Segment,
        next: *Segment,
        sh_prev: *Segment,
        sh_next: *Segment,
        addr: kern.Vaddr,
        size: usize,
        flags: c_int,
        phys: kern.Paddr,
    };

    pub const VmMap = extern struct {
        head: Segment,
        refcnt: c_int,
        pgd: kern.Pgd,
        total: usize,
    };

    comptime {
        std.debug.assert(@sizeOf(Segment) == @sizeOf(c.struct_seg));
        std.debug.assert(@sizeOf(VmMap) == @sizeOf(c.struct_vm_map));
    }
};
