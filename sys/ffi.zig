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
    pub const Vaddr = c.vaddr_t;
    pub const Paddr = c.paddr_t;
    pub const Vsize = c.vsize_t;
    pub const Psize = c.psize_t;
    pub const TaskRef = c.task_t;
    pub const ThreadRef = c.thread_t;
    pub const DeviceRef = c.device_t;
    pub const List = c.struct_list;
    pub const Queue = c.struct_queue;
    pub const Event = c.struct_event;
    pub const Timer = c.struct_timer;
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
};

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
        owner: c.task_t,
        event: sync.Event,
        link: List,
        holder: c.thread_t,
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
        owner: c.task_t,
        event: sync.Event,
    };

    pub const Sem = extern struct {
        next: ?*Sem,
        task_link: List,
        owner: c.task_t,
        event: sync.Event,
        value: c.u_int,
        refcnt: c_int,
    };

    comptime {
        std.debug.assert(@sizeOf(Event) == @sizeOf(c.struct_event));
        std.debug.assert(@sizeOf(Mutex) == @sizeOf(c.struct_mutex));
        std.debug.assert(@sizeOf(Cond) == @sizeOf(c.struct_cond));
        std.debug.assert(@sizeOf(Sem) == @sizeOf(c.struct_sem));
    }
};

pub const ipc = struct {
    pub const Object = extern struct {
        link: List,
        name: [c.MAXOBJNAME]u8,
        task_link: List,
        owner: c.task_t,
        sendq: Queue,
        recvq: Queue,
    };

    comptime {
        std.debug.assert(@sizeOf(Object) == @sizeOf(c.struct_object));
    }
};

pub const kern = struct {
    pub const Device = extern struct {
        next: ?*Device,
        driver: ?*Driver,
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
        count: c.u_int,
        istreq: c_int,
        thread: ThreadRef,
        istevt: sync.Event,
    };

    pub const Timer = extern struct {
        link: List,
        state: c_int,
        expire: c.u_long,
        interval: c.u_long,
        func: *const fn (void) callconv(.c) void,
        arg: ?*anyopaque,
        event: sync.Event,
    };

    pub const Dpc = extern struct {
        link: Queue,
        state: c_int,
        func: *const fn (void) callconv(.c) void,
        arg: ?*anyopaque,
    };

    pub const TaskRef = c.task_t;
    pub const ThreadRef = c.thread_t;
    pub const Thread = c.struct_thread;
    pub const Task = c.struct_task;

    pub const CpuControl = extern struct {
        active_thread: *Thread,
        idle_thread: *Thread,
        nest_count: c_int,
        spl_level: c_int,
        int_stack: ?*anyopaque,
        cpu_id: c_int,
        padding: [10]c_long,
    };

    comptime {
        std.debug.assert(@sizeOf(Device) == @sizeOf(c.struct_device));
        std.debug.assert(@sizeOf(IRQ) == @sizeOf(c.struct_irq));
        std.debug.assert(@sizeOf(Timer) == @sizeOf(c.struct_timer));
        std.debug.assert(@sizeOf(Dpc) == @sizeOf(c.struct_dpc));
        std.debug.assert(@sizeOf(Thread) == @sizeOf(c.struct_thread));
        std.debug.assert(@sizeOf(Task) == @sizeOf(c.struct_task));
        std.debug.assert(@sizeOf(CpuControl) == @sizeOf(c.struct_cpu_control));
    }

    pub const Driver = c.struct_driver;
    pub const DevOps = c.struct_devops;
    pub const DevIO = c.struct_dev_io;
};

pub const mem = struct {
    pub const Segment = extern struct {
        prev: *Segment,
        next: *Segment,
        sh_prev: *Segment,
        sh_next: *Segment,
        addr: hal.Vaddr,
        size: usize,
        flags: c_int,
        phys: hal.Paddr,
    };

    pub const VmMap = extern struct {
        head: mem.Segment,
        refcnt: c_int,
        pgd: c.pgd_t,
        total: usize,
    };

    comptime {
        std.debug.assert(@sizeOf(Segment) == @sizeOf(c.struct_seg));
        std.debug.assert(@sizeOf(VmMap) == @sizeOf(c.struct_vm_map));
    }
};
