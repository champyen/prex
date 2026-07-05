// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2008-2009, Kohsuke Ohtani
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
// 3. Neither the name of the author nor the names of any co-contributors
//    may be used to endorse or promote products derived from this software
//    without specific prior written permission.
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

const ffi = @import("ffi");

const UART_BASE = ffi.cfg.CONFIG_PL011_PHY_BASE;
const UART_CLK = ffi.cfg.CONFIG_PL011_CLK;
const BAUD_RATE = 115200;

// UART Registers
const UART_DR: *volatile u32 = @ptrFromInt(UART_BASE + 0x00);
const UART_FR: *volatile u32 = @ptrFromInt(UART_BASE + 0x18);
const UART_IBRD: *volatile u32 = @ptrFromInt(UART_BASE + 0x24);
const UART_FBRD: *volatile u32 = @ptrFromInt(UART_BASE + 0x28);
const UART_LCRH: *volatile u32 = @ptrFromInt(UART_BASE + 0x2c);
const UART_CR: *volatile u32 = @ptrFromInt(UART_BASE + 0x30);
const UART_ICR: *volatile u32 = @ptrFromInt(UART_BASE + 0x44);

// Flag register
const FR_TXFF = 0x20; // Transmit FIFO full

// Line control register (High)
const LCRH_WLEN8 = 0x60; // 8 bits
const LCRH_FEN = 0x10;   // Enable FIFO

// Control register
const CR_UARTEN = 0x0001; // UART enable
const CR_TXE = 0x0100;    // Transmit enable
const CR_RXE = 0x0200;    // Receive enable

pub export fn debug_putc(c: c_int) callconv(.c) void {
    if (ffi.cfg.DEBUG and ffi.cfg.CONFIG_DIAG_SERIAL) {
        while ((UART_FR.* & FR_TXFF) != 0) {}
        UART_DR.* = @intCast(@as(u8, @intCast(c)));
    }
}

pub export fn debug_init() callconv(.c) void {
    if (ffi.cfg.DEBUG and ffi.cfg.CONFIG_DIAG_SERIAL) {
        UART_CR.* = 0x0;     // Disable everything
        UART_ICR.* = 0x07ff; // Clear all interrupt status

        // Set baud rate:
        // IBRD = UART_CLK / (16 * BAUD_RATE)
        // FBRD = ROUND((64 * MOD(UART_CLK,(16 * BAUD_RATE))) / (16 * BAUD_RATE))
        const divider = UART_CLK / (16 * BAUD_RATE);
        const remainder = UART_CLK % (16 * BAUD_RATE);
        var fraction = (8 * remainder / BAUD_RATE) >> 1;
        fraction += (8 * remainder / BAUD_RATE) & 1;
        UART_IBRD.* = divider;
        UART_FBRD.* = fraction;

        UART_LCRH.* = (LCRH_WLEN8 | LCRH_FEN);     // N, 8, 1, FIFO enable
        UART_CR.* = (CR_RXE | CR_TXE | CR_UARTEN); // Enable UART
    }
}
