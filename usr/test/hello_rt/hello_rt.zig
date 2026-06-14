const std = @import("std");
const prex = @import("prex");

pub const panic = prex.panic;

export fn main(_: i32, _: [*][*:0]u8, _: [*][*:0]u8) callconv(.c) i32 {
    prex.print("\nHello from Native Zig RT Task!\n", .{});
    
    var ticks: u32 = 0;
    _ = prex.c.sys_time(&ticks);
    prex.print("Current ticks: {}\n", .{ticks});

    prex.print("Zig RT task exiting...\n", .{});
    return 0;
}
