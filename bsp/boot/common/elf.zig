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

// bsp/boot/common/elf.zig — ELF file format support for the bootloader.
//
// Replaces common/elf.c. Provides:
//   - load_elf(img: [*]u8, m: *mem.Module) callconv(.c) c_int — the public
//     C-ABI entry point called from common/load.c.
//
// The C version had three compile-time variants (CONFIG_ARMV8M, __riscv__,
// default). In Zig we use `comptime` branches on `builtin.cpu.arch` plus
// a CONFIG_ARMV8M gate. Since arm-qemu-virt is the active first-pass
// target, the default (non-ARMv8-M, non-RISC-V) path is the primary one.
//
// Namespace convention (see zig_boot_plan.md §4a): domain code uses
// `ffi.elf.types.*` and `mem.Module` instead of `c.Elf32_*` /
// `c.struct_module`.

const std = @import("std");
const builtin = @import("builtin");

const ffi = @import("ffi");
const panic_c = @import("panic_mod").panic;
const elf = ffi.elf;
const boot = ffi.boot;
const cfg = ffi.cfg;
const mem = ffi.mem;
const addr = ffi.addr;
const paddr_t = ffi.paddr_t;

// Machine relocation helpers — direct @import from machine_reloc module.
// No extern fn indirection needed; Zig-native ABI works across modules.
const machine_reloc = @import("machine_reloc");

const is_arm: bool = builtin.cpu.arch == .arm or builtin.cpu.arch == .thumb;
const is_riscv: bool = builtin.cpu.arch == .riscv32 or builtin.cpu.arch == .riscv64;
const is_armv8m: bool = mem.is_armv8m;

// Mirror of #define SHF_VALID.
const SHF_VALID = elf.types.SHF_ALLOC | elf.types.SHF_EXECINSTR | elf.types.SHF_WRITE | elf.types.SHF_LINK_ORDER;

// Packed structs for ELF relocation/symbol info bit-field access.
const RelInfo = packed struct(u32) {
    type: u8,
    sym: u24,
};

const SymInfo = packed struct(u8) {
    type: u4,
    bind: u4,
};

// ============================================================================
// Static state (matches the C file's static globals)
// ============================================================================

// Array of section addresses (32 entries). ARMv8-M needs this to be a
// *[]u8 rather than a []u8 so the relocation helpers can write to it.
const SECTIONS = 32;
var sect_addr: [SECTIONS][*]u8 = [_][*]u8{undefined} ** SECTIONS;
var strshndx: c_int = 0;

// ============================================================================
// ARMv8-M only: extern state shared with the relocation helpers.
// (Mirrors the C file lines 49-69).
// ============================================================================

// The C-side `load_base` / `load_start` (or `sram_load_base` / `sram_load_start`
// for ARMv8-M) are BSS-extern symbols defined in common/load.c. We declare
// them as Zig `extern` so domain code in this file can read/write them
// without going through c.*. The actual storage is owned by the C side.
pub extern var load_base: paddr_t;
pub extern var load_start: paddr_t;
pub extern var nr_img: c_int;

// For ARMv8-M, sram_load_base/sram_load_start are BSS-extern defined in
// <arch>/machdep.c. For other archs (the current arm-qemu-virt target),
// we just don't touch them — the getLoadBase() / setLoadBase() helpers
// return/assign load_base instead.
// The sram_* helpers are not used on non-ARMv8-M, so we don't declare
// them at file scope. They're referenced via inline `if (is_armv8m)`
// blocks further down where needed.

// ARMv8-M relocation globals (written by the carve-out in loadExecutable,
// read by the relocation helpers in <ARCH>/arch/elf_reloc.c).
// These must be visible as global symbols for the C relocation code.
pub export var sram_got_base: elf.types.Addr = 0;
pub export var text_vma: elf.types.Addr = 0;
pub export var data_vma: elf.types.Addr = 0;
pub export var text_runtime: elf.types.Addr = 0;
pub export var data_runtime: elf.types.Addr = 0;
pub export var elf_type: elf.types.Half = 0;
pub export var current_img: [*]u8 = undefined;
pub export var current_module: [*]mem.Module = undefined;
pub export var current_symtab: [*]elf.types.Sym = undefined;

// ARMv8-M relocation globals (already declared above as pub export var)
// Module-level globals: text_vma, data_vma, text_runtime, data_runtime, sram_got_base, elf_type, current_*

// (Removed the unused armv8m_globals wrapper struct since it shadows the
// module-level globals, causing computeSymVal to read stale zero values.)

inline fn getLoadBase() paddr_t {
    // The C side declares `extern paddr_t sram_load_base;` for ARMv8-M. For
    // other archs, only `load_base` is defined. The C preprocessor's
    // `#define load_base sram_load_base` from armv8m/elf.c means we want
    // to read sram_load_base when is_armv8m. Since this is a function and
    // we have an `if (is_armv8m)` comptime branch, the un-taken branch is
    // eliminated by the optimizer; the sram_load_base reference is never
    // emitted in the .o when is_armv8m is false.
    if (is_armv8m) {
        const p: *paddr_t = @extern(*paddr_t, .{ .name = "sram_load_base" });
        return p.*;
    }
    return load_base;
}

inline fn setLoadBase(v: paddr_t) void {
    if (is_armv8m) {
        const p: *paddr_t = @extern(*paddr_t, .{ .name = "sram_load_base" });
        p.* = v;
    } else {
        load_base = v;
    }
}

