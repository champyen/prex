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
// DAMAGES (INCLUDING BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
// OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
// HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
// LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
// OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
// SUCH DAMAGE.
//
// bsp/boot/common/load.zig — Load OS modules (kernel, driver, boot tasks).
// Replaces bsp/boot/common/load.c.

const std = @import("std");
const builtin = @import("builtin");
const ffi = @import("ffi");
const ar = ffi.ar;
const boot_mem = ffi.mem;
const boot = ffi.boot;
const cfg = ffi.cfg;
const elf = ffi.elf;

const is_riscv: bool = builtin.cpu.arch == .riscv32 or builtin.cpu.arch == .riscv64;
const is_armv8m: bool = ffi.mem.is_armv8m;

inline fn DPRINTF(comptime format: [*c]const u8, args: anytype) void {
    if (cfg.DEBUG) {
        @call(.auto, ffi.boot.printf, .{format} ++ args);
    }
}

// ============================================================================
// Static state (BSS/externs — exported with C linkage)
// ============================================================================

// Use `export var` to create C-linkage global variables with initializers.
// Zig 0.16 doesn't allow initializers on `pub extern var` (which is just
// a forward declaration), so we use `export var` which creates the
// actual storage with C linkage.
export var load_base: ffi.paddr_t = 0;
export var load_start: ffi.paddr_t = 0;
export var nr_img: c_int = 0;

// ARMv8-M: minimum data address across all loaded modules
// Used for the reserved memory region instead of sram_load_start
export var min_data_addr: ffi.paddr_t = 0;

// ARMv8-M: keep sram_load_base/start for elf.c compatibility
// elf.c uses #define load_base sram_load_base so it updates sram_load_base
export var sram_load_base: ffi.paddr_t = 0;
export var sram_load_start: ffi.paddr_t = 0;

// ============================================================================
// load_module — static helper (mirrors C's static function)
// ============================================================================

fn load_module(hdr: *ffi.ar.@"struct", m: *ffi.mem.Module) c_int {
    const ar_hdr: *ffi.ar.@"struct" = hdr;

    // Check archive header magic
    if (std.mem.eql(u8, &ar_hdr.ar_fmag, ar.constants.ARFMAG) == false) {
        DPRINTF("Invalid image %s\n", .{@as([*c]const u8, @ptrCast(&ar_hdr.*.ar_name))});
        return -1;
    }

    // Copy module name (strip trailing '/' and ' ')
    var name_buf: [16]u8 = undefined;
    std.mem.copyForwards(u8, &name_buf, &ar_hdr.*.ar_name);
    var i: usize = 0;
    while (i < 16 and name_buf[i] != '/' and name_buf[i] != ' ') : (i += 1) {}
    name_buf[i] = 0;

    std.mem.copyForwards(u8, &m.*.name, &name_buf);
    m.*.name[i] = 0;

    // Load ELF image (skip archive header)
    const img_ptr: [*]u8 = @ptrFromInt(@intFromPtr(hdr) + @sizeOf(ffi.ar.@"struct"));
    const img_size = parseArSize(&hdr.*.ar_size);
    DPRINTF("loading: hdr=%lx module=%lx name=%s\n", .{ @as(c_ulong, @intCast(@intFromPtr(hdr))), @as(c_ulong, @intCast(@intFromPtr(m))), @as([*c]const u8, @ptrCast(&m.*.name)) });
    const r = elf.api.load_elf(img_ptr, img_size, m);
    if (r != 0) {
        boot.panic("Load error");
    }

    // Track minimum data address for ARMv8-M reserved region
    if (is_armv8m and m.*.data != 0) {
        if (min_data_addr == 0 or m.*.data < min_data_addr) {
            min_data_addr = m.*.data;
        }
    }

    return 0;
}

// Parse a 10-byte decimal string (not null-terminated) to usize.
// Mirrors C's atol() behavior: skips leading whitespace, reads digits.
fn parseArSize(size_bytes: *[10]u8) usize {
    var result: usize = 0;
    var i: usize = 0;
    // Skip leading whitespace (spaces, tabs)
    while (i < 10 and (size_bytes[i] == ' ' or size_bytes[i] == '\t')) : (i += 1) {}
    // Parse digits
    while (i < 10) : (i += 1) {
        const ch = size_bytes[i];
        if (ch >= '0' and ch <= '9') {
            result = result * 10 + @as(usize, @intCast(ch - '0'));
        } else {
            break;
        }
    }
    return result;
}

// ============================================================================
// setup_bootdisk — static helper
// ============================================================================

fn setup_bootdisk(hdr: *ffi.ar.@"struct") void {
    const ar_hdr: *ffi.ar.@"struct" = hdr;

    if (std.mem.eql(u8, &ar_hdr.ar_fmag, ar.constants.ARFMAG) == false) {
        DPRINTF("Invalid bootdisk image\n", .{});
        return;
    }

    const size = parseArSize(&ar_hdr.*.ar_size);
    const size_aligned = (size + 1) & ~@as(usize, 1); // even alignment

    if (size_aligned == 0) {
        DPRINTF("Size of bootdisk is zero\n", .{});
        return;
    }

    const base: usize = @intFromPtr(hdr) + @sizeOf(ffi.ar.@"struct");
    const bi: *ffi.mem.BootInfo = @constCast(@ptrCast(@alignCast(boot.bootinfo)));

    bi.*.bootdisk.base = @as(usize, @intCast(base));
    bi.*.bootdisk.size = size_aligned;

    // Reserve memory for boot disk (non-RISC-V, non-ROMBOOT)
    if (!is_riscv) {
        const ram_idx: usize = @intCast(bi.*.nr_rams);
        bi.*.ram[ram_idx].base = @as(usize, @intCast(base));
        bi.*.ram[ram_idx].size = size_aligned;
        bi.*.ram[ram_idx].type = ffi.mem.MT_BOOTDISK;
        bi.*.nr_rams += 1;
    }
    DPRINTF("bootdisk base=%lx size=%lx\n", .{ bi.*.bootdisk.base, bi.*.bootdisk.size });
}

