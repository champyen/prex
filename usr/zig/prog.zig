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

/// Prex+ POSIX Program Wrapper for Zig
///
/// Used by everything built with `mk/prog.mk`: servers, user programs,
/// shells, etc. Provides libc + IPC bindings; kernel syscall types live
/// in `task.zig` under the `prex` namespace.
pub const unistd = @cImport({
    @cInclude("conf/config.h");
    @cInclude("unistd.h");
});

pub const stdlib = @cImport({
    @cInclude("conf/config.h");
    @cInclude("stdlib.h");
});

pub const stdio = @cImport({
    @cInclude("conf/config.h");
    @cInclude("stdio.h");
});

pub const errno = @cImport({
    @cInclude("conf/config.h");
    @cInclude("errno.h");
});

pub const fcntl = @cImport({
    @cInclude("conf/config.h");
    @cInclude("fcntl.h");
});

pub const string = @cImport({
    @cInclude("conf/config.h");
    @cInclude("string.h");
});

pub const signal = @cImport({
    @cInclude("conf/config.h");
    @cInclude("signal.h");
});

pub const poll = @cImport({
    @cInclude("conf/config.h");
    @cInclude("sys/poll.h");
});

pub const dirent = @cImport({
    @cInclude("conf/config.h");
    @cInclude("dirent.h");
});

pub const capsys = @cImport({
    @cInclude("conf/config.h");
    @cInclude("sys/types.h");
    @cInclude("sys/capability.h");
});

pub const termios = @cImport({
    @cInclude("conf/config.h");
    @cInclude("sys/types.h");
    @cInclude("sys/termios.h");
});

pub const sys = struct {
    pub const mount = @cImport({
        @cInclude("conf/config.h");
        @cInclude("sys/mount.h");
    });
    pub const syslog = @cImport({
        @cInclude("conf/config.h");
        @cInclude("sys/syslog.h");
    });
    pub const stat = @cImport({
        @cInclude("conf/config.h");
        @cInclude("sys/stat.h");
    });
    pub const list = @cImport({
        @cInclude("conf/config.h");
        @cInclude("sys/list.h");
    });
    pub const vnode = @cImport({
        @cInclude("conf/config.h");
        @cInclude("sys/vnode.h");
        @cInclude("sys/file.h");
    });
    pub const buf = @cImport({
        @cInclude("conf/config.h");
        @cInclude("sys/buf.h");
    });
};

pub const ipc = struct {
    pub const fs = @cImport({
        @cInclude("conf/config.h");
        @cInclude("ipc/fs.h");
    });
    pub const proc = @cImport({
        @cInclude("conf/config.h");
        @cInclude("ipc/proc.h");
    });
    pub const exec = @cImport({
        @cInclude("conf/config.h");
        @cInclude("ipc/exec.h");
    });
    pub const ipc = @cImport({
        @cInclude("conf/config.h");
        @cInclude("ipc/ipc.h");
    });
};

/// Formatted print utility routing to standard output (via POSIX write)
pub fn print(comptime fmt: []const u8, args: anytype) void {
    if (args.len == 0) {
        _ = unistd.write(1, fmt.ptr, fmt.len);
    } else {
        var buf: [512]u8 = undefined;
        if (std.fmt.bufPrint(&buf, fmt, args)) |msg| {
            _ = unistd.write(1, msg.ptr, msg.len);
        } else |_| {
            const err_msg = "print formatting failed\n";
            _ = unistd.write(1, err_msg.ptr, err_msg.len);
        }
    }
}

/// Standard Zig panic handler for POSIX processes
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    var buf: [512]u8 = undefined;
    if (std.fmt.bufPrint(&buf, "ZIG PANIC: {s}\n", .{msg})) |formatted| {
        _ = unistd.write(2, formatted.ptr, formatted.len);
    } else |_| {
        const err_msg = "ZIG PANIC!\n";
        _ = unistd.write(2, err_msg.ptr, err_msg.len);
    }
    stdlib.exit(1);
}

/// Map Zig errors to positive POSIX errno integers shared by user-space servers
pub fn toCError(err: anyerror) c_int {
    return switch (err) {
        error.PermissionDenied => errno.EACCES,
        error.InvalidArgument => errno.EINVAL,
        error.OutOfMemory => errno.ENOMEM,
        error.NoEntry => errno.ENOENT,
        error.IoError => errno.EIO,
        error.Busy => errno.EBUSY,
        error.Timeout => errno.ETIMEDOUT,
        error.NotSupported => errno.ENOSYS,
        error.NoDevice => errno.ENODEV,
        error.FileNotFound => errno.ENOENT,
        error.AlreadyExists => errno.EEXIST,
        error.BadFileDescriptor => errno.EBADF,
        error.BadSeek => errno.ESPIPE,
        error.IsDir => errno.EISDIR,
        error.NotDir => errno.ENOTDIR,
        error.NoSpaceLeft => errno.ENOSPC,
        error.NameTooLong => errno.ENAMETOOLONG,
        error.BrokenPipe => errno.EPIPE,
        error.ResourceLimit => errno.EAGAIN,
        error.OperationNotPermitted => errno.EPERM,
        else => errno.EIO,
    };
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
    if (stdlib.malloc(len)) |ptr| {
        return @ptrCast(ptr);
    }
    return null;
}

fn free(_: *anyopaque, buf: []u8, _: std.mem.Alignment, _: usize) void {
    stdlib.free(buf.ptr);
}
