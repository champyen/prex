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

// bsp/boot/common/string.zig — minimal libc-equivalent for the bootloader.
//
// Replaces common/string.c (atol, strlcpy, strncmp, memcpy, memset).
// Functions are callconv(.c) so the rest of the bootloader (C or Zig) can
// call them transparently.
//
// Each function is a separate @export at the bottom of the file; this
// file is a single `zig build-obj` compilation unit, mirroring how
// pl011.zig and ramdisk.zig self-export.
//
// Namespace convention (see zig_boot_plan.md §4a "no raw c.* in domain
// code" rule): the c_int / c_ulong / c_long types are Zig built-in
// primitive types and don't need to be aliased; the C-ABI struct types
// and complex types are accessed via ffi.*. Function-pointer type aliases
// (MemcpyFn, MemsetFn, ...) live in ffi.boot.* and are available to
// future callers (e.g. common/load.zig will use ffi.boot.memcpy instead of
// declaring its own signature).

const ffi = @import("ffi");

// ============================================================================
// atol — convert string to long. Does not support negative values (matches
// the C version which only handles positive decimal integers).
// Zig-native ABI (not exposed to C/assembly).
// ============================================================================
pub fn atol(str: [*c]const u8) c_long {
    var p: [*c]const u8 = str;
    // Skip leading spaces.
    while (p[0] == ' ') : (p += 1) {}
    var val: c_long = 0;
    while (p[0] >= '0' and p[0] <= '9') {
        val *= 10;
        val += p[0] - '0';
        p += 1;
    }
    return val;
}

// ============================================================================
// strlcpy — bounded string copy. Destination is always NUL-terminated.
// Returns strlen(src) (caller can detect truncation by comparing to count).
// Zig-native ABI.
// ============================================================================
pub fn strlcpy(dest: [*c]u8, src: [*c]const u8, count: c_ulong) c_ulong {
    // Use opaque many-pointer to defeat Zig's C-string optimization (which
    // would otherwise emit a call to libc's strlen()).
    const d: [*]u8 = @ptrCast(dest);
    const s: [*]const u8 = @ptrCast(src);
    var di: usize = 0;
    var si: usize = 0;

    if (count != 0) {
        while (di + 1 < count) {
            d[di] = s[si];
            if (s[si] == 0) break;
            di += 1;
            si += 1;
        }
        if (di < count) {
            // Out of room without seeing NUL — terminate dest.
            d[di] = 0;
        }
    }

    // Use Volatile read to prevent LLVM from replacing the loop with strlen.
    // (The @as cast forces the pointer to be treated as bytes, not C-string.)
    while (true) {
        const b: u8 = @as([*]const volatile u8, @ptrCast(s))[si];
        if (b == 0) break;
        si += 1;
    }
    return si;
}

// ============================================================================
// strncmp — compare at most count bytes. Returns 0 on equal, non-zero otherwise.
// Zig-native ABI.
// ============================================================================
pub fn strncmp(src: [*c]const u8, tgt: [*c]const u8, count: c_ulong) c_int {
    var s: [*]const u8 = src;
    var t: [*]const u8 = tgt;
    var n: c_ulong = count;

    while (n != 0) {
        const a: u8 = s[0];
        const b: u8 = t[0];
        if (a != b) return @intCast(a -% b);
        if (a == 0) return 0;
        s += 1;
        t += 1;
        n -= 1;
    }
    return 0;
}

// ============================================================================
// memcpy — copy n bytes. Caller is responsible for non-overlap guarantee.
// Zig-native ABI.
// ============================================================================
pub fn memcpy(dest: ?*anyopaque, src: ?*const anyopaque, count: c_ulong) ?*anyopaque {
    const d: [*]volatile u8 = @ptrCast(dest);
    const s: [*]volatile const u8 = @ptrCast(src);
    var i: c_ulong = 0;
    while (i < count) : (i += 1) {
        d[i] = s[i];
    }
    return dest;
}

// ============================================================================
// memset — fill n bytes with ch (interpreted as unsigned byte).
// Zig-native ABI.
// ============================================================================
pub fn memset(dest: ?*anyopaque, ch: c_int, count: c_ulong) ?*anyopaque {
    const d: [*]volatile u8 = @ptrCast(dest);
    const v: u8 = @intCast(ch & 0xFF);
    var i: c_ulong = 0;
    while (i < count) : (i += 1) {
        d[i] = v;
    }
    return dest;
}

// ============================================================================
// strlen — MOVED to bsp/boot/zig/ffi.zig (co-located with printRuntimeRaw so
// Zig's optimizer can resolve the symbol in the same TU when it emits direct
// calls to `strlen` for [*c]const u8 conversions).
// ============================================================================
