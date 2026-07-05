// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
// All rights reserved.

const ffi = @import("ffi");

const UART_BASE = ffi.cfg.CONFIG_NS16550_PHY_BASE;

const UART_THR: *volatile u8 = @ptrFromInt(UART_BASE + 0);
const UART_IER: *volatile u8 = @ptrFromInt(UART_BASE + 1);
const UART_FCR: *volatile u8 = @ptrFromInt(UART_BASE + 2);
const UART_LCR: *volatile u8 = @ptrFromInt(UART_BASE + 3);
const UART_MCR: *volatile u8 = @ptrFromInt(UART_BASE + 4);
const UART_LSR: *volatile u8 = @ptrFromInt(UART_BASE + 5);

const LSR_THRE = 0x20;

pub export fn debug_putc(c: c_int) callconv(.c) void {
    if (c == '\n') {
        while ((UART_LSR.* & LSR_THRE) == 0) {}
        UART_THR.* = '\r';
    }
    while ((UART_LSR.* & LSR_THRE) == 0) {}
    UART_THR.* = @intCast(@as(u8, @intCast(c)));
}

pub export fn debug_init() callconv(.c) void {
    // Minimal initialization for NS16550
    UART_IER.* = 0x00; // Disable interrupts
    UART_LCR.* = 0x03; // 8N1
    UART_FCR.* = 0x07; // Enable & Clear FIFO
    UART_MCR.* = 0x00; // No modem control
}