// ============================================================================
// Note: Zig resolves all function references within a single compilation
// unit, so forward declarations (as in C) are not needed. The file is
// structured to read top-down like the C version anyway.
// ============================================================================

// ============================================================================
// Debug helpers
//
// The C side uses DPRINTF/ELFDBG macros that expand to printf() if
// DEBUG/DEBUG_ELF is set, and to nothing otherwise.
// ============================================================================

inline fn ELFDBG(comptime format: []const u8, args: anytype) void {
    if (cfg.DEBUG_ELF) {
        ffi.print(format, args);
    }
}

inline fn DPRINTF(comptime format: []const u8, args: anytype) void {
    if (cfg.DEBUG) {
        ffi.print(format, args);
    }
}

// Compare a runtime name (NUL-terminated) against a comptime-known literal.
// `literal` length is bounded at comptime, so the function only reads at
// most `literal.len + 1` bytes from the runtime side — early exit and
// statically-known bounds make this much safer than a NUL-terminated
// strcmp-style loop with unbounded length.
inline fn nameEq(runtime: [*]const u8, comptime literal: []const u8) bool {
    var i: usize = 0;
    while (i < literal.len and runtime[i] == literal[i]) : (i += 1) {}
    // Match iff we consumed exactly `literal.len` bytes AND the next byte
    // is the terminating NUL.
    return i == literal.len and runtime[i] == 0;
}

pub fn load_elf(img_ptr: [*]u8, img_size: usize, m: *mem.Module) c_int {
    const img = img_ptr[0..img_size];
    if (img.len < @sizeOf(elf.types.Ehdr)) {
        ELFDBG("Invalid ELF size\n", .{});
        return -1;
    }
    const ehdr = @as(*const elf.types.Ehdr, @ptrCast(@alignCast(&img[0])));

    ELFDBG("\nelf_load\n", .{});

    // ----- ELF magic check -----
    if (ehdr.e_ident[elf.types.EI_MAG0] != elf.types.ELFMAG0 or
        ehdr.e_ident[elf.types.EI_MAG1] != elf.types.ELFMAG1 or
        ehdr.e_ident[elf.types.EI_MAG2] != elf.types.ELFMAG2 or
        ehdr.e_ident[elf.types.EI_MAG3] != elf.types.ELFMAG3)
    {
        ELFDBG("Invalid ELF image\n", .{});
        return -1;
    }

    if (is_armv8m) {
        current_img = img_ptr;
        current_module = @ptrCast(m);
    }

    // ----- Initialize load_base on the first image (kernel) -----
    if (nr_img == 0) {
        if (is_riscv) {
            // RISC-V: walk program headers to find first PT_LOAD's p_vaddr.
            const ph_offset = ehdr.e_phoff;
            const ph_count = ehdr.e_phnum;
            const ph_size = @sizeOf(elf.types.Phdr) * ph_count;
            if (ph_offset + ph_size > img.len) return -1;
            const phdr = @as([*]const elf.types.Phdr, @ptrCast(@alignCast(&img[ph_offset])));
            var found: bool = false;
            var i: c_int = 0;
            while (i < @as(c_int, @intCast(ph_count))) : (i += 1) {
                if (phdr[@intCast(i)].p_type == elf.types.PT_LOAD) {
                    const ph = &phdr[@intCast(i)];
                    setLoadBase(ph.p_vaddr); // kvtop(ph.p_vaddr) — KERNOFFSET=0 for RISC-V
                    found = true;
                    break;
                }
            }
            if (!found) {
                return -1;
            }
        } else {
            // Default (x86, ARM Cortex-A): compute load_base as the physical
            // address of the first segment (= kvtop of its virtual address).
            const ph_offset = ehdr.e_ehsize;
            const ph_size = @sizeOf(elf.types.Phdr);
            if (ph_offset + ph_size > img.len) return -1;
            const phdr = @as(*const elf.types.Phdr, @ptrCast(@alignCast(&img[ph_offset])));
            // kvtop = p_vaddr - KERNOFFSET
            const phys: elf.types.Addr = phdr.p_vaddr -% @as(elf.types.Addr, @intCast(cfg.KERNOFFSET));
            setLoadBase(phys);
        }
        if (getLoadBase() == 0) {
            DPRINTF("Invalid load address\n", .{});
            return -1;
        }
        load_start = getLoadBase();
        ELFDBG("kernel base={x}\n", .{getLoadBase()});
    } else if (nr_img == 1) {
        ELFDBG("driver base={x}\n", .{getLoadBase()});
    } else {
        ELFDBG("task base={x}\n", .{getLoadBase()});
    }

    // ----- Dispatch on ELF type -----
    const result: c_int = switch (ehdr.e_type) {
        elf.types.ET_EXEC => loadExecutable(img, m),
        elf.types.ET_REL => blk: {
            if (is_armv8m) {
                break :blk loadRelocatableArmv8m(img, m);
            } else if (is_riscv) {
                break :blk loadRelocatableRiscV(img, m);
            } else {
                break :blk loadRelocatableDefault(img, m);
            }
        },
        else => blk: {
            ELFDBG("Unsupported file type\n", .{});
            break :blk -1;
        },
    };

    if (result == 0) {
        nr_img += 1;
    }
    return result;
}

// ============================================================================
// loadExecutable — the kernel case (ET_EXEC).
// ============================================================================

