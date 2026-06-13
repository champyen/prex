const std = @import("std");
const builtin = @import("builtin");

/// Core Prex+ symbols for AEABI helpers
pub const c = @cImport({
    @cInclude("ddi.h");
    @cInclude("string.h");
});

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
    }
    @export(&strlen, .{ .name = "strlen", .linkage = .strong });
}

fn strlen(s: [*]const u8) callconv(.c) usize {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
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
