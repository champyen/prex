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

comptime {
    if (@import("root") == @This()) {
        @export(&strlen, .{ .name = "strlen", .linkage = .strong });
        @export(&strlcpy, .{ .name = "strlcpy", .linkage = .strong });
        @export(&strncmp, .{ .name = "strncmp", .linkage = .strong });
        @export(&strnlen, .{ .name = "strnlen", .linkage = .strong });
        @export(&memcpy, .{ .name = "memcpy", .linkage = .strong });
        @export(&memset, .{ .name = "memset", .linkage = .strong });
        @export(&memmove, .{ .name = "memmove", .linkage = .strong });
    }
}

pub fn strlen(str: [*c]const u8) callconv(.c) usize {
    var i: usize = 0;
    while (str[i] != 0) : (i += 1) {}
    return i;
}

pub fn strlcpy(dest: [*c]u8, src: [*c]const u8, count: usize) callconv(.c) usize {
    var src_len: usize = 0;
    while (src[src_len] != 0) : (src_len += 1) {}

    if (count > 0) {
        const copy_len = @min(src_len, count - 1);
        var i: usize = 0;
        while (i < copy_len) : (i += 1) {
            dest[i] = src[i];
        }
        dest[copy_len] = 0;
    }
    return src_len;
}

pub fn strncmp(src: [*c]const u8, tgt: [*c]const u8, count: usize) callconv(.c) c_int {
    var s = src;
    var t = tgt;
    var n = count;

    while (n != 0) : (n -= 1) {
        const a = s[0];
        const b = t[0];
        s += 1;
        t += 1;
        if (a != b or a == 0) {
            return @as(c_int, @intCast(a)) - @as(c_int, @intCast(b));
        }
    }
    return 0;
}

pub fn strnlen(str: [*c]const u8, count: usize) callconv(.c) usize {
    var s = str;
    var n = count;
    while (n != 0 and s[0] != 0) : (n -= 1) {
        s += 1;
    }
    return @intFromPtr(s) - @intFromPtr(str);
}

pub fn memcpy(dest: ?*anyopaque, src: ?*const anyopaque, count: usize) callconv(.c) ?*anyopaque {
    if (count == 0) return dest;
    const d: [*]volatile u8 = @ptrCast(dest.?);
    const s: [*]volatile const u8 = @ptrCast(src.?);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        d[i] = s[i];
    }
    return dest;
}

pub fn memset(dest: ?*anyopaque, ch: c_int, count: usize) callconv(.c) ?*anyopaque {
    if (count == 0) return dest;
    const d: [*]volatile u8 = @ptrCast(dest.?);
    const byte: u8 = @truncate(@as(c_uint, @bitCast(ch)));
    var i: usize = 0;
    while (i < count) : (i += 1) {
        d[i] = byte;
    }
    return dest;
}

pub fn memmove(dest: ?*anyopaque, src: ?*const anyopaque, count: usize) callconv(.c) ?*anyopaque {
    if (count == 0 or dest == null or src == null) return dest;
    const d: [*]volatile u8 = @ptrCast(dest.?);
    const s: [*]volatile const u8 = @ptrCast(src.?);
    if (@intFromPtr(d) < @intFromPtr(s)) {
        var i: usize = 0;
        while (i < count) : (i += 1) {
            d[i] = s[i];
        }
    } else {
        var i: usize = count;
        while (i > 0) {
            i -= 1;
            d[i] = s[i];
        }
    }
    return dest;
}
