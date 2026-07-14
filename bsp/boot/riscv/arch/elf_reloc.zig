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
const elf = ffi.elf;
const cfg = ffi.cfg;
const boot = ffi.boot;

inline fn DPRINTF(comptime format: []const u8, args: anytype) void {
    if (cfg.DEBUG) {
        ffi.print(format, args);
    }
}

const RelInfo = packed struct(u32) {
    type: u8,
    sym: u24,
};

const RiscvBranchInstruction = packed struct(u32) {
    opcode: u7,
    imm11: u1,
    imm4_1: u4,
    funct3: u3,
    rs1: u5,
    rs2: u5,
    imm10_5: u6,
    imm12: u1,
};

const RiscvJalInstruction = packed struct(u32) {
    opcode: u7,
    rd: u5,
    imm19_12: u8,
    imm11: u1,
    imm10_1: u10,
    imm20: u1,
};

const RiscvBranchOffset = packed struct(u32) {
    _pad: u1 = 0,
    imm4_1: u4,
    imm10_5: u6,
    imm11: u1,
    imm12: u1,
    sign_extension: u19,
};

const RiscvJalOffset = packed struct(u32) {
    _pad: u1 = 0,
    imm10_1: u10,
    imm11: u1,
    imm19_12: u8,
    imm20: u1,
    sign_extension: u11,
};

// A small LUT to store the calculated offset of HI20 relocations,
// so they can be retrieved by the following LO12 relocations.
const MAX_HI20 = 256;
var hi20_lut = [_]struct {
    addr: elf.types.Addr,
    offset: i32,
}{.{ .addr = 0, .offset = 0 }} ** MAX_HI20;
var hi20_idx: usize = 0;

fn add_hi20(addr: elf.types.Addr, offset: i32) void {
    hi20_lut[hi20_idx].addr = addr;
    hi20_lut[hi20_idx].offset = offset;
    hi20_idx = (hi20_idx + 1) % MAX_HI20;
}

