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
// `ffi.elf.types.*` and `ffi.mem.Module` instead of `c.Elf32_*` /
// `c.struct_module`.

const std = @import("std");
const builtin = @import("builtin");

const ffi = @import("ffi");
const elf = ffi.elf;
const elf_t = ffi.elf.types;
const mem = ffi.mem;

const is_arm: bool = builtin.cpu.arch == .arm or builtin.cpu.arch == .thumb;
const is_riscv: bool = builtin.cpu.arch == .riscv32 or builtin.cpu.arch == .riscv64;
const is_armv8m: bool = ffi.mem.is_armv8m;

// Mirror of #define SHF_VALID.
const SHF_VALID = elf_t.SHF_ALLOC | elf_t.SHF_EXECINSTR | elf_t.SHF_WRITE | elf_t.SHF_LINK_ORDER;

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
pub extern var load_base: ffi.paddr_t;
pub extern var load_start: ffi.paddr_t;
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
pub export var sram_got_base: elf_t.Addr = 0;
pub export var text_vma: elf_t.Addr = 0;
pub export var data_vma: elf_t.Addr = 0;
pub export var text_runtime: elf_t.Addr = 0;
pub export var data_runtime: elf_t.Addr = 0;
pub export var elf_type: elf_t.Half = 0;
pub export var current_img: [*]u8 = undefined;
pub export var current_module: [*]mem.Module = undefined;
pub export var current_symtab: [*]elf_t.Sym = undefined;

// ARMv8-M relocation globals (already declared above as pub export var)
// Module-level globals: text_vma, data_vma, text_runtime, data_runtime, sram_got_base, elf_type, current_*

// (Removed the unused armv8m_globals wrapper struct since it shadows the
// module-level globals, causing computeSymVal to read stale zero values.)

inline fn getLoadBase() ffi.paddr_t {
    // The C side declares `extern paddr_t sram_load_base;` for ARMv8-M. For
    // other archs, only `load_base` is defined. The C preprocessor's
    // `#define load_base sram_load_base` from armv8m/elf.c means we want
    // to read sram_load_base when is_armv8m. Since this is a function and
    // we have an `if (is_armv8m)` comptime branch, the un-taken branch is
    // eliminated by the optimizer; the sram_load_base reference is never
    // emitted in the .o when is_armv8m is false.
    if (is_armv8m) {
        const p: *ffi.paddr_t = @extern(*ffi.paddr_t, .{ .name = "sram_load_base" });
        return p.*;
    }
    return load_base;
}

