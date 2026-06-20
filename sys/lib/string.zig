const std = @import("std");

comptime {
    @export(&strlen, .{ .name = "strlen", .linkage = .strong });
    @export(&strlcpy, .{ .name = "strlcpy", .linkage = .strong });
    @export(&strncmp, .{ .name = "strncmp", .linkage = .strong });
    @export(&strnlen, .{ .name = "strnlen", .linkage = .strong });
    @export(&memcpy, .{ .name = "memcpy", .linkage = .strong });
    @export(&memset, .{ .name = "memset", .linkage = .strong });
    @export(&memmove, .{ .name = "memmove", .linkage = .strong });
}

fn strlen(str: [*c]const u8) callconv(.c) usize {
    var i: usize = 0;
    while (str[i] != 0) : (i += 1) {}
    return i;
}

fn strlcpy(dest: [*c]u8, src: [*c]const u8, count: usize) callconv(.c) usize {
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

fn strncmp(src: [*c]const u8, tgt: [*c]const u8, count: usize) callconv(.c) c_int {
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

fn strnlen(str: [*c]const u8, count: usize) callconv(.c) usize {
    var s = str;
    var n = count;
    while (n != 0 and s[0] != 0) : (n -= 1) {
        s += 1;
    }
    return @intFromPtr(s) - @intFromPtr(str);
}

fn memcpy(dest: ?*anyopaque, src: ?*const anyopaque, count: usize) callconv(.c) ?*anyopaque {
    if (count == 0) return dest;
    const d: [*]volatile u8 = @ptrCast(dest.?);
    const s: [*]volatile const u8 = @ptrCast(src.?);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        d[i] = s[i];
    }
    return dest;
}

fn memset(dest: ?*anyopaque, ch: c_int, count: usize) callconv(.c) ?*anyopaque {
    if (count == 0) return dest;
    const d: [*]volatile u8 = @ptrCast(dest.?);
    const byte: u8 = @truncate(@as(c_uint, @bitCast(ch)));
    var i: usize = 0;
    while (i < count) : (i += 1) {
        d[i] = byte;
    }
    return dest;
}

fn memmove(dest: ?*anyopaque, src: ?*const anyopaque, count: usize) callconv(.c) ?*anyopaque {
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
