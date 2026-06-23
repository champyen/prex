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

/// Prex+ Driver-Kernel Interface (DKI) Wrapper for Zig
pub const c = @cImport({
    @cDefine("__builtin_va_list", "void *");
    @cDefine("y", "1");
    @cInclude("conf/config.h");
    @cInclude("sys/param.h");
    @cInclude("dki.h");
    @cInclude("ddi.h");
    @cInclude("sys/errno.h");
    @cInclude("sys/device.h");
    @cInclude("vio_mmio.h");
    @cInclude("serial.h");
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
        error.Readonly => c.EROFS,
        else => c.EIO,
    };
}

/// Device operations structure with type-safe, optional C-calling convention pointers
pub const DevOps = extern struct {
    open: ?*const fn (c.device_t, c_int) callconv(.c) c_int = null,
    close: ?*const fn (c.device_t) callconv(.c) c_int = null,
    read: ?*const fn (c.device_t, [*]c_char, *usize, c_int) callconv(.c) c_int = null,
    write: ?*const fn (c.device_t, [*]const c_char, *usize, c_int) callconv(.c) c_int = null,
    ioctl: ?*const fn (c.device_t, c_ulong, ?*anyopaque) callconv(.c) c_int = null,
    devctl: ?*const fn (c.device_t, c_ulong, ?*anyopaque) callconv(.c) c_int = null,
};

/// Metaprogramming helper to build a C-compatible jump table from a static implementation struct.
/// This enforces the interface at compile time.
pub fn wrap(comptime Target: type, comptime Impl: type) Target {
    var result: Target = undefined;
    inline for (std.meta.fields(Target)) |field| {
        @field(result, field.name) = if (@hasDecl(Impl, field.name))
            @field(Impl, field.name)
        else
            null;
    }
    return result;
}

/// Driver object structure
pub const Driver = extern struct {
    name: [*:0]const u8,
    devops: ?*const DevOps,
    devsz: usize,
    flags: c_int,
    probe: ?*const fn (?*Driver) callconv(.c) c_int = null,
    init: ?*const fn (?*Driver) callconv(.c) c_int = null,
    unload: ?*const fn (?*Driver) callconv(.c) c_int = null,
};

// --- Memory Management ---

pub inline fn ptokv(pa: anytype) [*]u8 {
    const offset = if (@hasDecl(c, "KERNOFFSET")) c.KERNOFFSET else 0;
    return @ptrFromInt(@as(usize, @intCast(pa)) + offset);
}

pub inline fn kvtop(va: anytype) usize {
    const offset = if (@hasDecl(c, "KERNOFFSET")) c.KERNOFFSET else 0;
    return @intFromPtr(va) - offset;
}

/// Custom allocator that wraps Prex+ kmem_alloc and kmem_free
pub const allocator = std.mem.Allocator{
    .ptr = undefined,
    .vtable = &.{
        .alloc = alloc,
        .resize = std.mem.Allocator.noResize,
        .remap = std.mem.Allocator.noRemap,
        .free = free,
    },
};

fn alloc(_: *anyopaque, len: usize, ptr_align: std.mem.Alignment, _: usize) ?[*]u8 {
    const alignment = ptr_align.toByteUnits();
    if (alignment <= 4) {
        if (c.kmem_alloc(len)) |ptr| {
            return @ptrCast(ptr);
        }
        return null;
    }
    const total_len = len + alignment;
    const raw_ptr = c.kmem_alloc(total_len) orelse return null;
    const addr = @intFromPtr(raw_ptr);
    const aligned_addr = (addr + alignment - 1) & ~(alignment - 1);
    return @ptrFromInt(aligned_addr);
}

fn free(_: *anyopaque, buf: []u8, _: std.mem.Alignment, _: usize) void {
    c.kmem_free(buf.ptr);
}

pub inline fn kmem_alloc(size: usize) ?*anyopaque {
    return c.kmem_alloc(size);
}

pub inline fn kmem_free(ptr: ?*anyopaque) void {
    c.kmem_free(ptr);
}

pub inline fn page_alloc(size: usize) usize {
    return c.page_alloc(size);
}

// --- Type-safe DKI Wrappers ---

pub const IST_NONE: ?*const fn (?*anyopaque) callconv(.c) void = @ptrFromInt(@as(usize, @bitCast(@as(isize, -1))));

