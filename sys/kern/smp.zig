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

const ffi = @import("ffi");
const hal = ffi.hal;
const irq = ffi.irq;
const kern = ffi.kern;
const thread = ffi.thread;
const c = @import("c").c;

const NCPUS = if (@hasDecl(c, "CONFIG_SMP_NCPUS")) c.CONFIG_SMP_NCPUS else 1;

const ipi_irq = if (@hasDecl(c, "IPI_IRQ")) c.IPI_IRQ else 0;

const INTSTKTOP = @as(usize, @intCast(hal.INTSTKTOP));

var IST_NONE: ?*const fn (?*anyopaque) callconv(.c) void = undefined;

pub var cpu_table: [NCPUS]hal.CpuControl = std.mem.zeroes([NCPUS]hal.CpuControl);

pub var ap_boot_stacks: [NCPUS][hal.KSTACKSZ]u8 align(16) = std.mem.zeroes([NCPUS][hal.KSTACKSZ]u8);

var ready_count: c_int = 0;
var smp_active: c_int = 0;

extern fn zig_memory_barrier() callconv(.c) void;

fn ipi_isr(arg: ?*anyopaque) callconv(.c) c_int {
    _ = arg;
    return hal.INT_DONE;
}

pub fn kvtop(va: anytype) kern.Paddr {
    return @intFromPtr(va) - hal.KERNOFFSET;
}


pub fn initEarly() callconv(.c) void {
    const cpu: *hal.CpuControl = &cpu_table[0];

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
    _ = irq.attach(ipi_irq, hal.IPL_HIGH, 0, ipi_isr, IST_NONE, null);

    _ = @atomicRmw(c_int, &ready_count, .Add, 1, .seq_cst);

    var started_count: c_int = 1;

    var i: c_int = 1;
    while (i < NCPUS) : (i += 1) {
        const t = thread.create_idle();

        cpu_table[@intCast(i)].active_thread = t;
        cpu_table[@intCast(i)].idle_thread = t;
        cpu_table[@intCast(i)].nest_count = 0;
        cpu_table[@intCast(i)].spl_level = 15;
        cpu_table[@intCast(i)].int_stack = @ptrFromInt(@intFromPtr(&ap_boot_stacks[@intCast(i)]) + hal.KSTACKSZ);
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
    const cpu: *hal.CpuControl = &cpu_table[@intCast(cpuid)];

    hal_set_cpu_control(cpu);

    hal.interrupt_cpu_init();

    hal.clock_ap_init();

    _ = @atomicRmw(c_int, &ready_count, .Add, 1, .seq_cst);

    while (@atomicLoad(c_int, &smp_active, .seq_cst) == 0) {}
    zig_memory_barrier();

    thread.idle();
}

extern fn ap_reset_entry() callconv(.c) void;

extern var riscv_cpus: [c.CONFIG_SMP_NCPUS]hal.RiscVCpu;

pub fn hal_set_cpu_control(cpu: ?*hal.CpuControl) callconv(.c) void {
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

pub fn hal_get_cpu_control() callconv(.c) ?*hal.CpuControl {
    if (builtin.cpu.arch == .x86 or builtin.cpu.arch == .x86_64) {
        return &cpu_table[0];
    } else if (builtin.cpu.arch == .riscv32 or builtin.cpu.arch == .riscv64) {
        return asm volatile ("mv %[ret], tp"
            : [ret] "=r" (-> ?*hal.CpuControl),
        );
    } else if (builtin.cpu.arch == .arm or builtin.cpu.arch == .thumb) {
        if (@hasDecl(c, "CONFIG_ARMV8M")) {
            return @ptrFromInt(asm volatile ("mrs %[ret], psplim"
                : [ret] "=r" (-> usize),
            ));
        } else {
            return asm volatile ("mrc p15, 0, %[ret], c13, c0, 4"
                : [ret] "=r" (-> ?*hal.CpuControl),
            );
        }
    }
    return null;
}