inline fn setLoadBase(v: ffi.paddr_t) void {
    if (is_armv8m) {
        const p: *ffi.paddr_t = @extern(*ffi.paddr_t, .{ .name = "sram_load_base" });
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
//
// ELFDBG(format, args) provides that semantic in Zig. Each call is
// precomputed at *compile time* via std.fmt when DEBUG_ELF is set:
// the formatted message becomes a literal in the binary's .rodata
// and the runtime cost is exactly one variadic-free cstring printf.
// When DEBUG_ELF is undefined, every ELFDBG call is fully eliminated
// at compile time — there is no runtime stub.
//
// Zig 0.16 cannot forward C-ABI varargs through a generic function
// wrapper (see the comment on `boot.printf` in ffi.zig). We sidestep
// that limitation by formatting into a comptime string and then
// handing it to printf with a fixed `"%s"` format string, which is
// itself a comptime literal with no varargs.
//
// We use Zig's std.fmt format specifiers (`{x}`, `{d}`, `{s}`) so the
// format string is parsed entirely at compile time. Common conversions
// from the C version's specifiers:
//   C `%x`    → Zig `{x}`
//   C `%lx`   → Zig `{x}`
//   C `%d`    → Zig `{d}`
//   C `%u`    → Zig `{d}`
//   C `%s`    → Zig `{s}`
//   C `%5x`   → Zig `{x:0>5}` (zero-pad width 5)
//
// Usage:
//     ELFDBG("\nelf_load\n");
//     ELFDBG("kernel base=%lx\n", .{value});
//     ELFDBG("page %d pa=%lx\n", .{i, page_pa});
// ============================================================================

/// `ELFDBG(format, args)` is the Zig analogue of C's ELFDBG(format).
///
/// `ELFDBG` is intentionally a no-op stub in this Zig port. The
/// reasoning: Zig 0.16 cannot forward C-ABI varargs through generic
/// helpers (see the `boot.printf` comment in ffi.zig), so wrapping
/// `printf` with varargs in Zig is impossible until variable args
/// are supported. Earlier attempts to use `std.fmt.comptimePrint`
/// and `std.fmt.bufPrintSentinel` failed due to Zig 0.16 + std.fmt
/// ICEs and code-size bloat on 8 KB boot ROMs (arm-raspi0 etc.).
///
/// Instead, debug formatting is done at every emit site with an
/// inline `if (ffi.cfg.DEBUG_ELF) ffi.boot.printf(...)` block. The
/// Zig compiler eliminates the entire block when DEBUG_ELF is
/// undefined, so the disabled path has zero runtime cost, matching
/// the C semantics of `ELFDBG`. Future Zig 0.16 fixes may let us
/// replace this stub with a comptime-folded implementation.
inline fn ELFDBG(comptime format: [*c]const u8, args: anytype) void {
    if (ffi.cfg.DEBUG_ELF) {
        @call(.auto, ffi.boot.printf, .{format} ++ args);
    }
}

inline fn DPRINTF(comptime format: [*c]const u8, args: anytype) void {
    if (ffi.cfg.DEBUG) {
        @call(.auto, ffi.boot.printf, .{format} ++ args);
    }
}

fn strCmp(s1: [*]const u8, s2: [*]const u8) c_int {
    var p1: [*]const u8 = s1;
    var p2: [*]const u8 = s2;
    while (p1[0] != 0 and p1[0] == p2[0]) {
        p1 += 1;
        p2 += 1;
    }
    return @intCast(p1[0] -% p2[0]);
}

comptime {
    if (is_armv8m) {
        _ = &strCmp;
    }
}

pub export fn load_elf(img_ptr: [*]u8, img_size: usize, m: *mem.Module) callconv(.c) c_int {
    const img = img_ptr[0..img_size];
    if (img.len < @sizeOf(elf_t.Ehdr)) {
        ELFDBG("Invalid ELF size\n", .{});
        return -1;
    }
    const ehdr = @as(*const elf_t.Ehdr, @ptrCast(@alignCast(&img[0])));

    ELFDBG("\nelf_load\n", .{});

    // ----- ELF magic check -----
    if (ehdr.e_ident[elf_t.EI_MAG0] != elf_t.ELFMAG0 or
        ehdr.e_ident[elf_t.EI_MAG1] != elf_t.ELFMAG1 or
        ehdr.e_ident[elf_t.EI_MAG2] != elf_t.ELFMAG2 or
        ehdr.e_ident[elf_t.EI_MAG3] != elf_t.ELFMAG3)
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
            const ph_size = @sizeOf(elf_t.Phdr) * ph_count;
            if (ph_offset + ph_size > img.len) return -1;
            const phdr = @as([*]const elf_t.Phdr, @ptrCast(@alignCast(&img[ph_offset])));
            var found: bool = false;
            var i: c_int = 0;
            while (i < @as(c_int, @intCast(ph_count))) : (i += 1) {
                if (phdr[@intCast(i)].p_type == elf_t.PT_LOAD) {
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
            const ph_size = @sizeOf(elf_t.Phdr);
            if (ph_offset + ph_size > img.len) return -1;
            const phdr = @as(*const elf_t.Phdr, @ptrCast(@alignCast(&img[ph_offset])));
            // kvtop = p_vaddr - KERNOFFSET
            const phys: elf_t.Addr = phdr.p_vaddr -% @as(elf_t.Addr, @intCast(ffi.cfg.KERNOFFSET));
            setLoadBase(phys);
        }
        if (getLoadBase() == 0) {
            DPRINTF("Invalid load address\n", .{});
            return -1;
        }
        load_start = getLoadBase();
        ELFDBG("kernel base=%lx\n", .{getLoadBase()});
    } else if (nr_img == 1) {
        ELFDBG("driver base=%lx\n", .{getLoadBase()});
    } else {
        ELFDBG("task base=%lx\n", .{getLoadBase()});
    }

    // ----- Dispatch on ELF type -----
    const result: c_int = switch (ehdr.e_type) {
        elf_t.ET_EXEC => loadExecutable(img, m),
        elf_t.ET_REL => blk: {
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
    const ehdr = @as(*const elf_t.Ehdr, @ptrCast(@alignCast(&img[0])));
    const phys_base: ffi.paddr_t = getLoadBase();

    const ph_offset = if (is_riscv) ehdr.e_phoff else ehdr.e_ehsize;
    const ph_count = ehdr.e_phnum;
    const ph_size = @sizeOf(elf_t.Phdr) * ph_count;
    if (ph_offset + ph_size > img.len) return -1;
    var phdr = @as([*]const elf_t.Phdr, @ptrCast(@alignCast(&img[ph_offset])));
    m.phys = getLoadBase();
    DPRINTF("phys addr=%lx\n", .{phys_base});

    // ARMv8-M only: pre-scan to find loc_text_vma / loc_data_vma
    var loc_text_vma: elf_t.Addr = 0;
    var loc_data_vma: elf_t.Addr = 0;
    if (is_armv8m) {
        var j: c_int = 0;
        while (j < @as(c_int, @intCast(ph_count))) : (j += 1) {
            const ph = &phdr[@intCast(j)];
            if (ph.p_type == elf_t.PT_LOAD) {
                if ((ph.p_flags & elf_t.PF_W) == 0) {
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
        if (ph.p_type == elf_t.PT_LOAD) {

            if (is_armv8m) {
                if ((ph.p_flags & elf_t.PF_W) == 0) {
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
                        const data_vaddr: elf_t.Addr = if (nr_img == 0) ph.p_vaddr else getLoadBase();
                        m.data = data_vaddr;
                    }
                    m.datasz = @intCast((ph.p_vaddr + ph.p_filesz) - loc_data_vma);
                    m.bsssz = @intCast(((ph.p_vaddr + ph.p_memsz) - loc_data_vma) - m.datasz);
                    if (ph.p_filesz > 0) {
                        const dptr: [*]u8 = @ptrFromInt(m.data + (ph.p_vaddr - loc_data_vma));
                        if (ph.p_offset + ph.p_filesz > img.len) return -1;
                        const sptr: [*]const u8 = img[ph.p_offset..].ptr;
                        _ = ffi.boot.memcpy(@ptrCast(dptr), @ptrCast(sptr), ph.p_filesz);
                    }
                    if (ph.p_memsz > ph.p_filesz) {
                        const dptr: [*]u8 = @ptrFromInt(m.data + (ph.p_vaddr - loc_data_vma) + ph.p_filesz);
                        _ = ffi.boot.memset(@ptrCast(dptr), 0, ph.p_memsz - ph.p_filesz);
                    }
                    // Round up to next page.
                    setLoadBase(ff.mem.round_page(m.data + (ph.p_vaddr - loc_data_vma) + ph.p_memsz));
                }
            } else {
                // Default (x86, ARM Cortex-A): copy segments to phys_base.
                if ((ph.p_flags & elf_t.PF_W) == 0) {
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
                        _ = ffi.boot.memcpy(@ptrCast(dptr), @ptrCast(sptr), ph.p_filesz);
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
                        _ = ffi.boot.memcpy(@ptrCast(dptr), @ptrCast(sptr), ph.p_filesz);
                    }
                    if (ph.p_memsz > ph.p_filesz) {
                        const dptr: [*]u8 = @ptrFromInt(getLoadBase() + (ph.p_vaddr - m.data) + ph.p_filesz);
                        _ = ffi.boot.memset(@ptrCast(dptr), 0, ph.p_memsz - ph.p_filesz);
                    }
                }
            }
        } else if (is_arm and !is_armv8m) {
            // ARM Cortex-A: capture PT_ARM_EXIDX for unwind tables.
            if (ph.p_type == elf_t.PT_ARM_EXIDX) {
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
    setLoadBase(ff.mem.round_page(getLoadBase()));
    m.size = @intCast(getLoadBase() - m.phys);
    m.entry = if (is_armv8m) m.text + (ehdr.e_entry - loc_text_vma) else ehdr.e_entry;
    ELFDBG("module size=%x entry=%lx\n", .{ m.size, m.entry });

    if (m.size == 0) {
        ffi.boot.panic("Module size is 0!");
    }

    // ARMv8-M: walk section headers to populate sect_addr[] and find .got.
    if (is_armv8m) {
        const sh_offset = ehdr.e_shoff;
        const sh_count = ehdr.e_shnum;
        const sh_size = @sizeOf(elf_t.Shdr) * sh_count;
        if (sh_offset + sh_size > img.len) return -1;
        const shdr = @as([*]const elf_t.Shdr, @ptrCast(@alignCast(&img[sh_offset])));

        const strtab_sh = &shdr[ehdr.e_shstrndx];
        if (strtab_sh.sh_offset + strtab_sh.sh_size > img.len) return -1;
        const shstrtab = @as([*]const u8, @ptrCast(@alignCast(&img[strtab_sh.sh_offset])));

        strshndx = 0;
        var k: c_int = 0;
        while (k < @as(c_int, @intCast(sh_count))) : (k += 1) {
            sect_addr[@intCast(k)] = undefined;
            if ((shdr[@intCast(k)].sh_flags & elf_t.SHF_ALLOC) != 0) {
                if ((shdr[@intCast(k)].sh_flags & elf_t.SHF_WRITE) == 0) {
                    if (shdr[@intCast(k)].sh_offset + shdr[@intCast(k)].sh_size > img.len) return -1;
                    sect_addr[@intCast(k)] = @constCast(img[shdr[@intCast(k)].sh_offset..].ptr);
                } else {
                    sect_addr[@intCast(k)] = @ptrFromInt(m.data + (shdr[@intCast(k)].sh_addr - loc_data_vma));
                }
            } else if (shdr[@intCast(k)].sh_type == elf_t.SHT_SYMTAB or
                       shdr[@intCast(k)].sh_type == elf_t.SHT_STRTAB)
            {
                if (shdr[@intCast(k)].sh_offset + shdr[@intCast(k)].sh_size > img.len) return -1;
                sect_addr[@intCast(k)] = @constCast(img[shdr[@intCast(k)].sh_offset..].ptr);
                if (shdr[@intCast(k)].sh_type == elf_t.SHT_SYMTAB) {
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
            if (shdr[@intCast(g)].sh_type == elf_t.SHT_PROGBITS and
                strCmp(shstrtab + shdr[@intCast(g)].sh_name, ".got") == 0)
            {
                sram_got_base = @intCast(@intFromPtr(sect_addr[@intCast(g)]));
                break;
            }
        }
        m.got_base = sram_got_base;

        // Apply relocations.
        var r: c_int = 0;
        while (r < @as(c_int, @intCast(sh_count))) : (r += 1) {
            if (shdr[@intCast(r)].sh_type == elf_t.SHT_REL or
                shdr[@intCast(r)].sh_type == elf_t.SHT_RELA)
            {
                if (relocateSection(img, @ptrCast(@constCast(&shdr[@intCast(r)]))) != 0) {
                    DPRINTF("Relocation error: module=%s\n", .{@as([*c]const u8, @ptrCast(&m.name))});
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
    const ehdr = @as(*const elf_t.Ehdr, @ptrCast(@alignCast(&img[0])));
    m.phys = getLoadBase();
    strshndx = 0;

    const sh_offset = ehdr.e_shoff;
    const sh_count = ehdr.e_shnum;
    const sh_size = @sizeOf(elf_t.Shdr) * sh_count;
    if (sh_offset + sh_size > img.len) return -1;
    const shdr = @as([*]const elf_t.Shdr, @ptrCast(@alignCast(&img[sh_offset])));

    // Zero sect_addr for this module (matches C code initialization).
    var zi: c_int = 0;
    while (zi < @as(c_int, @intCast(sh_count))) : (zi += 1) {
        sect_addr[@intCast(zi)] = undefined;
    }

    var first_text_vma: elf_t.Addr = 0xffffffff;
    var first_text_off: elf_t.Addr = 0;
    var bss_base: ffi.paddr_t = 0;
    var i: c_int = 0;
    while (i < @as(c_int, @intCast(sh_count))) : (i += 1) {
        sect_addr[@intCast(i)] = undefined;
        const sh = &shdr[@intCast(i)];
        if ((sh.sh_flags & elf_t.SHF_ALLOC) != 0) {
            // Align load_base.
            const aligned = (getLoadBase() + (sh.sh_addralign - 1)) & ~(sh.sh_addralign - 1);
            setLoadBase(aligned);
            const sect_base = getLoadBase();

            if (sh.sh_type == elf_t.SHT_PROGBITS) {
                if ((sh.sh_flags & elf_t.SHF_EXECINSTR) != 0) {
                    if (first_text_vma == 0xffffffff) {
                        first_text_vma = sh.sh_addr;
                        first_text_off = sect_base - m.phys;
                    }
                } else if ((sh.sh_flags & elf_t.SHF_WRITE) == 0) {
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
                _ = ffi.boot.memcpy(
                    @ptrCast(@as([*]u8, @ptrFromInt(sect_base))),
                    @ptrCast(&img[sh.sh_offset]),
                    sh.sh_size,
                );
            } else if (sh.sh_type == elf_t.SHT_NOBITS) {
                bss_base = sect_base;
                m.bsssz = sh.sh_size;
                _ = ffi.boot.memset(@ptrCast(@as([*]u8, @ptrFromInt(sect_base))), 0, sh.sh_size);
            }
            sect_addr[@intCast(i)] = @ptrFromInt(sect_base);
            setLoadBase(getLoadBase() + sh.sh_size);
        } else if (sh.sh_type == elf_t.SHT_SYMTAB or sh.sh_type == elf_t.SHT_STRTAB or
                   sh.sh_type == elf_t.SHT_REL or sh.sh_type == elf_t.SHT_RELA)
        {
            if (sh.sh_offset + sh.sh_size > img.len) return -1;
            sect_addr[@intCast(i)] = @constCast(img[sh.sh_offset..].ptr);
            if (sh.sh_type == elf_t.SHT_SYMTAB) {
                strshndx = @intCast(sh.sh_link);
            }
        }
    }
    m.text = ffi.addr.ptokv(m.phys + first_text_off); // ptokv(m->phys + first_text_off)
    m.textsz = m.data - m.text;
    m.datasz = @as(usize, @intCast(ffi.addr.ptokv(bss_base))) - m.data;

    setLoadBase(ff.mem.round_page(getLoadBase()));
    m.size = @intCast(getLoadBase() - m.phys);
    m.entry = m.text + (ehdr.e_entry - first_text_vma);

    // Apply relocations.
    var r: c_int = 0;
    while (r < @as(c_int, @intCast(sh_count))) : (r += 1) {
        if (shdr[@intCast(r)].sh_type == elf_t.SHT_REL or
            shdr[@intCast(r)].sh_type == elf_t.SHT_RELA)
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
    const ehdr = @as(*const elf_t.Ehdr, @ptrCast(@alignCast(&img[0])));
    strshndx = 0;
    m.phys = getLoadBase();

    const sh_offset = ehdr.e_shoff;
    const sh_count = ehdr.e_shnum;
    const sh_size = @sizeOf(elf_t.Shdr) * sh_count;
    if (sh_offset + sh_size > img.len) return -1;
    const shdr = @as([*]const elf_t.Shdr, @ptrCast(@alignCast(&img[sh_offset])));

    const strtab_sh = &shdr[ehdr.e_shstrndx];
    if (strtab_sh.sh_offset + strtab_sh.sh_size > img.len) return -1;
    const shstrtab = @as([*]const u8, @ptrCast(@alignCast(&img[strtab_sh.sh_offset])));

    var bss_base: ffi.paddr_t = 0;
    var first_text_vma: elf_t.Addr = 0xffffffff;
    var first_text_off: elf_t.Addr = 0;

    // Save the initial load_base (like C version does)
    const init_load_base: ffi.paddr_t = getLoadBase();

    var i: c_int = 0;
    while (i < @as(c_int, @intCast(sh_count))) : (i += 1) {
        const sh = &shdr[@intCast(i)];
        sect_addr[@intCast(i)] = undefined;
        if ((sh.sh_flags & elf_t.SHF_ALLOC) != 0) {
            // Section alignment (match C: align load_base locally, don't persist)
            const align_val: elf_t.Addr = sh.sh_addralign;
            const aligned: elf_t.Addr = if (align_val > 1)
                (init_load_base + align_val - 1) & ~(align_val - 1)
            else
                init_load_base;
            // ARMv8-M: section physical address = init_load_base + sh.sh_addr (matches C's load_base + sh.sh_addr)
            const sect_base: elf_t.Addr = init_load_base + sh.sh_addr;
            _ = aligned;

            if (sh.sh_type == elf_t.SHT_PROGBITS) {
                if ((sh.sh_flags & elf_t.SHF_EXECINSTR) != 0) {
                    if (first_text_vma == 0xffffffff) {
                        first_text_vma = sh.sh_addr;
                        first_text_off = 0;
                    }
                } else if ((sh.sh_flags & elf_t.SHF_WRITE) == 0) {
                    // Rodata
                    if (first_text_vma == 0xffffffff) {
                        first_text_vma = sh.sh_addr;
                        first_text_off = 0;
                    }
                } else {
                    if (m.data == 0) {
                        m.data = @intCast(ffi.addr.ptokv(sect_base));
                    }
                }
                if (sh.sh_offset + sh.sh_size > img.len) return -1;
                _ = ffi.boot.memcpy(
                    @ptrCast(@as([*]u8, @ptrFromInt(sect_base))),
                    @ptrCast(&img[sh.sh_offset]),
                    sh.sh_size,
                );
            } else if (sh.sh_type == elf_t.SHT_NOBITS) {
                bss_base = sect_base;
                m.bsssz = sh.sh_size;
                _ = ffi.boot.memset(
                    @ptrCast(@as([*]u8, @ptrFromInt(bss_base))),
                    0,
                    sh.sh_size,
                );
            }
            sect_addr[@intCast(i)] = @ptrFromInt(sect_base);
            // C version does NOT advance load_base between sections

        } else if (sh.sh_type == elf_t.SHT_SYMTAB or
                   sh.sh_type == elf_t.SHT_STRTAB or
                   sh.sh_type == elf_t.SHT_REL or
                   sh.sh_type == elf_t.SHT_RELA)
        {
            if (sh.sh_offset + sh.sh_size > img.len) return -1;
            sect_addr[@intCast(i)] = @constCast(img[sh.sh_offset..].ptr);
            if (sh.sh_type == elf_t.SHT_SYMTAB) {
                strshndx = @intCast(sh.sh_link);
            }
        }
    }
    m.text = @intCast(ffi.addr.ptokv(m.phys + first_text_off));
    m.textsz = m.data - m.text;
    m.datasz = @as(usize, @intCast(ffi.addr.ptokv(bss_base))) - @as(usize, @intCast(m.data));

    // C version: load_base = round_page(bss_base + bsssz)
    setLoadBase(ff.mem.round_page(bss_base + m.bsssz));
    m.size = @intCast(getLoadBase() - m.phys);
    m.entry = @intCast(ffi.addr.ptokv(ehdr.e_entry + m.phys));

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
            if (shdr[@intCast(g)].sh_type == elf_t.SHT_PROGBITS and
                strCmp(shstrtab + shdr[@intCast(g)].sh_name, ".got") == 0)
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
            if (shdr[@intCast(r)].sh_type == elf_t.SHT_REL or
                shdr[@intCast(r)].sh_type == elf_t.SHT_RELA)
            {
            if (relocateSection(img, &shdr[@intCast(r)]) != 0) {
                DPRINTF("Relocation error: module=%s\n", .{@as([*c]const u8, @ptrCast(&m.name))});
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
    const ehdr = @as(*const elf_t.Ehdr, @ptrCast(@alignCast(&img[0])));
    strshndx = 0;
    m.phys = getLoadBase();
    DPRINTF("phys addr=%lx\n", .{getLoadBase()});

    const sh_offset = ehdr.e_shoff;
    const sh_count = ehdr.e_shnum;
    const sh_size = @sizeOf(elf_t.Shdr) * sh_count;
    if (sh_offset + sh_size > img.len) return -1;
    const shdr = @as([*]const elf_t.Shdr, @ptrCast(@alignCast(&img[sh_offset])));

    const strtab_sh = &shdr[ehdr.e_shstrndx];
    if (strtab_sh.sh_offset + strtab_sh.sh_size > img.len) return -1;
    const shstrtab = @as([*]const u8, @ptrCast(@alignCast(&img[strtab_sh.sh_offset])));

    var bss_base: ffi.paddr_t = 0;
    var first_text_vma: elf_t.Addr = 0xffffffff;

    var i: c_int = 0;
    while (i < @as(c_int, @intCast(sh_count))) : (i += 1) {
        sect_addr[@intCast(i)] = undefined;
        const sh = &shdr[@intCast(i)];

        const is_progbits = sh.sh_type == elf_t.SHT_PROGBITS or
            (is_arm and sh.sh_type == elf_t.SHT_ARM_EXIDX);

        if (is_progbits) {

            const section_class: u8 = switch (sh.sh_flags & SHF_VALID) {
                elf_t.SHF_ALLOC | elf_t.SHF_EXECINSTR => 1, // Text
                elf_t.SHF_ALLOC | elf_t.SHF_WRITE => 2,    // Data
                elf_t.SHF_ALLOC => 3,                     // rodata
                elf_t.SHF_ALLOC | elf_t.SHF_LINK_ORDER => 4, // exidx
                else => 0,
            };

            // ARM exidx handling: capture in all four cases that may match.
            if (is_arm and sh.sh_type == elf_t.SHT_ARM_EXIDX) {
                m.exidx_start = ffi.addr.ptokv(getLoadBase() + sh.sh_addr);
                m.exidx_size = sh.sh_size;
            }

            if (section_class == 0) {
                // Not one of the standard load classes. Continue unless it
                // was an ARM exidx (which we already captured).
                if (!(is_arm and sh.sh_type == elf_t.SHT_ARM_EXIDX)) {
                    continue;
                }
            }

            if (section_class == 1) {
                if (first_text_vma == 0xffffffff) {
                    first_text_vma = sh.sh_addr;
                }
                m.text = ffi.addr.ptokv(getLoadBase());
            } else if (section_class == 2 and m.data == 0) {
                m.data = ffi.addr.ptokv(getLoadBase() + sh.sh_addr);
            } else if (section_class == 3) {
                // Rodata is treated as text for first_text_vma tracking.
                if (first_text_vma == 0xffffffff) {
                    first_text_vma = sh.sh_addr;
                }
            }

            const sect_base = getLoadBase() + sh.sh_addr;
            if (sh.sh_offset + sh.sh_size > img.len) return -1;
            _ = ffi.boot.memcpy(
                @ptrCast(@as([*]u8, @ptrFromInt(sect_base))),
                @ptrCast(&img[sh.sh_offset]),
                sh.sh_size,
            );
            sect_addr[@intCast(i)] = @ptrFromInt(sect_base);
        } else if (sh.sh_type == elf_t.SHT_NOBITS) {
            m.bsssz = sh.sh_size;
            const sect_base = getLoadBase() + sh.sh_addr;
            bss_base = sect_base;
            _ = ffi.boot.memset(@ptrCast(@as([*]u8, @ptrFromInt(bss_base))), 0, sh.sh_size);
            sect_addr[@intCast(i)] = @ptrFromInt(sect_base);
        } else if (sh.sh_type == elf_t.SHT_SYMTAB) {
            if (sh.sh_offset + sh.sh_size > img.len) return -1;
            sect_addr[@intCast(i)] = @constCast(img[sh.sh_offset..].ptr);
            if (strshndx != 0) {
                ffi.boot.panic("Multiple symtab found!");
            }
            strshndx = @intCast(sh.sh_link);
        } else if (sh.sh_type == elf_t.SHT_STRTAB) {
            if (sh.sh_offset + sh.sh_size > img.len) return -1;
            sect_addr[@intCast(i)] = @constCast(img[sh.sh_offset..].ptr);
        }
    }
    m.textsz = m.data - m.text;
    m.datasz = @as(usize, @intCast(ffi.addr.ptokv(bss_base))) - m.data;

    setLoadBase(bss_base + m.bsssz);
    setLoadBase(ff.mem.round_page(getLoadBase()));
    m.size = @intCast(getLoadBase() - ffi.addr.kvtop(m.text)); // load_base - kvtop(m->text)
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
            if (shdr[@intCast(g)].sh_type == elf_t.SHT_PROGBITS and
                strCmp(shstrtab + shdr[@intCast(g)].sh_name, ".got") == 0)
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
        if (shdr[@intCast(r)].sh_type == elf_t.SHT_REL or
            shdr[@intCast(r)].sh_type == elf_t.SHT_RELA)
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

fn relocateSection(img: []const u8, shdr: *const elf_t.Shdr) c_int {
    ELFDBG("relocate_section\n", .{});
    if (shdr.sh_entsize == 0) {
        return 0;
    }

    const target_sect: [*]u8 = sect_addr[shdr.sh_info];
    if (@intFromPtr(target_sect) == 0) {
        return 0; // Skip unloaded target section.
    }

    const symtab: [*]elf_t.Sym = @ptrCast(@alignCast(@as([*]u8, @ptrCast(sect_addr[shdr.sh_link]))));
    if (@intFromPtr(symtab) == 0) {
        return -1;
    }

    if (is_armv8m) {
        current_symtab = symtab;
    }
    const strtab: [*]u8 = sect_addr[@as(usize, @intCast(strshndx))];
    if (@intFromPtr(strtab) == 0) return -1;
    ELFDBG("strtab=%lx\n", .{@as(c_ulong, @intCast(@intFromPtr(strtab)))});


    const nr_reloc: c_int = @intCast(@as(usize, @intCast(shdr.sh_size)) / @as(usize, @intCast(shdr.sh_entsize)));

    return switch (shdr.sh_type) {
        elf_t.SHT_REL => blk: {
            const offset = shdr.sh_offset;
            const size = shdr.sh_size;
            if (offset + size > img.len) return -1;
            break :blk relocateSectionRel(symtab, @ptrCast(@alignCast(@constCast(img[offset..].ptr))), target_sect, nr_reloc);
        },
        elf_t.SHT_RELA => blk: {
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
    sym_table: [*]elf_t.Sym,
    rel: [*]elf_t.Rel,
    target_sect: [*]u8,
    nr_reloc: c_int,
) c_int {
    var i: c_int = 0;
    while (i < nr_reloc) : (i += 1) {
        const r: elf_t.Rel = rel[@intCast(i)];
        const sym: [*]const elf_t.Sym = @ptrCast(&sym_table[r.r_info >> 8]);
        if (sym[0].st_shndx != elf_t.STN_UNDEF) {
            const sym_val = computeSymVal(sym[0], r.r_offset, target_sect);
            const rc = relocate_rel_api(@ptrCast(@constCast(&r)), sym_val, target_sect);
            if (rc != 0) {
                return -1;
            }
        } else if ((r.r_info >> 8) == elf_t.STN_UNDEF) {
            if (relocate_rel_api(@ptrCast(@constCast(&r)), sym[0].st_value, target_sect) != 0) return -1;
        } else if ((sym[0].st_info >> 4) != elf_t.STB_WEAK) {
            DPRINTF("Undefined symbol for rel[%x] sym=%lx\n", .{ i, @as(c_ulong, @intCast(@intFromPtr(sym))) });
            return -1;
        } else {
            DPRINTF("Undefined weak symbol for rel[%x]\n", .{i});
        }
    }
    return 0;
}

fn relocateSectionRela(
    sym_table: [*]elf_t.Sym,
    rela: [*]elf_t.Rela,
    target_sect: [*]u8,
    nr_reloc: c_int,
) c_int {
    var i: c_int = 0;
    while (i < nr_reloc) : (i += 1) {
        const r: elf_t.Rela = rela[@intCast(i)];
        const sym: [*]const elf_t.Sym = @ptrCast(&sym_table[r.r_info >> 8]);
        if (sym[0].st_shndx != elf_t.STN_UNDEF) {
            const sym_val = computeSymVal(sym[0], r.r_offset, target_sect);
            if (relocate_rela_api(@ptrCast(@constCast(&r)), sym_val, target_sect) != 0) return -1;
        } else if ((r.r_info >> 8) == elf_t.STN_UNDEF) {
            if (relocate_rela_api(@ptrCast(@constCast(&r)), sym[0].st_value, target_sect) != 0) return -1;
        } else if ((sym[0].st_info >> 4) != elf_t.STB_WEAK) {
            DPRINTF("Undefined symbol for rela[%x] sym=%lx\n", .{ i, @as(c_ulong, @intCast(@intFromPtr(sym))) });
            return -1;
        } else {
            DPRINTF("Undefined weak symbol for rela[%x]\n", .{i});
        }
    }
    return 0;
}

// Relocation helper wrappers to dispatch to elf.api.relocate_*
inline fn relocate_rel_api(rel: *elf_t.Rel, sym_val: elf_t.Addr, target_sect: [*]u8) c_int {
    return elf.api.relocate_rel(rel, sym_val, target_sect);
}

inline fn relocate_rela_api(rela: *elf_t.Rela, sym_val: elf_t.Addr, target_sect: [*]u8) c_int {
    return elf.api.relocate_rela(rela, sym_val, target_sect);
}

// Compute the symbol value based on arch-specific layout rules.
inline fn computeSymVal(sym: elf_t.Sym, _: elf_t.Addr, target_sect: [*]u8) elf_t.Addr {
    var sym_val: elf_t.Addr = sym.st_value;
    if (is_armv8m) {
        if (elf_type == elf_t.ET_EXEC) {
            if (sym_val < data_vma) {
                sym_val = text_runtime + (sym_val - text_vma);
            } else {
                sym_val = data_runtime + (sym_val - data_vma);
            }
        } else {
            sym_val += @intCast(@intFromPtr(sect_addr[sym.st_shndx]));
        }
    } else if (is_riscv) {
        if (sym.st_shndx != elf_t.SHN_ABS) {
            sym_val += @intCast(@intFromPtr(sect_addr[sym.st_shndx]));
        }
    } else {
        sym_val += @intCast(@intFromPtr(sect_addr[sym.st_shndx]));
    }
    _ = target_sect;
    return sym_val;
}

// `ff` is a forward-compat alias (the mem module hosts round_page/trunc_page).
const ff = ffi;
