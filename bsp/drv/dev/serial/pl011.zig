const std = @import("std");
const dki = @import("dki");
const c = dki.c;

// Configure constants from Prex configuration
const UART_BASE = c.CONFIG_PL011_BASE;
const UART_IRQ = c.CONFIG_PL011_IRQ;
const UART_CLK = c.CONFIG_PL011_CLK;
const BAUD_RATE = 115200;

// UART Registers
const UART_DR = (UART_BASE + 0x00);
const UART_RSR = (UART_BASE + 0x04);
const UART_ECR = (UART_BASE + 0x04);
const UART_FR = (UART_BASE + 0x18);
const UART_IBRD = (UART_BASE + 0x24);
const UART_FBRD = (UART_BASE + 0x28);
const UART_LCRH = (UART_BASE + 0x2C);
const UART_CR = (UART_BASE + 0x30);
const UART_IFLS = (UART_BASE + 0x34);
const UART_IMSC = (UART_BASE + 0x38);
const UART_RIS = (UART_BASE + 0x3C);
const UART_MIS = (UART_BASE + 0x40);
const UART_ICR = (UART_BASE + 0x44);

// Flag register
const FR_RXFE = 0x10; // Receive FIFO empty
const FR_TXFF = 0x20; // Transmit FIFO full

// Masked interrupt status register
const MIS_RX = 0x10; // Receive interrupt
const MIS_TX = 0x20; // Transmit interrupt
const MIS_RT = 0x40; // Timeout interrupt

// Interrupt clear register
const ICR_RX = 0x10; // Clear receive interrupt
const ICR_TX = 0x20; // Clear transmit interrupt
const ICR_RT = 0x40; // Clear timeout interrupt

// Line control register (High)
const LCRH_WLEN8 = 0x60; // 8 bits
const LCRH_FEN = 0x10; // Enable FIFO

// Control register
const CR_UARTEN = 0x0001; // UART enable
const CR_TXE = 0x0100; // Transmit enable
const CR_RXE = 0x0200; // Receive enable

// Interrupt mask set/clear register
const IMSC_RX = 0x10; // Receive interrupt mask
const IMSC_TX = 0x20; // Transmit interrupt mask
const IMSC_RT = 0x40; // Timeout interrupt mask

/// Static serial port implementation
const SerialInterface = struct {
    pub fn xmt_char(_: ?*c.struct_serial_port, ch: u8) callconv(.c) void {
        while (dki.bus_read_32(UART_FR) & FR_TXFF != 0) {}
        dki.bus_write_32(UART_DR, @as(u32, ch));
    }

    pub fn rcv_char(_: ?*c.struct_serial_port) callconv(.c) u8 {
        while (dki.bus_read_32(UART_FR) & FR_RXFE != 0) {}
        return @as(u8, @intCast(dki.bus_read_32(UART_DR) & 0xff));
    }

    pub fn set_poll(_: ?*c.struct_serial_port, on: c_int) callconv(.c) void {
        if (on != 0) {
            dki.bus_write_32(UART_IMSC, 0);
        } else {
            dki.bus_write_32(UART_IMSC, (IMSC_RX | IMSC_RT));
        }
    }

    pub fn start(sp: ?*c.struct_serial_port) callconv(.c) void {
        startZig(sp) catch |err| {
            dki.log("PL011: Start failed: {}\n", .{err});
        };
    }

    fn startZig(sp: ?*c.struct_serial_port) !void {
        dki.bus_write_32(UART_CR, 0); // Disable everything
        dki.bus_write_32(UART_ICR, 0x07ff); // Clear all interrupt status

        const divider: u32 = @as(u32, @intCast(UART_CLK / (16 * BAUD_RATE)));
        const remainder: u32 = @as(u32, @intCast(UART_CLK % (16 * BAUD_RATE)));
        var fraction: u32 = @as(u32, @intCast(8 * remainder / BAUD_RATE)) >> 1;
        fraction += @as(u32, @intCast(8 * remainder / BAUD_RATE)) & 1;
        dki.bus_write_32(UART_IBRD, divider);
        dki.bus_write_32(UART_FBRD, fraction);

        dki.bus_write_32(UART_LCRH, (LCRH_WLEN8 | LCRH_FEN));
        dki.bus_write_32(UART_CR, (CR_RXE | CR_TXE | CR_UARTEN));

        // Use try for idiomatic error handling
        sp.?.irq = try dki.irq_attach(UART_IRQ, c.IPL_COMM, 0, pl011_isr, pl011_ist, sp);

        dki.bus_write_32(UART_IMSC, (IMSC_RX | IMSC_RT));
    }

    pub fn stop(_: ?*c.struct_serial_port) callconv(.c) void {
        dki.bus_write_32(UART_IMSC, 0);
        dki.bus_write_32(UART_CR, 0);
    }
};

export fn pl011_isr(_: ?*anyopaque) callconv(.c) c_int {
    const mis = dki.bus_read_32(UART_MIS);
    if (mis == 0) return c.INT_DONE;

    dki.bus_write_32(UART_IMSC, 0);

    if (@hasDecl(c, "CONFIG_ARMV8M")) {
        _ = dki.bus_read_32(UART_IMSC);
        const icpr1: *volatile u32 = @ptrFromInt(0xE000E284);
        icpr1.* = 0x80;
    }

    return c.INT_CONTINUE;
}

export fn pl011_ist(arg: ?*anyopaque) callconv(.c) void {
    const sp: *c.struct_serial_port = @ptrCast(@alignCast(arg.?));
    
    // Use defer to guarantee interrupts are re-enabled
    defer dki.bus_write_32(UART_IMSC, (IMSC_RX | IMSC_RT));
    
    const ris = dki.bus_read_32(UART_RIS);

    if (ris & (MIS_RX | MIS_RT) != 0) {
        while (true) {
            const val = dki.bus_read_32(UART_DR);
            c.serial_rcv_char(sp, @as(u8, @intCast(val & 0xff)));
            if (dki.bus_read_32(UART_FR) & FR_RXFE != 0) break;
        }
        dki.bus_write_32(UART_ICR, (ICR_RX | ICR_RT));
    }
    
    if (ris & MIS_TX != 0) {
        c.serial_xmt_done(sp);
        dki.bus_write_32(UART_ICR, ICR_TX);
    }
}

var pl011_port: c.struct_serial_port = undefined;
var pl011_ops: c.struct_serial_ops = undefined;

export var pl011_driver = dki.Driver{
    .name = "pl011",
    .devops = null,
    .devsz = 0,
    .flags = 0,
    .probe = null,
    .init = pl011_init,
    .unload = null,
};

export fn pl011_init(_: ?*dki.Driver) callconv(.c) c_int {
    // Apply static interface pattern using the improved generic wrap
    pl011_ops = dki.wrap(c.struct_serial_ops, SerialInterface);
    c.serial_attach(&pl011_ops, &pl011_port);
    return 0;
}