fn loadExecutable(img: []const u8, m: *mem.Module) c_int {
    const ehdr = @as(*const elf.types.Ehdr, @ptrCast(@alignCast(&img[0])));
    const phys_base: paddr_t = getLoadBase();

    const ph_offset = if (is_riscv) ehdr.e_phoff else ehdr.e_ehsize;
    const ph_count = ehdr.e_phnum;
    const ph_size = @sizeOf(elf.types.Phdr) * ph_count;
    if (ph_offset + ph_size > img.len) return -1;
    var phdr = @as([*]const elf.types.Phdr, @ptrCast(@alignCast(&img[ph_offset])));
    m.phys = getLoadBase();
    DPRINTF("phys addr={x}\n", .{phys_base});

    // ARMv8-M only: pre-scan to find loc_text_vma / loc_data_vma
    var loc_text_vma: elf.types.Addr = 0;
    var loc_data_vma: elf.types.Addr = 0;
    if (is_armv8m) {
        var j: c_int = 0;
        while (j < @as(c_int, @intCast(ph_count))) : (j += 1) {
            const ph = &phdr[@intCast(j)];
            if (ph.p_type == elf.types.PT_LOAD) {
                if ((ph.p_flags & elf.types.PF_W) == 0) {
                    loc_text_vma = ph.p_vaddr;
                } else {
                    loc_data_vma = ph.p_vaddr;
                }
            }
        }
    }

    m.text = 0;
    m.data = 0;

    var i: c_int = 0;
    while (i < @as(c_int, @intCast(ph_count))) : (i += 1) {
        const ph = &phdr[@intCast(i)];
        if (ph.p_type == elf.types.PT_LOAD) {

            if (is_armv8m) {
                if ((ph.p_flags & elf.types.PF_W) == 0) {
                    // Text / RO data: XIP from flash, no copy.
                    if (m.text == 0) {
                        m.text = @intCast(@intFromPtr(&img[0]) + ph.p_offset);
                        m.textsz = @intCast(ph.p_memsz);
                    } else {
                        m.textsz = @intCast((ph.p_vaddr + ph.p_memsz) - m.text);
                    }
                } else {
                    // Data & BSS: relocated to SRAM.
                    if (m.data == 0) {
                        const data_vaddr: elf.types.Addr = if (nr_img == 0) ph.p_vaddr else getLoadBase();
                        m.data = data_vaddr;
                    }
                    m.datasz = @intCast((ph.p_vaddr + ph.p_filesz) - loc_data_vma);
                    m.bsssz = @intCast(((ph.p_vaddr + ph.p_memsz) - loc_data_vma) - m.datasz);
                    if (ph.p_filesz > 0) {
                        const dptr: [*]u8 = @ptrFromInt(m.data + (ph.p_vaddr - loc_data_vma));
                        if (ph.p_offset + ph.p_filesz > img.len) return -1;
                        const sptr: [*]const u8 = img[ph.p_offset..].ptr;
                        _ = boot.memcpy(@ptrCast(dptr), @ptrCast(sptr), ph.p_filesz);
                    }
                    if (ph.p_memsz > ph.p_filesz) {
                        const dptr: [*]u8 = @ptrFromInt(m.data + (ph.p_vaddr - loc_data_vma) + ph.p_filesz);
                        _ = boot.memset(@ptrCast(dptr), 0, ph.p_memsz - ph.p_filesz);
                    }
                    // Round up to next page.
                    setLoadBase(mem.round_page(m.data + (ph.p_vaddr - loc_data_vma) + ph.p_memsz));
                }
            } else {
                // Default (x86, ARM Cortex-A): copy segments to phys_base.
                if ((ph.p_flags & elf.types.PF_W) == 0) {
                    if (m.text == 0) {
                        m.text = ph.p_vaddr;
                        m.textsz = @intCast(ph.p_memsz);
                    } else {
                        m.textsz = @intCast((ph.p_vaddr + ph.p_memsz) - m.text);
                    }
                    if (ph.p_filesz > 0) {
                        const dptr: [*]u8 = @ptrFromInt(phys_base + (ph.p_vaddr - m.text));
                        if (ph.p_offset + ph.p_filesz > img.len) return -1;
                        const sptr: [*]const u8 = img[ph.p_offset..].ptr;
                        _ = boot.memcpy(@ptrCast(dptr), @ptrCast(sptr), ph.p_filesz);
                    }
                } else {
                    if (m.data == 0) {
                        m.data = ph.p_vaddr;
                        setLoadBase(phys_base + (m.data - m.text));
                    }
                    m.datasz = @intCast((ph.p_vaddr + ph.p_filesz) - m.data);
                    m.bsssz = @intCast(((ph.p_vaddr + ph.p_memsz) - m.data) - m.datasz);
                    if (ph.p_filesz > 0) {
                        const dptr: [*]u8 = @ptrFromInt(getLoadBase() + (ph.p_vaddr - m.data));
                        if (ph.p_offset + ph.p_filesz > img.len) return -1;
                        const sptr: [*]const u8 = img[ph.p_offset..].ptr;
                        _ = boot.memcpy(@ptrCast(dptr), @ptrCast(sptr), ph.p_filesz);
                    }
                    if (ph.p_memsz > ph.p_filesz) {
                        const dptr: [*]u8 = @ptrFromInt(getLoadBase() + (ph.p_vaddr - m.data) + ph.p_filesz);
                        _ = boot.memset(@ptrCast(dptr), 0, ph.p_memsz - ph.p_filesz);
                    }
                }
            }
        } else if (is_arm and !is_armv8m) {
            // ARM Cortex-A: capture PT_ARM_EXIDX for unwind tables.
            if (ph.p_type == elf.types.PT_ARM_EXIDX) {
                m.exidx_start = ph.p_vaddr;
                m.exidx_size = ph.p_memsz;
            }
        }
    }

    // Update load_base (non-ARMv8-M path).
    if (!is_armv8m) {
        if (m.data != 0) {
            setLoadBase(phys_base + (m.data - m.text) + m.datasz + m.bsssz);
        } else {
            setLoadBase(phys_base + m.textsz);
        }
    }
    setLoadBase(mem.round_page(getLoadBase()));
    m.size = @intCast(getLoadBase() - m.phys);
    m.entry = if (is_armv8m) m.text + (ehdr.e_entry - loc_text_vma) else ehdr.e_entry;
    ELFDBG("module size={x} entry={x}\n", .{ m.size, m.entry });

    if (m.size == 0) {
        panic_c("Module size is 0!");
    }

    // ARMv8-M: walk section headers to populate sect_addr[] and find .got.
    if (is_armv8m) {
        const sh_offset = ehdr.e_shoff;
        const sh_count = ehdr.e_shnum;
        const sh_size = @sizeOf(elf.types.Shdr) * sh_count;
        if (sh_offset + sh_size > img.len) return -1;
        const shdr = @as([*]const elf.types.Shdr, @ptrCast(@alignCast(&img[sh_offset])));

        const strtab_sh = &shdr[ehdr.e_shstrndx];
        if (strtab_sh.sh_offset + strtab_sh.sh_size > img.len) return -1;
        const shstrtab = @as([*]const u8, @ptrCast(@alignCast(&img[strtab_sh.sh_offset])));

        strshndx = 0;
        var k: c_int = 0;
        while (k < @as(c_int, @intCast(sh_count))) : (k += 1) {
            sect_addr[@intCast(k)] = undefined;
            if ((shdr[@intCast(k)].sh_flags & elf.types.SHF_ALLOC) != 0) {
                if ((shdr[@intCast(k)].sh_flags & elf.types.SHF_WRITE) == 0) {
                    if (shdr[@intCast(k)].sh_offset + shdr[@intCast(k)].sh_size > img.len) return -1;
                    sect_addr[@intCast(k)] = @constCast(img[shdr[@intCast(k)].sh_offset..].ptr);
                } else {
                    sect_addr[@intCast(k)] = @ptrFromInt(m.data + (shdr[@intCast(k)].sh_addr - loc_data_vma));
                }
            } else if (shdr[@intCast(k)].sh_type == elf.types.SHT_SYMTAB or
                       shdr[@intCast(k)].sh_type == elf.types.SHT_STRTAB)
            {
                if (shdr[@intCast(k)].sh_offset + shdr[@intCast(k)].sh_size > img.len) return -1;
                sect_addr[@intCast(k)] = @constCast(img[shdr[@intCast(k)].sh_offset..].ptr);
                if (shdr[@intCast(k)].sh_type == elf.types.SHT_SYMTAB) {
                    strshndx = @intCast(shdr[@intCast(k)].sh_link);
                }
            }
        }
        // Populate relocation globals.
        elf_type = ehdr.e_type;
        text_vma = loc_text_vma;
        data_vma = loc_data_vma;
        text_runtime = @intCast(m.text);
        data_runtime = @intCast(m.data);
        sram_got_base = 0;
        var g: c_int = 0;
        while (g < @as(c_int, @intCast(sh_count))) : (g += 1) {
            if (shdr[@intCast(g)].sh_type == elf.types.SHT_PROGBITS and
                nameEq(shstrtab + shdr[@intCast(g)].sh_name, ".got"))
            {
                sram_got_base = @intCast(@intFromPtr(sect_addr[@intCast(g)]));
                break;
            }
        }
        m.got_base = sram_got_base;

        // Apply relocations.
        var r: c_int = 0;
        while (r < @as(c_int, @intCast(sh_count))) : (r += 1) {
            if (shdr[@intCast(r)].sh_type == elf.types.SHT_REL or
                shdr[@intCast(r)].sh_type == elf.types.SHT_RELA)
            {
                if (relocateSection(img, @ptrCast(@constCast(&shdr[@intCast(r)]))) != 0) {
                    DPRINTF("Relocation error: module={s}\n", .{@as([*c]const u8, @ptrCast(&m.name))});
                    return -1;
                }
            }
        }
    }
    return 0;
}

