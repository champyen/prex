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

// bsp/boot/riscv/arch/elf_reloc.zig — RISC-V ELF relocation engine.
// Replaces bsp/boot/riscv/arch/elf_reloc.c.

const ffi = @import("ffi");
const cfg = ffi.cfg;
const elf_t = ffi.elf.types;
const riscv = ffi.elf.riscv;

inline fn DPRINTF(comptime format: [*c]const u8, args: anytype) void {
    if (cfg.DEBUG) {
        @call(.auto, ffi.boot.printf, .{format} ++ args);
    }
}

// A small LUT to store the calculated offset of HI20 relocations,
// so they can be retrieved by the following LO12 relocations.
const MAX_HI20 = 256;
var hi20_lut = [_]struct {
    addr: elf_t.Addr,
    offset: i32,
}{.{ .addr = 0, .offset = 0 }} ** MAX_HI20;
var hi20_idx: usize = 0;

fn add_hi20(addr: elf_t.Addr, offset: i32) void {
    hi20_lut[hi20_idx].addr = addr;
    hi20_lut[hi20_idx].offset = offset;
    hi20_idx = (hi20_idx + 1) % MAX_HI20;
}

fn find_hi20(addr: elf_t.Addr) i32 {
    var i: usize = 0;
    while (i < MAX_HI20) : (i += 1) {
        if (hi20_lut[i].addr == addr) {
            const off = hi20_lut[i].offset;
            hi20_lut[i].addr = 0; // Clear it
            return off;
        }
    }
    return 0;
}

