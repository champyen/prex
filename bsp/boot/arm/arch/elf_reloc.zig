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

const elf = @import("ffi").elf;
const mem = @import("ffi").mem;
const boot = @import("ffi").boot;
const cfg = @import("ffi").cfg;
const print = @import("ffi").print;
const panic = @import("panic_mod").panic;

// ARMv8-M relocation globals (defined in bsp/boot/common/elf.c under CONFIG_ARMV8M).
extern var current_symtab: [*]elf.types.Sym;
extern var sram_got_base: elf.types.Addr;
extern var text_vma: elf.types.Addr;
extern var data_vma: elf.types.Addr;
extern var text_runtime: elf.types.Addr;
extern var data_runtime: elf.types.Addr;
extern var elf_type: elf.types.Half;

const R_ARM_GOT_BREL: u32 = 26;

const RelInfo = packed struct(u32) {
    type: u8,
    sym: u24,
};

const Thumb2MovwUpper = packed struct(u16) {
    imm4: u4,
    _pad1: u6,
    i: u1,
    _pad2: u5,
};

const Thumb2MovwLower = packed struct(u16) {
    imm8: u8,
    _pad1: u4,
    imm3: u3,
    _pad2: u1,
};

const ArmMovwInstruction = packed struct(u32) {
    imm12: u12,
    rd: u4,
    imm4: u4,
    opcode: u12,
};

const ArmMovwImmediate = packed struct(u16) {
    imm12: u12,
    imm4: u4,
};

const Thumb2MovwImmediate = packed struct(u16) {
    imm8: u8,
    imm3: u3,
    i: u1,
    imm4: u4,
};

const ArmAddressParts = packed struct(u32) {
    lo16: u16,
    hi16: u16,
};

const Thumb2MovwInstruction = packed struct(u32) {
    upper: Thumb2MovwUpper,
    lower: Thumb2MovwLower,
};

const Thumb2BranchInstruction = packed struct(u32) {
    // upper 16 bits (w[0] in inst_val)
    imm10: u10,
    s: u1,
    opcode: u5,

    // lower 16 bits (w[1] in inst_val)
    imm11: u11,
    j2: u1,
    opcode2: u1,
    j1: u1,
    op: u2,
};

const Thumb2BranchOffset = packed struct(u32) {
    _pad: u1 = 0,
    imm11: u11,
    imm10: u10,
    i2: u1,
    i1: u1,
    s: u1,
    sign_extension: u7,
};

const ArmBranchInstruction = packed struct(u32) {
    imm24_val: u23,
    imm24_sign: u1,
    opcode: u8,
};

const ArmBranchOffset = packed struct(u32) {
    _pad: u2 = 0,
    imm24_val: u23,
    imm24_sign: u1,
    sign_extension: u6,
};

const ArmPrel31Instruction = packed struct(u32) {
    offset_val: u30,
    offset_sign: u1,
    reserved: u1,
};

const ArmPrel31Offset = packed struct(u32) {
    val: u30,
    sign: u1,
    sign_extension: u1,
};