// ============================================================================
// loadRelocatableRiscV — RISC-V variant of loadRelocatable
// ============================================================================

fn loadRelocatableRiscV(img: []const u8, m: *mem.Module) c_int {
    const ehdr = @as(*const elf.types.Ehdr, @ptrCast(@alignCast(&img[0])));
    m.phys = getLoadBase();
    strshndx = 0;

    const sh_offset = ehdr.e_shoff;
    const sh_count = ehdr.e_shnum;
    const sh_size = @sizeOf(elf.types.Shdr) * sh_count;
    if (sh_offset + sh_size > img.len) return -1;
    const shdr = @as([*]const elf.types.Shdr, @ptrCast(@alignCast(&img[sh_offset])));

    // Zero sect_addr for this module (matches C code initialization).
    var zi: c_int = 0;
    while (zi < @as(c_int, @intCast(sh_count))) : (zi += 1) {
        sect_addr[@intCast(zi)] = undefined;
    }

    var first_text_vma: elf.types.Addr = 0xffffffff;
    var first_text_off: elf.types.Addr = 0;
    var bss_base: paddr_t = 0;
    var i: c_int = 0;
    while (i < @as(c_int, @intCast(sh_count))) : (i += 1) {
        sect_addr[@intCast(i)] = undefined;
        const sh = &shdr[@intCast(i)];
        if ((sh.sh_flags & elf.types.SHF_ALLOC) != 0) {
            // Align load_base.
            const aligned = (getLoadBase() + (sh.sh_addralign - 1)) & ~(sh.sh_addralign - 1);
            setLoadBase(aligned);
            const sect_base = getLoadBase();

            if (sh.sh_type == elf.types.SHT_PROGBITS) {
                if ((sh.sh_flags & elf.types.SHF_EXECINSTR) != 0) {
                    if (first_text_vma == 0xffffffff) {
                        first_text_vma = sh.sh_addr;
                        first_text_off = sect_base - m.phys;
                    }
                } else if ((sh.sh_flags & elf.types.SHF_WRITE) == 0) {
                    // Rodata
                    if (first_text_vma == 0xffffffff) {
                        first_text_vma = sh.sh_addr;
                        first_text_off = sect_base - m.phys;
                    }
                } else {
                    if (m.data == 0) {
                        m.data = sect_base; // ptokv(sect_base) — KERNOFFSET=0
                    }
                }
                if (sh.sh_offset + sh.sh_size > img.len) return -1;
                _ = boot.memcpy(
                    @ptrCast(@as([*]u8, @ptrFromInt(sect_base))),
                    @ptrCast(&img[sh.sh_offset]),
                    sh.sh_size,
                );
            } else if (sh.sh_type == elf.types.SHT_NOBITS) {
                bss_base = sect_base;
                m.bsssz = sh.sh_size;
                _ = boot.memset(@ptrCast(@as([*]u8, @ptrFromInt(sect_base))), 0, sh.sh_size);
            }
            sect_addr[@intCast(i)] = @ptrFromInt(sect_base);
            setLoadBase(getLoadBase() + sh.sh_size);
        } else if (sh.sh_type == elf.types.SHT_SYMTAB or sh.sh_type == elf.types.SHT_STRTAB or
                   sh.sh_type == elf.types.SHT_REL or sh.sh_type == elf.types.SHT_RELA)
        {
            if (sh.sh_offset + sh.sh_size > img.len) return -1;
            sect_addr[@intCast(i)] = @constCast(img[sh.sh_offset..].ptr);
            if (sh.sh_type == elf.types.SHT_SYMTAB) {
                strshndx = @intCast(sh.sh_link);
            }
        }
    }
    m.text = addr.ptokv(m.phys + first_text_off); // ptokv(m->phys + first_text_off)
    m.textsz = m.data - m.text;
    m.datasz = @as(usize, @intCast(addr.ptokv(bss_base))) - m.data;

    setLoadBase(mem.round_page(getLoadBase()));
    m.size = @intCast(getLoadBase() - m.phys);
    m.entry = m.text + (ehdr.e_entry - first_text_vma);

    // Apply relocations.
    var r: c_int = 0;
    while (r < @as(c_int, @intCast(sh_count))) : (r += 1) {
        if (shdr[@intCast(r)].sh_type == elf.types.SHT_REL or
            shdr[@intCast(r)].sh_type == elf.types.SHT_RELA)
        {
            if (relocateSection(img, &shdr[@intCast(r)]) != 0) {
                return -1;
            }
        }
    }
    // RISC-V: instruction cache flush.
    asm volatile ("fence.i");
    return 0;
}

