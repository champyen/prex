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

// bsp/boot/arm/arch/elf_reloc.zig — ARM Cortex-A ELF relocation engine.
// Replaces bsp/boot/arm/arch/elf_reloc.c (MMU + ARMv8-M paths).

const ffi = @import("ffi");
const elf_t = ffi.elf.types;
const arm = ffi.elf.arm;
const c = @import("c").c;

// ARMv8-M relocation globals (defined in bsp/boot/common/elf.c under CONFIG_ARMV8M).
extern var current_symtab: [*]elf_t.Sym;
extern var sram_got_base: elf_t.Addr;
extern var text_vma: elf_t.Addr;
extern var data_vma: elf_t.Addr;
extern var text_runtime: elf_t.Addr;
extern var data_runtime: elf_t.Addr;
extern var elf_type: elf_t.Half;

const R_ARM_GOT_BREL: u32 = 26;

pub export fn relocate_rel(
    rel: *elf_t.Rel,
    sym_val: elf_t.Addr,
    target_sect: [*]u8,
) callconv(.c) c_int {
    const r_type: u32 = @intCast(rel.r_info & 0xff);
    const is_v8m: bool = @hasDecl(c, "CONFIG_ARMV8M");

    const where: [*]align(1) elf_t.Addr = if (is_v8m) blk: {
        if (elf_type == elf_t.ET_EXEC) {
            if (rel.r_offset < data_vma) {
                const addr: u32 = text_runtime + (rel.r_offset - text_vma);
                break :blk @ptrCast(@as(*anyopaque, @ptrFromInt(addr)));
            } else {
                const addr: u32 = data_runtime + (rel.r_offset - data_vma);
                break :blk @ptrCast(@as(*anyopaque, @ptrFromInt(addr)));
            }
        } else {
            break :blk @ptrCast(target_sect + rel.r_offset);
        }
    } else @ptrCast(target_sect + rel.r_offset);

    const adj_sym_val: elf_t.Addr = if (is_v8m and elf_type == elf_t.ET_EXEC) blk: {
        const sym: *elf_t.Sym = &current_symtab[rel.r_info >> 8];
        break :blk sym_val - sym.st_value;
    } else sym_val;

    if (is_v8m and r_type == R_ARM_GOT_BREL) {
        const got_offset: elf_t.Addr = where[0];
        const got_entry: [*]align(1) elf_t.Addr = @ptrCast(@as(*anyopaque, @ptrFromInt(sram_got_base + got_offset)));
        got_entry[0] = ptokv(sym_val);
        return 0;
    }

    if (is_v8m) {
        const where_addr: usize = @intFromPtr(where);
        if (!((where_addr >= 0x20000000 and where_addr < 0x20080000) or
              (where_addr >= 0x30000000 and where_addr < 0x30080000)))
        {
            return 0;
        }
    }

    switch (r_type) {
        arm.R_ARM_NONE => {},

        arm.R_ARM_ABS32 => {
            where[0] += ptokv(adj_sym_val);
        },

        arm.R_ARM_REL32 => {},

        arm.R_ARM_MOVW_ABS_NC => {
            var addend: u32 = where[0];
            addend = ((addend & 0xf0000) >> 4) | (addend & 0xfff);
            const tmp: u32 = ptokv(adj_sym_val) + addend;
            where[0] = (where[0] & 0xfff0f000) | ((tmp & 0xf000) << 4) | (tmp & 0xfff);
        },

        arm.R_ARM_MOVT_ABS => {
            var addend: u32 = where[0];
            addend = ((addend & 0xf0000) >> 4) | (addend & 0xfff);
            var tmp: u32 = ptokv(adj_sym_val) + addend;
            tmp >>= 16;
            where[0] = (where[0] & 0xfff0f000) | ((tmp & 0xf000) << 4) | (tmp & 0xfff);
        },

        arm.R_ARM_THM_MOVW_ABS_NC, arm.R_ARM_THM_MOVT_ABS => {
            const upper_insn: u16 = @intCast(where[0] & 0xffff);
            const lower_insn: u16 = @intCast((where[0] >> 16) & 0xffff);

            const addend: u32 = ((upper_insn & 0x000f) << 12) |
                ((upper_insn & 0x0400) << 1) |
                ((lower_insn & 0x7000) >> 4) |
                (lower_insn & 0x00ff);

            var tmp: u32 = ptokv(adj_sym_val) + addend;
            if (r_type == arm.R_ARM_THM_MOVT_ABS) {
                tmp >>= 16;
            }

            const new_upper: u16 = @intCast(
                (upper_insn & 0xfbf0) |
                    ((tmp & 0xf000) >> 12) |
                    ((tmp & 0x0800) >> 1),
            );
            const new_lower: u16 = @intCast(
                (lower_insn & 0x8f00) |
                    ((tmp & 0x0700) << 4) |
                    (tmp & 0x00ff),
            );
            where[0] = @as(elf_t.Addr, @intCast(new_upper)) |
                (@as(elf_t.Addr, @intCast(new_lower)) << 16);
        },

        arm.R_ARM_THM_CALL, arm.R_ARM_THM_JUMP24 => {
            const w: [*]u16 = @ptrCast(@alignCast(where));
            const upper: u32 = w[0];
            const lower: u32 = w[1];
            const upper_s: u32 = (upper >> 10) & 1;
            const j1: u32 = (lower >> 13) & 1;
            const j2: u32 = (lower >> 11) & 1;
            const i1_bit: u32 = if ((j1 ^ upper_s) != 0) 0 else 1;
            const i2_bit: u32 = if ((j2 ^ upper_s) != 0) 0 else 1;

            var addend: u32 = (upper_s << 31 >> 7) |
                (i1_bit << 23) |
                (i2_bit << 22) |
                ((upper & 0x3ff) << 12) |
                ((lower & 0x7ff) << 1);
            if ((addend & 0x01000000) != 0) {
                addend |= 0xfe000000;
            }

            if ((sym_val & 1) != 0) {
                const tmp: i32 = @bitCast(
                    @as(u32, @bitCast(sym_val)) -
                        @as(u32, @intCast(@intFromPtr(where))) +
                        addend,
                );
                const s: u32 = (@as(u32, @bitCast(tmp)) >> 24) & 1;
                const bi1: u32 = (@as(u32, @bitCast(tmp)) >> 23) & 1;
                const bi2: u32 = (@as(u32, @bitCast(tmp)) >> 22) & 1;
                const bj1: u32 = if (bi1 ^ s != 0) 0 else 1;
                const bj2: u32 = if (bi2 ^ s != 0) 0 else 1;
                w[0] = @intCast(
                    (upper & 0xf800) | (s << 10) | ((@as(u32, @bitCast(tmp)) >> 12) & 0x3ff),
                );
                w[1] = @intCast(
                    (lower & 0xd000) | (bj1 << 13) | (1 << 12) | (bj2 << 11) |
                        ((@as(u32, @bitCast(tmp)) >> 1) & 0x7ff),
                );
            } else {
                const tmp: i32 = @bitCast(
                    @as(u32, @bitCast(sym_val & ~@as(u32, 3))) -
                        @as(u32, @intCast(@intFromPtr(where) & ~@as(usize, 3))) +
                        addend,
                );
                const s: u32 = (@as(u32, @bitCast(tmp)) >> 24) & 1;
                const bi1: u32 = (@as(u32, @bitCast(tmp)) >> 23) & 1;
                const bi2: u32 = (@as(u32, @bitCast(tmp)) >> 22) & 1;
                const bj1: u32 = if (bi1 ^ s != 0) 0 else 1;
                const bj2: u32 = if (bi2 ^ s != 0) 0 else 1;
                w[0] = @intCast(
                    (upper & 0xf800) | (s << 10) | ((@as(u32, @bitCast(tmp)) >> 12) & 0x3ff),
                );
                w[1] = @intCast(
                    (lower & 0xd000) | (bj1 << 13) | (0 << 12) | (bj2 << 11) |
                        ((@as(u32, @bitCast(tmp)) >> 1) & 0x7ff),
                );
            }
        },

        arm.R_ARM_PC24, arm.R_ARM_PLT32, arm.R_ARM_CALL, arm.R_ARM_JUMP24 => {
            var addend: u32 = where[0] & 0x00ffffff;
            if ((addend & 0x00800000) != 0) {
                addend |= 0xff000000;
            }
            const tmp: u32 = sym_val - @intFromPtr(where) + (addend << 2);
            where[0] = (where[0] & 0xff000000) | ((tmp >> 2) & 0x00ffffff);
        },

        arm.R_ARM_V4BX => {},

        arm.R_ARM_PREL31 => {
            const addend: i32 = (@as(i32, @bitCast(where[0])) << 1) >> 1;
            const val: u32 = (
                ptokv(sym_val) + @as(u32, @intCast(addend)) - @intFromPtr(where)
            ) & 0x7fffffff;
            where[0] = (where[0] & 0x80000000) | val;
        },

        else => {
            return -1;
        },
    }
    return 0;
}

pub export fn relocate_rela(
    _: [*]elf_t.Rela,
    _: elf_t.Addr,
    _: [*]u8,
) callconv(.c) c_int {
    return -1;
}

inline fn ptokv(pa: u32) u32 {
    return pa + KERNOFFSET;
}

pub const KERNOFFSET: u32 = ffi.cfg.KERNOFFSET;
