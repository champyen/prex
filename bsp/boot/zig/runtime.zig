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

// bsp/boot/zig/runtime.zig — Zig-side runtime helpers for the bootloader.
//
// Mirrors sys/lib/zig_runtime.zig. Provides:
//   - AEABI memcpy/memset/memclr stubs (for ARM/Thumb targets that don't
//     link against libgcc's compiler-rt; Zig's optimizer emits calls to
//     __aeabi_memcpy / __aeabi_memset when generating word-sized copies
//     of large structs).
//   - A panic glue (runtime.panic) that delegates to the C-ABI panic
//     exported by common/main.zig.
//
// Domain .zig files in bsp/boot/common/, bsp/boot/zig/reloc/, and
// bsp/boot/<arch>/<plat>/ can `@import("runtime")` for these helpers.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// AEABI runtime stubs (ARM/Thumb only).
//
// Zig's optimizer (ReleaseSmall) lowers large struct copies to
// __aeabi_memcpy / __aeabi_memcpy4 / __aeabi_memcpy8 calls on ARMv7. The
// bootloader does not link libgcc, so we provide minimal inline stubs.
// Mirrors bsp/drv/zig/aeabi.zig (which does the same for the driver).
// ============================================================================

comptime {
    if (builtin.cpu.arch == .arm or builtin.cpu.arch == .thumb) {
        @export(&__aeabiMemcpy, .{ .name = "__aeabi_memcpy", .linkage = .strong });
        @export(&__aeabiMemcpy, .{ .name = "__aeabi_memcpy4", .linkage = .strong });
        @export(&__aeabiMemcpy, .{ .name = "__aeabi_memcpy8", .linkage = .strong });
        @export(&__aeabiMemset, .{ .name = "__aeabi_memset", .linkage = .strong });
        @export(&__aeabiMemset, .{ .name = "__aeabi_memset4", .linkage = .strong });
        @export(&__aeabiMemset, .{ .name = "__aeabi_memset8", .linkage = .strong });
        @export(&__aeabiMemclr, .{ .name = "__aeabi_memclr", .linkage = .strong });
        @export(&__aeabiMemclr, .{ .name = "__aeabi_memclr4", .linkage = .strong });
        @export(&__aeabiMemclr, .{ .name = "__aeabi_memclr8", .linkage = .strong });
    }
}

fn __aeabiMemcpy(dest: ?*anyopaque, src: ?*const anyopaque, n: usize) callconv(.c) void {
    @setRuntimeSafety(false);
    const d: [*]volatile u8 = @ptrCast(dest);
    const s: [*]volatile const u8 = @ptrCast(src);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        d[i] = s[i];
    }
}

fn __aeabiMemset(dest: ?*anyopaque, n: usize, val: c_int) callconv(.c) void {
    @setRuntimeSafety(false);
    const d: [*]volatile u8 = @ptrCast(dest);
    const v: u8 = @intCast(val & 0xFF);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        d[i] = v;
    }
}

fn __aeabiMemclr(dest: ?*anyopaque, n: usize) callconv(.c) void {
    __aeabiMemset(dest, n, 0);
}