// ============================================================================
// loadRelocatableArmv8m — ARMv8-M variant of loadRelocatable
// ============================================================================

fn loadRelocatableArmv8m(img: []const u8, m: *mem.Module) c_int {
    const ehdr = @as(*const elf.types.Ehdr, @ptrCast(@alignCast(&img[0])));
    strshndx = 0;
    m.phys = getLoadBase();

    const sh_offset = ehdr.e_shoff;
    const sh_count = ehdr.e_shnum;
    const sh_size = @sizeOf(elf.types.Shdr) * sh_count;
    if (sh_offset + sh_size > img.len) return -1;
    const shdr = @as([*]const elf.types.Shdr, @ptrCast(@alignCast(&img[sh_offset])));

    const strtab_sh = &shdr[ehdr.e_shstrndx];
    if (strtab_sh.sh_offset + strtab_sh.sh_size > img.len) return -1;
    const shstrtab = @as([*]const u8, @ptrCast(@alignCast(&img[strtab_sh.sh_offset])));

    var bss_base: paddr_t = 0;
    var first_text_vma: elf.types.Addr = 0xffffffff;
    var first_text_off: elf.types.Addr = 0;

    // Save the initial load_base (like C version does)
    const init_load_base: paddr_t = getLoadBase();

    var i: c_int = 0;
    while (i < @as(c_int, @intCast(sh_count))) : (i += 1) {
        const sh = &shdr[@intCast(i)];
        sect_addr[@intCast(i)] = undefined;
        if ((sh.sh_flags & elf.types.SHF_ALLOC) != 0) {
            // Section alignment (match C: align load_base locally, don't persist)
            const align_val: elf.types.Addr = sh.sh_addralign;
            const aligned: elf.types.Addr = if (align_val > 1)
                (init_load_base + align_val - 1) & ~(align_val - 1)
            else
                init_load_base;
            // ARMv8-M: section physical address = init_load_base + sh.sh_addr (matches C's load_base + sh.sh_addr)
            const sect_base: elf.types.Addr = init_load_base + sh.sh_addr;
            _ = aligned;

            if (sh.sh_type == elf.types.SHT_PROGBITS) {
                if ((sh.sh_flags & elf.types.SHF_EXECINSTR) != 0) {
                    if (first_text_vma == 0xffffffff) {
                        first_text_vma = sh.sh_addr;
                        first_text_off = 0;
                    }
                } else if ((sh.sh_flags & elf.types.SHF_WRITE) == 0) {
                    // Rodata
                    if (first_text_vma == 0xffffffff) {
                        first_text_vma = sh.sh_addr;
                        first_text_off = 0;
                    }
                } else {
                    if (m.data == 0) {
                        m.data = @intCast(addr.ptokv(sect_base));
                    }
                }
                if (sh.sh_offset + sh.sh_size > img.len) return -1;
                _ = boot.memcpy(
                    @ptrCast(@as([*]u8, @ptrFromInt(sect_base))),
                    @ptrCast(&img[sh.sh_offset]),
                    sh.sh_size,
                );
            } else if (sh.sh_type == elf.types.SHT_NOBITS) {
                bss_base = sect_base;
                m.bsssz = sh.sh_size;
                _ = boot.memset(
                    @ptrCast(@as([*]u8, @ptrFromInt(bss_base))),
                    0,
                    sh.sh_size,
                );
            }
            sect_addr[@intCast(i)] = @ptrFromInt(sect_base);
            // C version does NOT advance load_base between sections

        } else if (sh.sh_type == elf.types.SHT_SYMTAB or
                   sh.sh_type == elf.types.SHT_STRTAB or
                   sh.sh_type == elf.types.SHT_REL or
                   sh.sh_type == elf.types.SHT_RELA)
        {
            if (sh.sh_offset + sh.sh_size > img.len) return -1;
            sect_addr[@intCast(i)] = @constCast(img[sh.sh_offset..].ptr);
            if (sh.sh_type == elf.types.SHT_SYMTAB) {
                strshndx = @intCast(sh.sh_link);
            }
        }
    }
    m.text = @intCast(addr.ptokv(m.phys + first_text_off));
    m.textsz = m.data - m.text;
    m.datasz = @as(usize, @intCast(addr.ptokv(bss_base))) - @as(usize, @intCast(m.data));

    // C version: load_base = round_page(bss_base + bsssz)
    setLoadBase(mem.round_page(bss_base + m.bsssz));
    m.size = @intCast(getLoadBase() - m.phys);
    m.entry = @intCast(addr.ptokv(ehdr.e_entry + m.phys));

    // ARMv8-M: populate relocation globals for helper
    elf_type = ehdr.e_type;
    text_vma = 0;
    data_vma = 0;
    text_runtime = @intCast(m.text);
    data_runtime = @intCast(m.data);
    sram_got_base = 0;
    {
        var g: c_int = 0;
        while (g < @as(c_int, @intCast(sh_count))) : (g += 1) {
            if (shdr[@intCast(g)].sh_type == elf.types.SHT_PROGBITS and
                nameEq(shstrtab + shdr[@intCast(g)].sh_name, ".got"))
            {
                sram_got_base = @intCast(@intFromPtr(sect_addr[@intCast(g)]));
                break;
            }
        }
    }
    m.got_base = sram_got_base;


    // Process relocation
    {
        var r: c_int = 0;
        while (r < @as(c_int, @intCast(sh_count))) : (r += 1) {
            if (shdr[@intCast(r)].sh_type == elf.types.SHT_REL or
                shdr[@intCast(r)].sh_type == elf.types.SHT_RELA)
            {
            if (relocateSection(img, &shdr[@intCast(r)]) != 0) {
                DPRINTF("Relocation error: module={s}\n", .{@as([*c]const u8, @ptrCast(&m.*.name))});
                return -1;
            }
            }
        }
    }
    // ARMv8-M doesn't need fence.i (RISC-V only)
    return 0;
}

