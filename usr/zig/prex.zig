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
