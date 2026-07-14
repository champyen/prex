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
// 3. Neither the name of the author nor the names of any co-contributors
//    may be used to endorse or promote products derived from this software
//    without specific prior written permission.
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

// bsp/boot/arm/gba/debug.zig — Game Boy Advance debug port.
//
// Port of common/arm/gba/debug.c. The GBA has no real serial port for
// bootloader diagnostics — debug_init is a no-op, debug_putc is guarded
// by CONFIG_DEBUG + CONFIG_DIAG_VBA and emits characters through an
// out-of-line `vba_putc(int)` symbol that the VBA emulator hooks.
//
// Matched against boot.h's `void debug_init(void)` and
// `void debug_putc(int)` declarations via the boot.* namespace in
// ffi.zig (extern fn, callconv(.c)).

const ffi = @import("ffi");
const vba_putc = @extern(*const fn (c_int) callconv(.c) void, .{ .name = "vba_putc" });

pub fn debug_putc(c: c_int) void {
    if (ffi.cfg.DEBUG and ffi.cfg.CONFIG_DIAG_VBA) {
        vba_putc(c);
    }
}

pub fn debug_init() void {
    // DO NOTHING on real hardware (GBA has no debug serial port).
}
