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