// ============================================================================
// loadRelocatableDefault — x86 / ARM Cortex-A variant of loadRelocatable
// ============================================================================

fn loadRelocatableDefault(img: []const u8, m: *mem.Module) c_int {
    const ehdr = @as(*const elf.types.Ehdr, @ptrCast(@alignCast(&img[0])));
    strshndx = 0;
    m.phys = getLoadBase();
    DPRINTF("phys addr={x}\n", .{getLoadBase()});

    const sh_offset = ehdr.e_shoff;
    const sh_count = ehdr.e_shnum;
    const sh_size = @sizeOf(elf.types.Shdr) * sh_count;
    if (sh_offset + sh_size > img.len) return -1;
    const shdr = @as([*]const elf.types.Shdr, @ptrCast(@alignCast(&img[sh_offset])));

    const strtab_sh = &shdr[ehdr.e_shstrndx];
    if (strtab_sh.sh_offset + strtab_sh.sh_size > img.len) return -1;
    const shstrtab = @as([*]const u8, @ptrCast(@alignCast(&img[strtab_sh.sh_offset])));

    var bss_base: paddr_t = 0;
    var first_text_vma: elf.types.Addr = 0xffffffff;

    var i: c_int = 0;
    while (i < @as(c_int, @intCast(sh_count))) : (i += 1) {
        sect_addr[@intCast(i)] = undefined;
        const sh = &shdr[@intCast(i)];

        const is_progbits = sh.sh_type == elf.types.SHT_PROGBITS or
            (is_arm and sh.sh_type == elf.types.SHT_ARM_EXIDX);

        if (is_progbits) {

            const section_class: u8 = switch (sh.sh_flags & SHF_VALID) {
                elf.types.SHF_ALLOC | elf.types.SHF_EXECINSTR => 1, // Text
                elf.types.SHF_ALLOC | elf.types.SHF_WRITE => 2,    // Data
                elf.types.SHF_ALLOC => 3,                     // rodata
                elf.types.SHF_ALLOC | elf.types.SHF_LINK_ORDER => 4, // exidx
                else => 0,
            };

            // ARM exidx handling: capture in all four cases that may match.
            if (is_arm and sh.sh_type == elf.types.SHT_ARM_EXIDX) {
                m.exidx_start = addr.ptokv(getLoadBase() + sh.sh_addr);
                m.exidx_size = sh.sh_size;
            }

            if (section_class == 0) {
                // Not one of the standard load classes. Continue unless it
                // was an ARM exidx (which we already captured).
                if (!(is_arm and sh.sh_type == elf.types.SHT_ARM_EXIDX)) {
                    continue;
                }
            }

            if (section_class == 1) {
                if (first_text_vma == 0xffffffff) {
                    first_text_vma = sh.sh_addr;
                }
                m.text = addr.ptokv(getLoadBase());
            } else if (section_class == 2 and m.data == 0) {
                m.data = addr.ptokv(getLoadBase() + sh.sh_addr);
            } else if (section_class == 3) {
                // Rodata is treated as text for first_text_vma tracking.
                if (first_text_vma == 0xffffffff) {
                    first_text_vma = sh.sh_addr;
                }
            }

            const sect_base = getLoadBase() + sh.sh_addr;
            if (sh.sh_offset + sh.sh_size > img.len) return -1;
            _ = boot.memcpy(
                @ptrCast(@as([*]u8, @ptrFromInt(sect_base))),
                @ptrCast(&img[sh.sh_offset]),
                sh.sh_size,
            );
            sect_addr[@intCast(i)] = @ptrFromInt(sect_base);
        } else if (sh.sh_type == elf.types.SHT_NOBITS) {
            m.bsssz = sh.sh_size;
            const sect_base = getLoadBase() + sh.sh_addr;
            bss_base = sect_base;
            _ = boot.memset(@ptrCast(@as([*]u8, @ptrFromInt(bss_base))), 0, sh.sh_size);
            sect_addr[@intCast(i)] = @ptrFromInt(sect_base);
        } else if (sh.sh_type == elf.types.SHT_SYMTAB) {
            if (sh.sh_offset + sh.sh_size > img.len) return -1;
            sect_addr[@intCast(i)] = @constCast(img[sh.sh_offset..].ptr);
            if (strshndx != 0) {
                panic_c("Multiple symtab found!");
            }
            strshndx = @intCast(sh.sh_link);
        } else if (sh.sh_type == elf.types.SHT_STRTAB) {
            if (sh.sh_offset + sh.sh_size > img.len) return -1;
            sect_addr[@intCast(i)] = @constCast(img[sh.sh_offset..].ptr);
        }
    }
    m.textsz = m.data - m.text;
    m.datasz = @as(usize, @intCast(addr.ptokv(bss_base))) - m.data;

    setLoadBase(bss_base + m.bsssz);
    setLoadBase(mem.round_page(getLoadBase()));
    m.size = @intCast(getLoadBase() - addr.kvtop(m.text)); // load_base - kvtop(m->text)
    m.entry = m.text + (ehdr.e_entry - first_text_vma); // virtual entry point

    // ARMv8-M: populate relocation globals + process relocs.
    if (is_armv8m) {
        elf_type = ehdr.e_type;
        text_vma = 0;
        data_vma = 0;
        text_runtime = @intCast(m.text);
        data_runtime = @intCast(m.data);
        sram_got_base = 0;
        var g: c_int = 0;
        while (g < @as(c_int, @intCast(sh_count))) : (g += 1) {
            if (shdr[@intCast(g)].sh_type == elf.types.SHT_PROGBITS and
                nameEq(shstrtab + shdr[@intCast(g)].sh_name, ".got"))
            {
                sram_got_base = @intCast(@intFromPtr(sect_addr[@intCast(g)]));
                break;
            }
        }
        m.got_base = sram_got_base;
    }


    // Apply relocations.
    var r: c_int = 0;
    while (r < @as(c_int, @intCast(sh_count))) : (r += 1) {
        if (shdr[@intCast(r)].sh_type == elf.types.SHT_REL or
            shdr[@intCast(r)].sh_type == elf.types.SHT_RELA)
        {
            if (relocateSection(img, &shdr[@intCast(r)]) != 0) {
                return -1;
            }
        }
    }
    return 0;
}

