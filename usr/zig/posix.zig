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

/// Prex+ POSIX Interface Wrapper for Zig
pub const c = @cImport({
    @cInclude("conf/config.h");
    @cInclude("unistd.h");
    @cInclude("stdlib.h");
    @cInclude("stdio.h");
    @cInclude("errno.h");
    @cInclude("fcntl.h");
});

/// Formatted print utility routing to standard output (via POSIX write)
pub fn print(comptime fmt: []const u8, args: anytype) void {
    if (args.len == 0) {
        _ = c.write(1, fmt.ptr, fmt.len);
    } else {
        var buf: [512]u8 = undefined;
        if (std.fmt.bufPrint(&buf, fmt, args)) |msg| {
            _ = c.write(1, msg.ptr, msg.len);
        } else |_| {
            const err_msg = "print formatting failed\n";
            _ = c.write(1, err_msg.ptr, err_msg.len);
        }
    }
}

/// Standard Zig panic handler for POSIX processes
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    var buf: [512]u8 = undefined;
    if (std.fmt.bufPrint(&buf, "ZIG PANIC: {s}\n", .{msg})) |formatted| {
        _ = c.write(2, formatted.ptr, formatted.len);
    } else |_| {
        const err_msg = "ZIG PANIC!\n";
        _ = c.write(2, err_msg.ptr, err_msg.len);
    }
    c.exit(1);
}

/// Standard allocator wrapping malloc/free for POSIX processes
pub const allocator = std.mem.Allocator{
    .ptr = undefined,
    .vtable = &.{
        .alloc = alloc,
        .resize = std.mem.Allocator.noResize,
        .remap = std.mem.Allocator.noRemap,
        .free = free,
    },
};

fn alloc(_: *anyopaque, len: usize, _: std.mem.Alignment, _: usize) ?[*]u8 {
    if (c.malloc(len)) |ptr| {
        return @ptrCast(ptr);
    }
    return null;
}

fn free(_: *anyopaque, buf: []u8, _: std.mem.Alignment, _: usize) void {
    c.free(buf.ptr);
}
