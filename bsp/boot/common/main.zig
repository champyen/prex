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
//
// bsp/boot/common/main.zig — Boot loader main module.
// Replaces bsp/boot/common/main.c.

const ffi = @import("ffi");
const splash = @import("splash.zig");
const bootinfo = @import("bootinfo.zig");
const load = @import("load.zig");
const machine_startup = @import("machine_startup");
const machine_debug = @import("machine_debug");
const panic_mod = @import("panic_mod");

const boot = ffi.boot;
const cfg = ffi.cfg;

/// Zero the bootinfo struct.
fn zeroBootinfo() void {
    var i: usize = 0;
    const zero_ptr: [*]u8 = @ptrCast(@as(*u8, @ptrFromInt(cfg.BOOTINFO -% cfg.KERNOFFSET)));
    while (i < 1024) : (i += 1) {
        zero_ptr[i] = 0;
    }
}

/// Bootloader main routine.
///
/// Called from head.S / startup.S. Assumes:
/// - CPU is initialized.
/// - DRAM is configured.
/// - Loader BSS section is filled with 0.
/// - Loader stack is configured.
/// - All interrupts are disabled.
inline fn DPRINTF(comptime format: []const u8, args: anytype) void {
    if (cfg.DEBUG) {
        ffi.print(format, args);
    }
}

pub export fn main() callconv(.c) c_int {
    // 1. Initialize the bootinfo global pointer (handled by
    //    common/bootinfo.zig).
    bootinfo.boot_bootinfo_init();

    // 2. Zero the bootinfo struct.
    zeroBootinfo();

    // 3. Initialize debug port (direct @import call; no extern fn ABI
    //    boundary needed across Zig modules).
    machine_debug.debug_init();

    // 4. Print banner via DPRINTF (only when DEBUG is set).
    DPRINTF("Prex+ Boot Loader\n", .{});

    // 5. Do platform dependent initialization (direct @import call;
    //    no extern fn ABI boundary needed across Zig modules).
    machine_startup.startup();

    // 6. Show splash screen (common/splash.zig).
    splash.splash();

    // 7. Load OS modules to appropriate locations (common/load.zig).
    load.load_os();

    // 8. Dump boot information (common/bootinfo.zig).
    if (cfg.DEBUG) {
        bootinfo.dumpBootinfo();
    } else {
        bootinfo.dumpBootinfoNoop();
    }

    // 9. Launch kernel via C helper (Zig 0.16 has a function-pointer
    //    call codegen bug for all archs; see common/jump_entry.c).
    const entry_ptr: usize = boot.bootinfo.*.kernel.entry -% cfg.KERNOFFSET;
    DPRINTF("Entering kernel (at 0x{x}) ...\n\n", .{entry_ptr});
    boot.jump_to_kernel(entry_ptr);
    unreachable;
}
