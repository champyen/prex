const std = @import("std");
const builtin = @import("builtin");

extern fn diag_puts([*c]const u8) void;
extern fn machine_abort() noreturn;

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    diag_puts("KERNEL PANIC: ");
    var buf: [256]u8 = undefined;
    const len = @min(msg.len, buf.len - 2);
    @memcpy(buf[0..len], msg[0..len]);
    buf[len] = '\n';
    buf[len + 1] = 0;
    diag_puts(@ptrCast(&buf));
    machine_abort();
}

comptime {
    if (builtin.cpu.arch == .arm or builtin.cpu.arch == .thumb) {
        @export(&__aeabi_memcpy, .{ .name = "__aeabi_memcpy", .linkage = .strong });
        @export(&__aeabi_memcpy, .{ .name = "__aeabi_memcpy4", .linkage = .strong });
        @export(&__aeabi_memcpy, .{ .name = "__aeabi_memcpy8", .linkage = .strong });
        @export(&__aeabi_memset, .{ .name = "__aeabi_memset", .linkage = .strong });
        @export(&__aeabi_memset, .{ .name = "__aeabi_memset4", .linkage = .strong });
        @export(&__aeabi_memset, .{ .name = "__aeabi_memset8", .linkage = .strong });
        @export(&__aeabi_memclr, .{ .name = "__aeabi_memclr", .linkage = .strong });
        @export(&__aeabi_memclr, .{ .name = "__aeabi_memclr4", .linkage = .strong });
        @export(&__aeabi_memclr, .{ .name = "__aeabi_memclr8", .linkage = .strong });
        @export(&__aeabi_memmove, .{ .name = "__aeabi_memmove", .linkage = .strong });
        @export(&__aeabi_memmove, .{ .name = "__aeabi_memmove4", .linkage = .strong });
        @export(&__aeabi_memmove, .{ .name = "__aeabi_memmove8", .linkage = .strong });
    }
}

fn __aeabi_memcpy(dest: ?*anyopaque, src: ?*const anyopaque, n: usize) callconv(.c) void {
    @setRuntimeSafety(false);
    const d: [*]volatile u8 = @ptrCast(dest);
    const s: [*]volatile const u8 = @ptrCast(src);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        d[i] = s[i];
    }
}

fn __aeabi_memset(dest: ?*anyopaque, n: usize, val: c_int) callconv(.c) void {
    @setRuntimeSafety(false);
    const d: [*]volatile u8 = @ptrCast(dest);
    const v: u8 = @intCast(val & 0xFF);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        d[i] = v;
    }
}

fn __aeabi_memclr(dest: ?*anyopaque, n: usize) callconv(.c) void {
    __aeabi_memset(dest, n, 0);
}

fn __aeabi_memmove(dest: ?*anyopaque, src: ?*const anyopaque, n: usize) callconv(.c) void {
    @setRuntimeSafety(false);
    const d: [*]volatile u8 = @ptrCast(dest);
    const s: [*]volatile const u8 = @ptrCast(src);
    if (@intFromPtr(d) < @intFromPtr(s)) {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            d[i] = s[i];
        }
    } else {
        var i: usize = n;
        while (i > 0) {
            i -= 1;
            d[i] = s[i];
        }
    }
}