pub fn relocate_rel(
    rel: *elf.types.Rel,
    sym_val: elf.types.Addr,
    target_sect: [*]u8,
) c_int {
    const r_type: u32 = @intCast(rel.r_info & 0xff);
    const is_v8m: bool = mem.is_armv8m;

    const where: [*]align(1) elf.types.Addr = if (is_v8m) blk: {
        if (elf_type == elf.types.ET_EXEC) {
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

    const adj_sym_val: elf.types.Addr = if (is_v8m and elf_type == elf.types.ET_EXEC) blk: {
        const sym: *elf.types.Sym = &current_symtab[@as(RelInfo, @bitCast(rel.r_info)).sym];
        break :blk sym_val - sym.st_value;
    } else sym_val;

    if (is_v8m and r_type == R_ARM_GOT_BREL) {
        const got_offset: elf.types.Addr = where[0];
        const got_entry: [*]align(1) elf.types.Addr = @ptrCast(@as(*anyopaque, @ptrFromInt(sram_got_base + got_offset)));
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
        elf.arm.R_ARM_NONE => {},

        elf.arm.R_ARM_ABS32 => {
            where[0] += ptokv(adj_sym_val);
        },

        elf.arm.R_ARM_REL32 => {},

        elf.arm.R_ARM_MOVW_ABS_NC, elf.arm.R_ARM_MOVT_ABS => {
            const inst: ArmMovwInstruction = @bitCast(where[0]);
            const addend: u32 = @as(u16, @bitCast(ArmMovwImmediate{ .imm12 = inst.imm12, .imm4 = inst.imm4 }));
            const tmp: u32 = ptokv(adj_sym_val) + addend;
            const parts = @as(ArmAddressParts, @bitCast(tmp));
            const target_val = if (r_type == elf.arm.R_ARM_MOVT_ABS) parts.hi16 else parts.lo16;
            const new_imm = @as(ArmMovwImmediate, @bitCast(@as(u16, @intCast(target_val))));
            var new_inst = inst;
            new_inst.imm12 = new_imm.imm12;
            new_inst.imm4 = new_imm.imm4;
            where[0] = @bitCast(new_inst);
        },

        elf.arm.R_ARM_THM_MOVW_ABS_NC, elf.arm.R_ARM_THM_MOVT_ABS => {
            const inst = @as(Thumb2MovwInstruction, @bitCast(where[0]));
            const addend: u32 = @as(u16, @bitCast(Thumb2MovwImmediate{
                .imm8 = inst.lower.imm8,
                .imm3 = inst.lower.imm3,
                .i = inst.upper.i,
                .imm4 = inst.upper.imm4,
            }));
            const tmp: u32 = ptokv(adj_sym_val) + addend;
            const parts = @as(ArmAddressParts, @bitCast(tmp));
            const target_val = if (r_type == elf.arm.R_ARM_THM_MOVT_ABS) parts.hi16 else parts.lo16;
            const new_imm = @as(Thumb2MovwImmediate, @bitCast(@as(u16, @intCast(target_val))));
            var new_inst = inst;
            new_inst.upper.imm4 = new_imm.imm4;
            new_inst.upper.i = new_imm.i;
            new_inst.lower.imm8 = new_imm.imm8;
            new_inst.lower.imm3 = new_imm.imm3;
            where[0] = @bitCast(new_inst);
        },

        elf.arm.R_ARM_THM_CALL, elf.arm.R_ARM_THM_JUMP24 => {
            const inst: Thumb2BranchInstruction = @bitCast(where[0]);

            const i1_bit: u1 = if (inst.j1 == inst.s) 1 else 0;
            const i2_bit: u1 = if (inst.j2 == inst.s) 1 else 0;

            const offset_struct = Thumb2BranchOffset{
                .imm11 = inst.imm11,
                .imm10 = inst.imm10,
                .i2 = i2_bit,
                .i1 = i1_bit,
                .s = inst.s,
                .sign_extension = if (inst.s == 1) @as(u7, 0x7f) else @as(u7, 0),
            };
            const addend: i32 = @bitCast(offset_struct);

            if ((sym_val & 1) != 0) {
                const tmp: i32 = @bitCast(
                    @as(u32, @bitCast(sym_val)) -
                        @as(u32, @intCast(@intFromPtr(where))) +
                        @as(u32, @bitCast(addend)),
                );
                const new_offset = @as(Thumb2BranchOffset, @bitCast(tmp));
                var new_inst = inst;
                new_inst.imm10 = new_offset.imm10;
                new_inst.imm11 = new_offset.imm11;
                new_inst.s = new_offset.s;
                new_inst.j1 = if (new_offset.i1 == new_offset.s) 1 else 0;
                new_inst.j2 = if (new_offset.i2 == new_offset.s) 1 else 0;
                new_inst.opcode2 = 1;
                where[0] = @bitCast(new_inst);
            } else {
                const tmp: i32 = @bitCast(
                    @as(u32, @bitCast(sym_val & ~@as(u32, 3))) -
                        @as(u32, @intCast(@intFromPtr(where) & ~@as(usize, 3))) +
                        @as(u32, @bitCast(addend)),
                );
                const new_offset = @as(Thumb2BranchOffset, @bitCast(tmp));
                var new_inst = inst;
                new_inst.imm10 = new_offset.imm10;
                new_inst.imm11 = new_offset.imm11;
                new_inst.s = new_offset.s;
                new_inst.j1 = if (new_offset.i1 == new_offset.s) 1 else 0;
                new_inst.j2 = if (new_offset.i2 == new_offset.s) 1 else 0;
                new_inst.opcode2 = 0;
                where[0] = @bitCast(new_inst);
            }
        },

        elf.arm.R_ARM_PC24, elf.arm.R_ARM_PLT32, elf.arm.R_ARM_CALL, elf.arm.R_ARM_JUMP24 => {
            const inst: ArmBranchInstruction = @bitCast(where[0]);
            const offset_struct = ArmBranchOffset{
                .imm24_val = inst.imm24_val,
                .imm24_sign = inst.imm24_sign,
                .sign_extension = if (inst.imm24_sign == 1) @as(u6, 0x3f) else @as(u6, 0),
            };
            const addend: i32 = @bitCast(offset_struct);

            const tmp: i32 = @bitCast(
                @as(u32, @bitCast(sym_val)) - @as(u32, @intCast(@intFromPtr(where))) + @as(u32, @bitCast(addend)),
            );
            
            const new_offset = @as(ArmBranchOffset, @bitCast(tmp));
            var new_inst = inst;
            new_inst.imm24_val = new_offset.imm24_val;
            new_inst.imm24_sign = new_offset.imm24_sign;
            where[0] = @bitCast(new_inst);
        },

        elf.arm.R_ARM_V4BX => {},

        elf.arm.R_ARM_PREL31 => {
            const inst: ArmPrel31Instruction = @bitCast(where[0]);
            const offset_struct = ArmPrel31Offset{
                .val = inst.offset_val,
                .sign = inst.offset_sign,
                .sign_extension = inst.offset_sign,
            };
            const addend: i32 = @bitCast(offset_struct);

            const val: u32 = ptokv(sym_val) + @as(u32, @bitCast(addend)) - @intFromPtr(where);
            
            const new_offset = @as(ArmPrel31Offset, @bitCast(val));
            var new_inst = inst;
            new_inst.offset_val = new_offset.val;
            new_inst.offset_sign = new_offset.sign;
            where[0] = @bitCast(new_inst);
        },

        else => {
            print("relocation fail: type={d}\n", .{r_type});
            return -1;
        },
    }
    return 0;
}

pub fn relocate_rela(
    _: [*]elf.types.Rela,
    _: elf.types.Addr,
    _: [*]u8,
) c_int {
            panic("invalid relocation type");
    return -1;
}

inline fn ptokv(pa: u32) u32 {
    return pa + KERNOFFSET;
}

pub const KERNOFFSET: u32 = cfg.KERNOFFSET;