// ============================================================================
// relocateSection — dispatches to REL or RELA handlers.
// ============================================================================

fn relocateSection(img: []const u8, shdr: *const elf.types.Shdr) c_int {
    ELFDBG("relocate_section\n", .{});
    if (shdr.sh_entsize == 0) {
        return 0;
    }

    const target_sect: [*]u8 = sect_addr[shdr.sh_info];
    if (@intFromPtr(target_sect) == 0) {
        return 0; // Skip unloaded target section.
    }

    const symtab: [*]elf.types.Sym = @ptrCast(@alignCast(@as([*]u8, @ptrCast(sect_addr[shdr.sh_link]))));
    if (@intFromPtr(symtab) == 0) {
        return -1;
    }

    if (is_armv8m) {
        current_symtab = symtab;
    }
    const strtab: [*]u8 = sect_addr[@as(usize, @intCast(strshndx))];
    if (@intFromPtr(strtab) == 0) return -1;
    ELFDBG("strtab={x}\n", .{@intFromPtr(strtab)});


    const nr_reloc: c_int = @intCast(@as(usize, @intCast(shdr.sh_size)) / @as(usize, @intCast(shdr.sh_entsize)));

    return switch (shdr.sh_type) {
        elf.types.SHT_REL => blk: {
            const offset = shdr.sh_offset;
            const size = shdr.sh_size;
            if (offset + size > img.len) return -1;
            break :blk relocateSectionRel(symtab, @ptrCast(@alignCast(@constCast(img[offset..].ptr))), target_sect, nr_reloc);
        },
        elf.types.SHT_RELA => blk: {
            const offset = shdr.sh_offset;
            const size = shdr.sh_size;
            if (offset + size > img.len) return -1;
            break :blk relocateSectionRela(symtab, @ptrCast(@alignCast(@constCast(img[offset..].ptr))), target_sect, nr_reloc);
        },
        else => -1,
    };
}