pub fn log(comptime fmt: []const u8, args: anytype) void {
    if (args.len == 0) {
        _ = c.printf(fmt.ptr);
    } else {
        var buf: [256]u8 = undefined;
        if (std.fmt.bufPrint(&buf, fmt, args)) |msg| {
            var term_buf: [257]u8 = undefined;
            @memcpy(term_buf[0..msg.len], msg);
            term_buf[msg.len] = 0;
            _ = c.printf(@ptrCast(&term_buf));
        } else |_| {
            _ = c.printf("log formatting failed\n");
        }
    }
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = error_return_trace;
    _ = ret_addr;
    _ = c.printf("ZIG PANIC: ");
    _ = c.printf(@ptrCast(msg.ptr));
    _ = c.printf("\n");
    while (true) {}
}

pub inline fn device_create(drv: *const Driver, name: [*:0]const u8, flags: c_int) !c.device_t {
    const dev = c.device_create(@ptrCast(@constCast(drv)), name, flags);
    if (dev == 0) return error.Fault;
    return dev;
}

pub inline fn device_private(dev: c.device_t) ?*anyopaque {
    return c.device_private(dev);
}

pub inline fn kmem_map(ptr: ?*anyopaque, size: usize) !*anyopaque {
    if (c.kmem_map(ptr, size)) |kptr| {
        return kptr;
    }
    return error.Fault;
}

pub inline fn irq_attach(irqno: c_int, prio: c_int, shared: c_int, isr: ?*const fn (?*anyopaque) callconv(.c) c_int, ist: ?*const fn (?*anyopaque) callconv(.c) void, arg: ?*anyopaque) !c.irq_t {
    const irq = c.irq_attach(irqno, prio, shared, isr, ist, arg);
    if (irq == 0) return error.Fault;
    return irq;
}

pub inline fn irq_detach(irq: c.irq_t) void {
    c.irq_detach(irq);
}

pub fn event_init(event: *c.struct_event, name: [*:0]const u8) void {
    event.sleepq.next = @ptrCast(&event.sleepq);
    event.sleepq.prev = @ptrCast(&event.sleepq);
    event.name = name;
}

pub inline fn sched_lock() void {
    c.sched_lock();
}

pub inline fn sched_unlock() void {
    c.sched_unlock();
}

pub inline fn sched_sleep(event: *c.struct_event) void {
    _ = c.sched_sleep(event);
}

pub inline fn sched_wakeup(event: *c.struct_event) void {
    c.sched_wakeup(event);
}

pub inline fn delay_usec(usec: c_ulong) void {
    c.delay_usec(usec);
}

pub inline fn memoryBarrier() void {
    asm volatile ("" ::: .{ .memory = true });
}

// --- Bus I/O Wrappers ---

pub inline fn bus_read_8(addr: usize) u8 {
    const p: *volatile u8 = @ptrFromInt(addr);
    return p.*;
}

pub inline fn bus_read_16(addr: usize) u16 {
    const p: *volatile u16 = @ptrFromInt(addr);
    return p.*;
}

pub inline fn bus_read_32(addr: usize) u32 {
    const p: *volatile u32 = @ptrFromInt(addr);
    return p.*;
}

pub inline fn bus_write_8(addr: usize, val: u8) void {
    const p: *volatile u8 = @ptrFromInt(addr);
    p.* = val;
}

pub inline fn bus_write_16(addr: usize, val: u16) void {
    const p: *volatile u16 = @ptrFromInt(addr);
    p.* = val;
}

pub inline fn bus_write_32(addr: usize, val: u32) void {
    const p: *volatile u32 = @ptrFromInt(addr);
    p.* = val;
}

// --- AEABI Memory Helpers ---
const builtin = @import("builtin");

comptime {
    if (builtin.cpu.arch == .arm or builtin.cpu.arch == .thumb) {
        @export(&__aeabi_memcpy, .{ .name = "__aeabi_memcpy", .linkage = .weak });
        @export(&__aeabi_memcpy, .{ .name = "__aeabi_memcpy4", .linkage = .weak });
        @export(&__aeabi_memcpy, .{ .name = "__aeabi_memcpy8", .linkage = .weak });
        @export(&__aeabi_memset, .{ .name = "__aeabi_memset", .linkage = .weak });
        @export(&__aeabi_memset, .{ .name = "__aeabi_memset4", .linkage = .weak });
        @export(&__aeabi_memset, .{ .name = "__aeabi_memset8", .linkage = .weak });
        @export(&__aeabi_memclr, .{ .name = "__aeabi_memclr", .linkage = .weak });
        @export(&__aeabi_memclr, .{ .name = "__aeabi_memclr4", .linkage = .weak });
        @export(&__aeabi_memclr, .{ .name = "__aeabi_memclr8", .linkage = .weak });
    }
    @export(&strlen, .{ .name = "strlen", .linkage = .weak });
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
