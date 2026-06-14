const std = @import("std");
const posix = @import("posix");

pub const panic = posix.panic;

export fn main(_: i32, _: [*][*:0]u8, _: [*][*:0]u8) callconv(.c) i32 {
    posix.print("Hello from POSIX Zig Program!\n", .{});
    
    const pid = posix.c.getpid();
    posix.print("My PID is: {}\n", .{pid});

    posix.print("Zig POSIX program exiting...\n", .{});
    return 0;
}