pub export fn relocate_rela(
    rela: *elf_t.Rela,
    sym_val: elf_t.Addr,
    target_sect: [*]u8,
) callconv(.c) c_int {
    const where: [*]align(1) elf_t.Addr = @ptrCast(target_sect + rela.r_offset);
    const val: elf_t.Addr = sym_val + @as(elf_t.Addr, @bitCast(rela.r_addend));
    const r_type = rel_type_cast(rela.r_info & 0xff);

    switch (r_type) {
        riscv.R_RISCV_NONE, riscv.R_RISCV_RELAX, riscv.R_RISCV_ALIGN => {},

        riscv.R_RISCV_32 => {
            where[0] = val;
        },

        riscv.R_RISCV_HI20 => {
            const offset: i32 = @bitCast(val);
            const hi: u32 = @bitCast((offset + 0x800) >> 12);
            where[0] = (where[0] & 0x00000fff) | (hi << 12);
        },

        riscv.R_RISCV_LO12_I => {
            const offset: i32 = @bitCast(val);
            const lo: u32 = @bitCast(offset & 0xfff);
            where[0] = (where[0] & 0x000fffff) | (lo << 20);
        },

        riscv.R_RISCV_LO12_S => {
            const offset: i32 = @bitCast(val);
            const lo: u32 = @bitCast(offset & 0xfff);
            where[0] = (where[0] & 0x01fff07f) | ((lo & 0xfe0) << 20) | ((lo & 0x01f) << 7);
        },

        riscv.R_RISCV_PCREL_HI20 => {
            const offset: i32 = @bitCast(val - @intFromPtr(where));
            const hi: u32 = @bitCast((offset + 0x800) >> 12);
            where[0] = (where[0] & 0x00000fff) | (hi << 12);
            add_hi20(@intFromPtr(where), offset);
        },

        riscv.R_RISCV_PCREL_LO12_I => {
            const offset = find_hi20(sym_val);
            const lo: u32 = @bitCast(offset & 0xfff);
            where[0] = (where[0] & 0x000fffff) | (lo << 20);
        },

        riscv.R_RISCV_PCREL_LO12_S => {
            const offset = find_hi20(sym_val);
            const lo: u32 = @bitCast(offset & 0xfff);
            where[0] = (where[0] & 0x01fff07f) | ((lo & 0xfe0) << 20) | ((lo & 0x01f) << 7);
        },

        riscv.R_RISCV_CALL, riscv.R_RISCV_CALL_PLT => {
            const offset: i32 = @bitCast(val - @intFromPtr(where));
            const hi: u32 = @bitCast((offset + 0x800) >> 12);
            const lo: u32 = @bitCast(offset & 0xfff);
            // Patch auipc
            where[0] = (where[0] & 0x00000fff) | (hi << 12);
            // Patch jalr
            const jalr_ptr: *align(1) elf_t.Addr = @ptrCast(&where[1]);
            jalr_ptr.* = (jalr_ptr.* & 0x000fffff) | (lo << 20);
        },

        riscv.R_RISCV_BRANCH => {
            const offset: i32 = @bitCast(val - @intFromPtr(where));
            where[0] = (where[0] & 0x01fff07f) |
                ((@as(u32, @bitCast((offset >> 12) & 0x01))) << 31) |
                ((@as(u32, @bitCast((offset >> 5) & 0x3f))) << 25) |
                ((@as(u32, @bitCast((offset >> 1) & 0x0f))) << 8) |
                ((@as(u32, @bitCast((offset >> 11) & 0x01))) << 7);
        },

        riscv.R_RISCV_JAL => {
            const offset: i32 = @bitCast(val - @intFromPtr(where));
            where[0] = (where[0] & 0x0000007f) |
                ((@as(u32, @bitCast((offset >> 20) & 0x01))) << 31) |
                ((@as(u32, @bitCast((offset >> 1) & 0x3ff))) << 21) |
                ((@as(u32, @bitCast((offset >> 11) & 0x01))) << 20) |
                ((@as(u32, @bitCast((offset >> 12) & 0xff))) << 12);
        },

        riscv.R_RISCV_ADD32 => {
            where[0] += val;
        },

        riscv.R_RISCV_SUB32 => {
            where[0] -= val;
        },

        riscv.R_RISCV_32_PCREL => {
            where[0] = val - @intFromPtr(where);
        },

        riscv.R_RISCV_SUB8 => {
            const ptr: *u8 = @ptrCast(where);
            ptr.* = @bitCast(@as(i8, @bitCast(ptr.*)) - @as(i8, @intCast(val)));
        },

        riscv.R_RISCV_SUB16 => {
            const ptr: *align(1) u16 = @ptrCast(where);
            ptr.* = @bitCast(@as(i16, @bitCast(ptr.*)) - @as(i16, @intCast(val)));
        },

        riscv.R_RISCV_SUB6 => {
            const ptr: *u8 = @ptrCast(where);
            ptr.* = (ptr.* & 0xc0) | @as(u8, @bitCast((@as(i8, @bitCast(ptr.* & 0x3f)) - @as(i8, @intCast(val & 0x3f))) & 0x3f));
        },

        riscv.R_RISCV_SET6 => {
            const ptr: *u8 = @ptrCast(where);
            ptr.* = (ptr.* & 0xc0) | @as(u8, @intCast(val & 0x3f));
        },

        riscv.R_RISCV_SET8 => {
            const ptr: *u8 = @ptrCast(where);
            ptr.* = @intCast(val);
        },

        riscv.R_RISCV_SET16 => {
            const ptr: *align(1) u16 = @ptrCast(where);
            ptr.* = @intCast(val);
        },

        riscv.R_RISCV_SET32 => {
            where[0] = val;
        },

        else => {
            DPRINTF("RISCV-BOOT: Unknown reloc type %d at %lx sym_val=%lx\n", .{ @as(c_int, @intCast(r_type)), @as(c_ulong, @intCast(@intFromPtr(where))), @as(c_ulong, @intCast(sym_val)) });
            return -1;
        },
    }
    return 0;
}

pub export fn relocate_rel(
    _: [*]elf_t.Rel,
    _: elf_t.Addr,
    _: [*]u8,
) callconv(.c) c_int {
    return -1;
}

inline fn rel_type_cast(val: u64) u32 {
    return @intCast(val);
}
