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

/// Prex+ Native Microkernel Interface (PREX) Wrapper for Zig
pub const c = @cImport({
    @cInclude("conf/config.h");
    @cInclude("sys/prex.h");
    @cInclude("sys/errno.h");
});

/// Map Zig errors to positive POSIX errno integers
pub fn toCError(err: anyerror) c_int {
    return switch (err) {
        error.OutOfMemory => c.ENOMEM,
        error.InvalidArgs => c.EINVAL,
        error.IoError => c.EIO,
        error.Fault => c.EFAULT,
        error.NoDevice => c.ENODEV,
        error.NoEntry => c.ENOENT,
        error.Busy => c.EBUSY,
        error.Timeout => c.ETIMEDOUT,
        error.NotSupported => c.ENOSYS,
        else => c.EIO,
    };
}

/// Formatted print utility routing to sys_log
pub fn print(comptime fmt: []const u8, args: anytype) void {
    if (args.len == 0) {
        _ = c.sys_log(fmt.ptr);
    } else {
        var buf: [256]u8 = undefined;
        if (std.fmt.bufPrint(&buf, fmt, args)) |msg| {
            var term_buf: [257]u8 = undefined;
            @memcpy(term_buf[0..msg.len], msg);
            term_buf[msg.len] = 0;
            _ = c.sys_log(@ptrCast(&term_buf));
        } else |_| {
            _ = c.sys_log("print formatting failed\n");
        }
    }
}

/// Standard Zig panic handler for Prex+ tasks
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    var buf: [256]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buf, "ZIG PANIC: {s}\x00", .{msg}) catch "ZIG PANIC!\x00";
    c.sys_panic(formatted.ptr);
    while (true) {}
}

/// Custom allocator wrapping vm_allocate/vm_free for heap usage in native tasks
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
    var addr: ?*anyopaque = null;
    // vm_allocate always returns page-aligned memory
    const err = c.vm_allocate(c.task_self(), &addr, len, 1);
    if (err != 0) return null;
    return @ptrCast(addr);
}

fn free(_: *anyopaque, buf: []u8, _: std.mem.Alignment, _: usize) void {
    _ = c.vm_free(c.task_self(), buf.ptr);
}
