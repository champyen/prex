// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2005-2009, Kohsuke Ohtani
// Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
// All rights reserved.

const ffi = @import("ffi");

extern fn outb(port: c_int, val: u8) callconv(.c) void;
extern fn inb(port: c_int) callconv(.c) u8;

const COM_BASE = ffi.cfg.CONFIG_NS16550_BASE;

// Register offsets
const COM_RBR = COM_BASE + 0x00; // receive buffer register
const COM_THR = COM_BASE + 0x00; // transmit holding register
const COM_IER = COM_BASE + 0x01; // interrupt enable register
const COM_FCR = COM_BASE + 0x02; // FIFO control register
const COM_LCR = COM_BASE + 0x03; // line control register
const COM_MCR = COM_BASE + 0x04; // modem control register
const COM_LSR = COM_BASE + 0x05; // line status register
const COM_DLL = COM_BASE + 0x00; // divisor latch LSB (LCR[7] = 1)
const COM_DLM = COM_BASE + 0x01; // divisor latch MSB (LCR[7] = 1)

pub fn debug_putc(c: c_int) void {
    // output to serial port.
    while ((inb(@intCast(COM_LSR)) & 0x20) == 0) {}
    outb(@intCast(COM_THR), @intCast(@as(u8, @intCast(c))));

    if (ffi.cfg.DEBUG and ffi.cfg.CONFIG_DIAG_BOCHS) {
        // output to bochs emulator console.
        if (inb(0xe9) == 0xe9) {
            outb(0xe9, @intCast(@as(u8, @intCast(c))));
        }
    }
}

pub fn debug_init() void {
    // Initialize serial port.
    if (inb(@intCast(COM_LSR)) == 0xff) {
        return; // Serial port is disabled
    }

    outb(@intCast(COM_IER), 0x00); // Disable interrupt
    outb(@intCast(COM_LCR), 0x80); // Access baud rate
    outb(@intCast(COM_DLL), 0x01); // 115200 baud
    outb(@intCast(COM_DLM), 0x00);
    outb(@intCast(COM_LCR), 0x03); // N, 8, 1
    outb(@intCast(COM_MCR), 0x03); // Ready
    outb(@intCast(COM_FCR), 0x00); // Disable FIFO
    _ = inb(@intCast(COM_RBR));
    _ = inb(@intCast(COM_RBR));
}
