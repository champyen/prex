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

/// Prex+ Native Real-Time Task Wrapper for Zig
///
/// Used by everything built with `mk/task.mk` (standalone RT tasks that
/// talk to the microkernel directly). Provides kernel syscall wrappers,
/// raw kernel types (task_t, object_t, ...), and helpers for native RT
/// tasks. The POSIX-equivalent wrapper for programs built with
/// `mk/prog.mk` lives in `prog.zig`.
pub const prex = @cImport({
    @cInclude("conf/config.h");
    @cInclude("sys/prex.h");
    @cInclude("sys/errno.h");
});

/// Map Zig errors to positive POSIX errno integers
pub fn toCError(err: anyerror) c_int {
    return switch (err) {
        error.OutOfMemory => prex.ENOMEM,
        error.InvalidArgs => prex.EINVAL,
        error.IoError => prex.EIO,
        error.Fault => prex.EFAULT,
        error.NoDevice => prex.ENODEV,
        error.NoEntry => prex.ENOENT,
        error.Busy => prex.EBUSY,
        error.Timeout => prex.ETIMEDOUT,
        error.NotSupported => prex.ENOSYS,
        else => prex.EIO,
    };
}

/// Formatted print utility routing to sys_log
pub fn print(comptime fmt: []const u8, args: anytype) void {
    if (args.len == 0) {
        _ = prex.sys_log(fmt.ptr);
    } else {
        var buf: [256]u8 = undefined;
        if (std.fmt.bufPrint(&buf, fmt, args)) |msg| {
            var term_buf: [257]u8 = undefined;
            @memcpy(term_buf[0..msg.len], msg);
            term_buf[msg.len] = 0;
            _ = prex.sys_log(@ptrCast(&term_buf));
        } else |_| {
            _ = prex.sys_log("print formatting failed\n");
        }
    }
}

/// Standard Zig panic handler for Prex+ tasks
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    var buf: [256]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buf, "ZIG PANIC: {s}\x00", .{msg}) catch "ZIG PANIC!\x00";
    prex.sys_panic(formatted.ptr);
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
    const err = prex.vm_allocate(prex.task_self(), &addr, len, 1);
    if (err != 0) return null;
    return @ptrCast(addr);
}

fn free(_: *anyopaque, buf: []u8, _: std.mem.Alignment, _: usize) void {
    _ = prex.vm_free(prex.task_self(), buf.ptr);
}
