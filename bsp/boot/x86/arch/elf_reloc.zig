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

// bsp/boot/x86/arch/elf_reloc.zig — x86 ELF relocation engine.
// Replaces bsp/boot/x86/arch/elf_reloc.c.

const ffi = @import("ffi");
const elf_t = ffi.elf.types;
const x86 = ffi.elf.x86;

pub export fn relocate_rel(
    rel: *elf_t.Rel,
    sym_val: elf_t.Addr,
    target_sect: [*]u8,
) callconv(.c) c_int {
    const where: [*]align(1) elf_t.Addr = @ptrCast(target_sect + rel.r_offset);
    const r_type: u32 = @intCast(rel.r_info & 0xff);

    switch (r_type) {
        x86.R_386_NONE => {},

        x86.R_386_32 => {
            where[0] +%= ptokv(sym_val);
        },

        x86.R_386_PC32, x86.R_386_PLT32 => {
            const where_addr = @intFromPtr(where);
            where[0] = where[0] +% sym_val -% @as(u32, @intCast(where_addr));
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
