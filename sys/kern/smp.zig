const std = @import("std");
const builtin = @import("builtin");

const ffi = @import("ffi");
const hal = ffi.hal;
const c = @import("c").c;

const NCPUS = if (@hasDecl(c, "CONFIG_SMP_NCPUS")) c.CONFIG_SMP_NCPUS else 1;

const ipi_irq = if (@hasDecl(c, "IPI_IRQ")) c.IPI_IRQ else 0;

const INTSTKTOP = @as(usize, @intCast(c.INTSTKTOP));

var IST_NONE: ?*const fn (?*anyopaque) callconv(.c) void = undefined;

pub var cpu_table: [NCPUS]c.struct_cpu_control = std.mem.zeroes([NCPUS]c.struct_cpu_control);

pub var ap_boot_stacks: [NCPUS][c.KSTACKSZ]u8 align(16) = std.mem.zeroes([NCPUS][c.KSTACKSZ]u8);

var ready_count: c_int = 0;
var smp_active: c_int = 0;

extern fn zig_memory_barrier() callconv(.c) void;

fn ipi_isr(arg: ?*anyopaque) callconv(.c) c_int {
    _ = arg;
    return c.INT_DONE;
}

pub fn kvtop(va: anytype) ffi.hal.Paddr {
    return @intFromPtr(va) - c.KERNOFFSET;
}

const thread = ffi.thread;

pub fn initEarly() callconv(.c) void {
    const cpu: *c.struct_cpu_control = &cpu_table[0];

    cpu.active_thread = &thread.idle_thread;
    cpu.idle_thread = &thread.idle_thread;
    cpu.nest_count = 0;
    cpu.spl_level = 15;
    cpu.int_stack = @ptrFromInt(INTSTKTOP - 0x100);
    cpu.cpu_id = 0;

    hal_set_cpu_control(cpu);

    @as(*usize, @ptrCast(&IST_NONE)).* = @as(usize, @bitCast(@as(isize, -1)));
}

pub fn startAps() callconv(.c) void {
    _ = ffi.irq.attach(ipi_irq, c.IPL_HIGH, 0, ipi_isr, IST_NONE, null);

    _ = @atomicRmw(c_int, &ready_count, .Add, 1, .seq_cst);

    var started_count: c_int = 1;

    var i: c_int = 1;
    while (i < NCPUS) : (i += 1) {
        const t = thread.create_idle();

        cpu_table[@intCast(i)].active_thread = t;
        cpu_table[@intCast(i)].idle_thread = t;
        cpu_table[@intCast(i)].nest_count = 0;
        cpu_table[@intCast(i)].spl_level = 15;
        cpu_table[@intCast(i)].int_stack = @ptrFromInt(@intFromPtr(&ap_boot_stacks[@intCast(i)]) + c.KSTACKSZ);
        cpu_table[@intCast(i)].cpu_id = i;

        zig_memory_barrier();

        const ret = hal.hal_cpu_start(@intCast(i), kvtop(&ap_reset_entry));
        if (ret == 0) {
            started_count += 1;
        }
    }

    while (@atomicLoad(c_int, &ready_count, .seq_cst) < started_count) {
        zig_memory_barrier();
    }
    zig_memory_barrier();
}

pub fn activate() callconv(.c) void {
    zig_memory_barrier();
    @atomicStore(c_int, &smp_active, 1, .seq_cst);
    zig_memory_barrier();
}

pub fn apBoot() callconv(.c) void {
    zig_memory_barrier();
    const cpuid = hal.hal_cpu_id();
    const cpu: *c.struct_cpu_control = &cpu_table[@intCast(cpuid)];

    hal_set_cpu_control(cpu);

    hal.interrupt_cpu_init();

    hal.clock_ap_init();

    _ = @atomicRmw(c_int, &ready_count, .Add, 1, .seq_cst);

    while (@atomicLoad(c_int, &smp_active, .seq_cst) == 0) {}
    zig_memory_barrier();

    ffi.thread.idle();
}

extern fn ap_reset_entry() callconv(.c) void;

extern var riscv_cpus: [c.CONFIG_SMP_NCPUS]c.struct_riscv_cpu;

pub fn hal_set_cpu_control(cpu: ?*c.struct_cpu_control) callconv(.c) void {
    if (builtin.cpu.arch == .riscv32 or builtin.cpu.arch == .riscv64) {
        asm volatile ("mv tp, %[cpu]"
            :
            : [cpu] "r" (cpu),
        );
        if (cpu) |c_ptr| {
            riscv_cpus[@intCast(c_ptr.cpu_id)].cpu_control = c_ptr;
        }
    } else if (builtin.cpu.arch == .arm or builtin.cpu.arch == .thumb) {
        if (@hasDecl(c, "CONFIG_ARMV8M")) {
            asm volatile ("msr psplim, %[cpu]"
                :
                : [cpu] "r" (cpu),
            );
        } else {
            asm volatile ("mcr p15, 0, %[cpu], c13, c0, 4"
                :
                : [cpu] "r" (cpu),
            );
        }
    }
}

pub fn hal_get_cpu_control() callconv(.c) ?*c.struct_cpu_control {
    if (builtin.cpu.arch == .x86 or builtin.cpu.arch == .x86_64) {
        return &cpu_table[0];
    } else if (builtin.cpu.arch == .riscv32 or builtin.cpu.arch == .riscv64) {
        return asm volatile ("mv %[ret], tp"
            : [ret] "=r" (-> ?*c.struct_cpu_control),
        );
    } else if (builtin.cpu.arch == .arm or builtin.cpu.arch == .thumb) {
        if (@hasDecl(c, "CONFIG_ARMV8M")) {
            return @ptrFromInt(asm volatile ("mrs %[ret], psplim"
                : [ret] "=r" (-> usize),
            ));
        } else {
            return asm volatile ("mrc p15, 0, %[ret], c13, c0, 4"
                : [ret] "=r" (-> ?*c.struct_cpu_control),
            );
        }
    }
    return null;
}

comptime {
    if (@import("root") == @This()) {
        @export(&cpu_table, .{ .name = "cpu_table", .linkage = .strong });
        @export(&ap_boot_stacks, .{ .name = "ap_boot_stacks", .linkage = .strong });
        @export(&initEarly, .{ .name = "smp_init_early", .linkage = .strong });
        @export(&hal_set_cpu_control, .{ .name = "hal_set_cpu_control", .linkage = .strong });
        @export(&hal_get_cpu_control, .{ .name = "hal_get_cpu_control", .linkage = .strong });
        if (@hasDecl(c, "CONFIG_SMP")) {
            @export(&startAps, .{ .name = "smp_start_aps", .linkage = .strong });
            @export(&activate, .{ .name = "smp_activate", .linkage = .strong });
            @export(&apBoot, .{ .name = "smp_ap_boot", .linkage = .strong });
        }
    }
}