// ============================================================================
// relocateSectionRel / relocateSectionRela — walk the reloc entries, compute
// the symbol value, and call the per-arch relocate_rel / relocate_rela.
// ============================================================================

fn relocateSectionRel(
    sym_table: [*]elf.types.Sym,
    rel: [*]elf.types.Rel,
    target_sect: [*]u8,
    nr_reloc: c_int,
) c_int {
    var i: c_int = 0;
    while (i < nr_reloc) : (i += 1) {
        const r: elf.types.Rel = rel[@intCast(i)];
        const sym: [*]const elf.types.Sym = @ptrCast(&sym_table[@as(RelInfo, @bitCast(r.r_info)).sym]);
        if (sym[0].st_shndx != elf.types.STN_UNDEF) {
            const sym_val = computeSymVal(sym[0]);
            const rc = machine_reloc.relocate_rel(@ptrCast(@constCast(&r)), sym_val, target_sect);
            if (rc != 0) {
                return -1;
            }
        } else if (@as(RelInfo, @bitCast(r.r_info)).sym == elf.types.STN_UNDEF) {
            if (machine_reloc.relocate_rel(@ptrCast(@constCast(&r)), sym[0].st_value, target_sect) != 0) return -1;
        } else if (@as(SymInfo, @bitCast(sym[0].st_info)).bind != elf.types.STB_WEAK) {
            DPRINTF("Undefined symbol for rel[{d}] sym={x}\n", .{ i, @intFromPtr(sym) });
            return -1;
        } else {
            DPRINTF("Undefined weak symbol for rel[{d}]\n", .{i});
        }
    }
    return 0;
}

fn relocateSectionRela(
    sym_table: [*]elf.types.Sym,
    rela: [*]elf.types.Rela,
    target_sect: [*]u8,
    nr_reloc: c_int,
) c_int {
    var i: c_int = 0;
    while (i < nr_reloc) : (i += 1) {
        const r: elf.types.Rela = rela[@intCast(i)];
        const sym: [*]const elf.types.Sym = @ptrCast(&sym_table[@as(RelInfo, @bitCast(r.r_info)).sym]);
        if (sym[0].st_shndx != elf.types.STN_UNDEF) {
            const sym_val = computeSymVal(sym[0]);
            if (machine_reloc.relocate_rela(@ptrCast(@constCast(&r)), sym_val, target_sect) != 0) return -1;
        } else if (@as(RelInfo, @bitCast(r.r_info)).sym == elf.types.STN_UNDEF) {
            if (machine_reloc.relocate_rela(@ptrCast(@constCast(&r)), sym[0].st_value, target_sect) != 0) return -1;
        } else if (@as(SymInfo, @bitCast(sym[0].st_info)).bind != elf.types.STB_WEAK) {
            DPRINTF("Undefined symbol for rela[{d}] sym={x}\n", .{ i, @intFromPtr(sym) });
            return -1;
        } else {
            DPRINTF("Undefined weak symbol for rela[{d}]\n", .{i});
        }
    }
    return 0;
}

// Compute the symbol value based on arch-specific layout rules.
// Uses only the symbol's ELF metadata (st_value, st_shndx); the relocation
// offset and target-section pointer are not needed for value resolution —
// they belong to the relocation *application*, decided by the per-arch
// relocate_rel/rela helper.
inline fn computeSymVal(sym: elf.types.Sym) elf.types.Addr {
    var sym_val: elf.types.Addr = sym.st_value;
    if (is_armv8m) {
        if (elf_type == elf.types.ET_EXEC) {
            if (sym_val < data_vma) {
                sym_val = text_runtime + (sym_val - text_vma);
            } else {
                sym_val = data_runtime + (sym_val - data_vma);
            }
        } else {
            sym_val += @intCast(@intFromPtr(sect_addr[sym.st_shndx]));
        }
    } else if (is_riscv) {
        if (sym.st_shndx != elf.types.SHN_ABS) {
            sym_val += @intCast(@intFromPtr(sect_addr[sym.st_shndx]));
        }
    } else {
        sym_val += @intCast(@intFromPtr(sect_addr[sym.st_shndx]));
    }
    return sym_val;
}
// end of file
