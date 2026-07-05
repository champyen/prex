// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
// All rights reserved.

const ffi = @import("ffi");

const UART_BASE = ffi.cfg.CONFIG_PL011_PHY_BASE;

const UART_DR: *volatile u32 = @ptrFromInt(UART_BASE + 0x00);
const UART_FR: *volatile u32 = @ptrFromInt(UART_BASE + 0x18);

const FR_TXFF = 0x20;

pub export fn debug_putc(c: c_int) callconv(.c) void {
    while ((UART_FR.* & FR_TXFF) != 0) {}
    UART_DR.* = @intCast(@as(u8, @intCast(c)));
}

pub export fn debug_init() callconv(.c) void {
}