fn find_hi20(addr: elf.types.Addr) i32 {
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

const RiscvAddressOffset = packed struct(u32) {
    lo12: i12,
    hi20: i20,
};

const RiscvUTypeInstruction = packed struct(u32) {
    opcode: u7,
    rd: u5,
    imm20: u20,
};

const RiscvITypeInstruction = packed struct(u32) {
    opcode: u7,
    rd: u5,
    funct3: u3,
    rs1: u5,
    imm12: i12,
};

const RiscvSTypeInstruction = packed struct(u32) {
    opcode: u7,
    imm4_0: u5,
    funct3: u3,
    rs1: u5,
    rs2: u5,
    imm11_5: u7,
};

const RiscvSTypeOffset = packed struct(i12) {
    imm4_0: u5,
    imm11_5: u7,
};

pub fn relocate_rela(
    rela: *elf.types.Rela,
    sym_val: elf.types.Addr,
    target_sect: [*]u8,
) c_int {
    const where: [*]align(1) elf.types.Addr = @ptrCast(target_sect + rela.r_offset);
    const val: elf.types.Addr = sym_val + @as(elf.types.Addr, @bitCast(rela.r_addend));
    const r_type = @as(RelInfo, @bitCast(rela.r_info)).type;

    switch (r_type) {
        elf.riscv.R_RISCV_NONE, elf.riscv.R_RISCV_RELAX, elf.riscv.R_RISCV_ALIGN => {},

        elf.riscv.R_RISCV_32 => {
            where[0] = val;
        },

        elf.riscv.R_RISCV_HI20 => {
            const offset: i32 = @bitCast(val);
            const off = @as(RiscvAddressOffset, @bitCast(offset));
            const hi_val: i20 = if (off.lo12 < 0) off.hi20 + 1 else off.hi20;
            
            const inst: RiscvUTypeInstruction = @bitCast(where[0]);
            var new_inst = inst;
            new_inst.imm20 = @bitCast(hi_val);
            where[0] = @bitCast(new_inst);
        },

        elf.riscv.R_RISCV_LO12_I => {
            const offset: i32 = @bitCast(val);
            const off = @as(RiscvAddressOffset, @bitCast(offset));
            
            const inst: RiscvITypeInstruction = @bitCast(where[0]);
            var new_inst = inst;
            new_inst.imm12 = @bitCast(off.lo12);
            where[0] = @bitCast(new_inst);
        },

        elf.riscv.R_RISCV_LO12_S => {
            const offset: i32 = @bitCast(val);
            const off = @as(RiscvAddressOffset, @bitCast(offset));
            const s_off = @as(RiscvSTypeOffset, @bitCast(off.lo12));
            
            const inst: RiscvSTypeInstruction = @bitCast(where[0]);
            var new_inst = inst;
            new_inst.imm4_0 = s_off.imm4_0;
            new_inst.imm11_5 = s_off.imm11_5;
            where[0] = @bitCast(new_inst);
        },

        elf.riscv.R_RISCV_PCREL_HI20 => {
            const offset: i32 = @bitCast(val - @intFromPtr(where));
            const off = @as(RiscvAddressOffset, @bitCast(offset));
            const hi_val: i20 = if (off.lo12 < 0) off.hi20 + 1 else off.hi20;
            
            const inst: RiscvUTypeInstruction = @bitCast(where[0]);
            var new_inst = inst;
            new_inst.imm20 = @bitCast(hi_val);
            where[0] = @bitCast(new_inst);
            add_hi20(@intFromPtr(where), offset);
        },

        elf.riscv.R_RISCV_PCREL_LO12_I => {
            const offset = find_hi20(sym_val);
            const off = @as(RiscvAddressOffset, @bitCast(offset));
            
            const inst: RiscvITypeInstruction = @bitCast(where[0]);
            var new_inst = inst;
            new_inst.imm12 = @bitCast(off.lo12);
            where[0] = @bitCast(new_inst);
        },

        elf.riscv.R_RISCV_PCREL_LO12_S => {
            const offset = find_hi20(sym_val);
            const off = @as(RiscvAddressOffset, @bitCast(offset));
            const s_off = @as(RiscvSTypeOffset, @bitCast(off.lo12));
            
            const inst: RiscvSTypeInstruction = @bitCast(where[0]);
            var new_inst = inst;
            new_inst.imm4_0 = s_off.imm4_0;
            new_inst.imm11_5 = s_off.imm11_5;
            where[0] = @bitCast(new_inst);
        },

        elf.riscv.R_RISCV_CALL, elf.riscv.R_RISCV_CALL_PLT => {
            const offset: i32 = @bitCast(val - @intFromPtr(where));
            const off = @as(RiscvAddressOffset, @bitCast(offset));
            const hi_val: i20 = if (off.lo12 < 0) off.hi20 + 1 else off.hi20;
            
            // Patch auipc
            const auipc_inst: RiscvUTypeInstruction = @bitCast(where[0]);
            var new_auipc = auipc_inst;
            new_auipc.imm20 = @bitCast(hi_val);
            where[0] = @bitCast(new_auipc);
            
            // Patch jalr
            const jalr_inst: RiscvITypeInstruction = @bitCast(where[1]);
            var new_jalr = jalr_inst;
            new_jalr.imm12 = @bitCast(off.lo12);
            where[1] = @bitCast(new_jalr);
        },

        elf.riscv.R_RISCV_BRANCH => {
            const offset: i32 = @bitCast(val - @intFromPtr(where));
            const off_struct = @as(RiscvBranchOffset, @bitCast(offset));
            var inst = @as(RiscvBranchInstruction, @bitCast(where[0]));
            inst.imm12 = off_struct.imm12;
            inst.imm10_5 = off_struct.imm10_5;
            inst.imm4_1 = off_struct.imm4_1;
            inst.imm11 = off_struct.imm11;
            where[0] = @bitCast(inst);
        },

        elf.riscv.R_RISCV_JAL => {
            const offset: i32 = @bitCast(val - @intFromPtr(where));
            const off_struct = @as(RiscvJalOffset, @bitCast(offset));
            var inst = @as(RiscvJalInstruction, @bitCast(where[0]));
            inst.imm20 = off_struct.imm20;
            inst.imm10_1 = off_struct.imm10_1;
            inst.imm11 = off_struct.imm11;
            inst.imm19_12 = off_struct.imm19_12;
            where[0] = @bitCast(inst);
        },

        elf.riscv.R_RISCV_ADD32 => {
            where[0] += val;
        },

        elf.riscv.R_RISCV_SUB32 => {
            where[0] -= val;
        },

        elf.riscv.R_RISCV_32_PCREL => {
            where[0] = val - @intFromPtr(where);
        },

        elf.riscv.R_RISCV_SUB8 => {
            const ptr: *u8 = @ptrCast(where);
            ptr.* = @bitCast(@as(i8, @bitCast(ptr.*)) - @as(i8, @intCast(val)));
        },

        elf.riscv.R_RISCV_SUB16 => {
            const ptr: *align(1) u16 = @ptrCast(where);
            ptr.* = @bitCast(@as(i16, @bitCast(ptr.*)) - @as(i16, @intCast(val)));
        },

        elf.riscv.R_RISCV_SUB6 => {
            const ptr: *u8 = @ptrCast(where);
            ptr.* = (ptr.* & 0xc0) | @as(u8, @bitCast((@as(i8, @bitCast(ptr.* & 0x3f)) - @as(i8, @intCast(val & 0x3f))) & 0x3f));
        },

        elf.riscv.R_RISCV_SET6 => {
            const ptr: *u8 = @ptrCast(where);
            ptr.* = (ptr.* & 0xc0) | @as(u8, @intCast(val & 0x3f));
        },

        elf.riscv.R_RISCV_SET8 => {
            const ptr: *u8 = @ptrCast(where);
            ptr.* = @intCast(val);
        },

        elf.riscv.R_RISCV_SET16 => {
            const ptr: *align(1) u16 = @ptrCast(where);
            ptr.* = @intCast(val);
        },

        elf.riscv.R_RISCV_SET32 => {
            where[0] = val;
        },

        else => {
            DPRINTF("RISCV-BOOT: Unknown reloc type {d} at {x} sym_val={x}\n", .{ r_type, @intFromPtr(where), sym_val });
            return -1;
        },
    }
    return 0;
}

pub fn relocate_rel(
    _: [*]elf.types.Rel,
    _: elf.types.Addr,
    _: [*]u8,
) c_int {
    return -1;
}