// ARMv8-M: _bss_end is provided by linker script
// Use @extern inside the is_armv8m branch so the symbol reference is only
// emitted for ARMv8-M targets (not for Cortex-A which lacks the symbol).

// ============================================================================
// load_os — public C-ABI entry point
// ============================================================================

pub export fn load_os() callconv(.c) void {
    const bi: *ffi.mem.BootInfo = @constCast(@ptrCast(@alignCast(boot.bootinfo)));


    // Initialize static state
    load_base = 0;
    load_start = 0;
    nr_img = 0;
    min_data_addr = 0;

    if (is_armv8m) {
        // ARMv8-M: sram_load_base/start from _bss_end
        // _bss_end is a linker label; @extern resolves it to a pointer
        const bss_end = @extern(*usize, .{ .name = "_bss_end" });
        sram_load_start = ffi.mem.round_page(ffi.addr.kvtop(@intFromPtr(bss_end)));
        sram_load_base = sram_load_start;
    }

    // Sanity check of archive image
    const magic: [*]u8 = @ptrFromInt(ffi.addr.kvtop(cfg.CONFIG_BOOTIMG_BASE));
    if (std.mem.eql(u8, magic[0..8], ar.constants.ARMAG) == false) {
        boot.panic("Invalid OS image");
    }

// Load kernel module
    var hdr: *ffi.ar.@"struct" = @ptrFromInt(@intFromPtr(magic) + 8);
    if (load_module(hdr, &bi.*.kernel) != 0) {
        boot.panic("Can not load kernel");
    }

    // Load driver module
    var len: usize = parseArSize(&hdr.*.ar_size);
    len += @mod(len, 2); // even alignment
    if (len == 0) {
        boot.panic("Invalid driver image");
    }
    hdr = @ptrFromInt(@intFromPtr(hdr) + @sizeOf(ffi.ar.@"struct") + len);
    if (load_module(hdr, &bi.*.driver) != 0) {
        boot.panic("Can not load driver");
    }

    // Load boot tasks
    var i: usize = 0;
    const bi2 = bi;
    var m: *ffi.mem.Module = &bi2.*.tasks[0];
    while (true) {
        len = parseArSize(&hdr.*.ar_size);
        len += @mod(len, 2); // even alignment
        if (len == 0) break;
        hdr = @ptrFromInt(@intFromPtr(hdr) + @sizeOf(ffi.ar.@"struct") + len);

        // Check archive header
        if (std.mem.eql(u8, &hdr.*.ar_fmag, ar.constants.ARFMAG) == false) {
            break;
        }

        // Check for bootdisk.a
        const name_ptr: [*]const u8 = @ptrCast(&hdr.*.ar_name);
        if (std.mem.eql(u8, name_ptr[0..10], "bootdisk.a") == true) {
            setup_bootdisk(hdr);
            continue;
        }

        // Load task
        if (load_module(hdr, m) != 0) break;
        i += 1;
        m = @ptrFromInt(@intFromPtr(m) + @sizeOf(ffi.mem.Module));
    }

    bi2.*.nr_tasks = @intCast(i);

    if (i == 0) {
        boot.panic("No boot task found!");
    }

    if (is_riscv) {
        // RISC-V specific: Reserve memory for OS archive
        const ram_idx: usize = @intCast(bi2.*.nr_rams);
        bi2.*.ram[ram_idx].base = @intFromPtr(magic);
        bi2.*.ram[ram_idx].size = ffi.mem.round_page(@as(usize, @intCast(@intFromPtr(hdr) - @intFromPtr(magic))));
        bi2.*.ram[ram_idx].type = ffi.mem.MT_RESERVED;
        bi2.*.nr_rams += 1;
    }

// Reserve single memory block for all boot modules
    const ram_idx: usize = @intCast(bi2.*.nr_rams);

    if (is_riscv) {
        bi2.*.ram[ram_idx].base = @as(usize, ffi.mem.trunc_page(load_start));
        bi2.*.ram[ram_idx].size = @as(usize, ffi.mem.round_page(load_base - load_start));
    } else if (is_armv8m) {
        // For ARMv8-M, use min_data_addr which tracks the lowest data address
        // of all loaded modules (kernel data at 0x30004400 for musca-b1).
        // Fall back to sram_load_start if min_data_addr wasn't set.
        const base = if (min_data_addr != 0) min_data_addr else sram_load_start;
        bi2.*.ram[ram_idx].base = @as(usize, base);
        bi2.*.ram[ram_idx].size = @as(usize, sram_load_base - base);
    } else {
        bi2.*.ram[ram_idx].base = @as(usize, load_start);
        bi2.*.ram[ram_idx].size = @as(usize, load_base - load_start);
    }
    bi2.*.ram[ram_idx].type = ffi.mem.MT_RESERVED;
    bi2.*.nr_rams += 1;
}
