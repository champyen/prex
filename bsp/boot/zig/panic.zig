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

// bsp/boot/zig/panic.zig — panic helper shared across bootloader modules.
//
// Provided as its own tiny Zig module so both the root module (which
// contains common/main.zig, common/load.zig etc.) and the machine_*
// modules (machine_startup, machine_debug, machine_reloc) can
// `@import("panic_mod")` and call `panic()` directly with Zig-native
// ABI. No extern fn indirection needed for the standalone Zig
// bootloader program.

const ffi = @import("ffi");

/// Hang the system after printing a panic message. Zig-native ABI —
/// both root-module callers (via main.bootPanic) and cross-module
/// callers (machine_reloc's elf_reloc helpers, machine_startup/debug
/// if they ever need it) reach this function through a small `panic_mod`
/// module dep declared in mk/zig.mk.
pub fn panic(comptime msg: []const u8) noreturn {
    if (ffi.cfg.DEBUG) {
        @import("ffi").print("Panic: " ++ msg ++ "\n", .{});
    }
    while (true) {}
}
