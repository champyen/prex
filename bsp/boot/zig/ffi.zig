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
//    documentation and/or other materials provided with the documentation
//    and/or other materials provided with the distribution.
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

// bsp/boot/zig/ffi.zig — typed/organized namespace for the bootloader.
//
// Mirrors usr/zig/prog.zig: each per-domain namespace embeds its own
// scoped @cImport rather than routing through a separate c.zig hub.
// Domain .zig files import only ffi.zig and write:
//
//     const ffi = @import("ffi");
//     ffi.boot.printf("...");
//     ffi.elf.types.Addr
//     ffi.ar.constants.ARMAG
//     ffi.mem.MT_USABLE
//     ffi.cfg.CONFIG_LOADER_TEXT
//
// Build-time -D flags (KERNEL, DEBUG, __arm__, __qemu_virt__, ...) propagate
// from mk/zig.mk into every @cImport below — do NOT @cDefine them here.

const builtin = @import("builtin");
const std = @import("std");

// ============================================================================
// strlen — return length of C-string. Zig's optimizer emits `bl strlen` for
// `[*c]const u8` value conversions during print()'s type-erasure path. We
// export this Zig-native implementation under the standard `strlen` symbol
// name with C ABI to match the optimizer's emitted `extern fn` reference.
// Unused after kernel boot.
// ============================================================================
fn strlen(str: [*c]const u8) callconv(.c) c_ulong {
    const s: [*c]const volatile u8 = @ptrCast(str);
    var i: c_ulong = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}

comptime {
    @export(&strlen, .{ .name = "strlen", .linkage = .strong });
}

// ============================================================================
// Per-machine startup/debug helpers (different Zig modules). Imported
// directly via @import so ffi.zig can call the platform-specific
// startup() / debug_init() / debug_putc() as plain Zig-native functions,
// not through the extern fn indirection.
//
// The implementations in <arch>/<plat>/{startup,debug}.zig are still
// `pub export fn` with C ABI for the C-fallback bootloader path
// (bsp/boot/arm/gba/startup.c et al); we get the Zig-native address by
// direct @import into these callsites.
// ============================================================================
const machine_startup = @import("machine_startup");
const machine_debug = @import("machine_debug");

// ============================================================================
// Zig-native string/memory helpers from common/string.zig. Exposed through
// the `boot` namespace so domain code can call `ffi.boot.memcpy(...)` without
// going through a C ABI boundary (these are pkg-internal Zig calls).
// ============================================================================
const string = @import("string_mod");

// ============================================================================
// Shared raw @cImport used by several namespaces for C primitive types
// (size_t, paddr_t, vaddr_t, ...). Scoped to a private name so domain code
// accesses via ffi.paddr_t / ffi.size_t etc.
// ============================================================================
const c_types = @cImport({
    @cInclude("stdint.h");
    @cInclude("stddef.h");
    @cInclude("sys/types.h");
    @cInclude("sys/param.h");
});

pub const size_t = c_types.size_t;
pub const ssize_t = c_types.ssize_t;
pub const intptr_t = c_types.intptr_t;
pub const uintptr_t = c_types.uintptr_t;
pub const paddr_t = c_types.paddr_t;
pub const vaddr_t = c_types.vaddr_t;
pub const psize_t = c_types.psize_t;
pub const vsize_t = c_types.vsize_t;

// ============================================================================
// boot.* — C-ABI entry points, BSS-extern state, libc-equivalent helpers.
// Scoped @cImport for <boot.h>, <load.h>, <machdep.h>. The libc-equivalents
// (memcpy/memset/strncmp/strlcpy/atol) are declared as `extern fn` rather
// than pulled from @cImport so we get the right callconv + types without
// dragging in competing C prototypes.
// ============================================================================
const c_boot = @cImport({
    @cInclude("boot.h");
    @cInclude("load.h");
    @cInclude("machdep.h");
});

pub const boot = struct {
    // sole assembly entry — must remain C ABI
    pub extern fn main() callconv(.c) c_int;

    // extern vars shared with arch relocation helpers (load.c symtab state).
    pub extern var load_base: paddr_t;
    pub extern var load_start: paddr_t;
    pub extern var nr_img: c_int;

    // Bootinfo pointer — the actual storage lives in common/bootinfo.zig
    // (module root). The pub var in bootinfo.zig has type [*c]mem.BootInfo;
    // we expose a non-c pointer here so per-machine startup.zig (which
    // needs to do field access like `bi.video.text_x`) gets auto-deref.
    pub extern var bootinfo: *mem.BootInfo;

    // Zig-native string/memory helpers from common/string.zig. These are
    // pkg-internal Zig calls (no `@import("...string")` needed in callers).
    pub const memcpy = string.memcpy;
    pub const memset = string.memset;
    pub const strncmp = string.strncmp;
    pub const strlcpy = string.strlcpy;
    pub const atol = string.atol;

    // implemented in common/jump_entry.c — Zig 0.16 function-pointer bug
    // forces a C helper for the indirect call to the kernel entry.
    pub extern fn _jump_to_kernel(entry: usize) callconv(.c) void;
    pub const jump_to_kernel = _jump_to_kernel;
};

// ============================================================================
// elf.* — ELF loader namespace.
//   elf.types  : shared ELF struct aliases + format constants (from sys/elf.h)
//   elf.x86    : x86 relocation type enum (R_386_*)
//   elf.arm    : ARM relocation type enum (R_ARM_*)
//   elf.riscv  : RISC-V relocation type enum (R_RISCV_*)
//   elf.api    : extern fn load_elf, relocate_rel, relocate_rela
// ============================================================================
const c_elf = @cImport({
    @cInclude("sys/elf.h");
    @cInclude("elf_reloc.h");
});

pub const elf = struct {
    pub const types = struct {
        pub const Ehdr = c_elf.Elf32_Ehdr;
        pub const Phdr = c_elf.Elf32_Phdr;
        pub const Shdr = c_elf.Elf32_Shdr;
        pub const Sym = c_elf.Elf32_Sym;
        pub const Rel = c_elf.Elf32_Rel;
        pub const Rela = c_elf.Elf32_Rela;
        pub const Addr = c_elf.Elf32_Addr;
        pub const Off = c_elf.Elf32_Off;
        pub const Word = c_elf.Elf32_Word;
        pub const Half = c_elf.Elf32_Half;
        pub const Sword = c_elf.Elf32_Sword;

        pub const EI_MAG0: u8 = c_elf.EI_MAG0;
        pub const EI_MAG1: u8 = c_elf.EI_MAG1;
        pub const EI_MAG2: u8 = c_elf.EI_MAG2;
        pub const EI_MAG3: u8 = c_elf.EI_MAG3;
        pub const ELFMAG0: u8 = c_elf.ELFMAG0;
        pub const ELFMAG1: u8 = c_elf.ELFMAG1;
        pub const ELFMAG2: u8 = c_elf.ELFMAG2;
        pub const ELFMAG3: u8 = c_elf.ELFMAG3;
        pub const ELFMAG = c_elf.ELFMAG;
        pub const SELFMAG = c_elf.SELFMAG;

        pub const ET_NONE: u16 = c_elf.ET_NONE;
        pub const ET_REL: u16 = c_elf.ET_REL;
        pub const ET_EXEC: u16 = c_elf.ET_EXEC;
        pub const ET_DYN: u16 = c_elf.ET_DYN;
        pub const ET_CORE: u16 = c_elf.ET_CORE;

        pub const PT_NULL: u32 = c_elf.PT_NULL;
        pub const PT_LOAD: u32 = c_elf.PT_LOAD;
        pub const PT_DYNAMIC: u32 = c_elf.PT_DYNAMIC;
        pub const PT_NOTE: u32 = c_elf.PT_NOTE;
        pub const PT_ARM_EXIDX: u32 = if (@hasDecl(c_elf, "PT_ARM_EXIDX")) c_elf.PT_ARM_EXIDX else 0x70000000;

        pub const SHT_NULL: u32 = c_elf.SHT_NULL;
        pub const SHT_PROGBITS: u32 = c_elf.SHT_PROGBITS;
        pub const SHT_SYMTAB: u32 = c_elf.SHT_SYMTAB;
        pub const SHT_STRTAB: u32 = c_elf.SHT_STRTAB;
        pub const SHT_RELA: u32 = c_elf.SHT_RELA;
        pub const SHT_REL: u32 = c_elf.SHT_REL;
        pub const SHT_NOBITS: u32 = c_elf.SHT_NOBITS;
        pub const SHT_ARM_EXIDX: u32 = if (@hasDecl(c_elf, "SHT_ARM_EXIDX")) c_elf.SHT_ARM_EXIDX else 0x70000003;

        pub const SHF_WRITE: u32 = c_elf.SHF_WRITE;
        pub const SHF_ALLOC: u32 = c_elf.SHF_ALLOC;
        pub const SHF_EXECINSTR: u32 = c_elf.SHF_EXECINSTR;
        pub const SHF_LINK_ORDER: u32 = if (@hasDecl(c_elf, "SHF_LINK_ORDER")) c_elf.SHF_LINK_ORDER else 0x80;

        pub const PF_X: u32 = c_elf.PF_X;
        pub const PF_W: u32 = c_elf.PF_W;
        pub const PF_R: u32 = c_elf.PF_R;

        pub const STN_UNDEF: u16 = c_elf.STN_UNDEF;
        pub const STB_WEAK: u8 = c_elf.STB_WEAK;
        pub const STT_NOTYPE: u8 = c_elf.STT_NOTYPE;
        pub const SHN_ABS: u16 = c_elf.SHN_ABS;
    };

    pub const x86 = struct {
        pub const R_386_NONE = c_elf.R_386_NONE;
        pub const R_386_32 = c_elf.R_386_32;
        pub const R_386_PC32 = c_elf.R_386_PC32;
        pub const R_386_PLT32 = c_elf.R_386_PLT32;
    };
    pub const arm = struct {
        pub const R_ARM_NONE = c_elf.R_ARM_NONE;
        pub const R_ARM_ABS32 = c_elf.R_ARM_ABS32;
        pub const R_ARM_REL32 = c_elf.R_ARM_REL32;
        pub const R_ARM_PC24 = c_elf.R_ARM_PC24;
        pub const R_ARM_CALL = c_elf.R_ARM_CALL;
        pub const R_ARM_JUMP24 = c_elf.R_ARM_JUMP24;
        pub const R_ARM_PLT32 = c_elf.R_ARM_PLT32;
        pub const R_ARM_MOVW_ABS_NC = c_elf.R_ARM_MOVW_ABS_NC;
        pub const R_ARM_MOVT_ABS = c_elf.R_ARM_MOVT_ABS;
        pub const R_ARM_THM_CALL = c_elf.R_ARM_THM_CALL;
        pub const R_ARM_THM_JUMP24 = c_elf.R_ARM_THM_JUMP24;
        pub const R_ARM_THM_MOVW_ABS_NC = c_elf.R_ARM_THM_MOVW_ABS_NC;
        pub const R_ARM_THM_MOVT_ABS = c_elf.R_ARM_THM_MOVT_ABS;
        pub const R_ARM_V4BX = c_elf.R_ARM_V4BX;
        pub const R_ARM_PREL31 = 42;
        pub const SHT_ARM_EXIDX = if (@hasDecl(c_elf, "SHT_ARM_EXIDX")) c_elf.SHT_ARM_EXIDX else 0x70000003;
    };
    pub const riscv = struct {
        pub const R_RISCV_NONE = if (@hasDecl(c_elf, "R_RISCV_NONE")) c_elf.R_RISCV_NONE else 0;
        pub const R_RISCV_32 = if (@hasDecl(c_elf, "R_RISCV_32")) c_elf.R_RISCV_32 else 1;
        pub const R_RISCV_64 = if (@hasDecl(c_elf, "R_RISCV_64")) c_elf.R_RISCV_64 else 2;
        pub const R_RISCV_RELATIVE = if (@hasDecl(c_elf, "R_RISCV_RELATIVE")) c_elf.R_RISCV_RELATIVE else 3;
        pub const R_RISCV_BRANCH = if (@hasDecl(c_elf, "R_RISCV_BRANCH")) c_elf.R_RISCV_BRANCH else 16;
        pub const R_RISCV_JAL = if (@hasDecl(c_elf, "R_RISCV_JAL")) c_elf.R_RISCV_JAL else 17;
        pub const R_RISCV_CALL = if (@hasDecl(c_elf, "R_RISCV_CALL")) c_elf.R_RISCV_CALL else 18;
        pub const R_RISCV_HI20 = if (@hasDecl(c_elf, "R_RISCV_HI20")) c_elf.R_RISCV_HI20 else 26;
        pub const R_RISCV_LO12_I = if (@hasDecl(c_elf, "R_RISCV_LO12_I")) c_elf.R_RISCV_LO12_I else 27;
        pub const R_RISCV_PCREL_HI20 = if (@hasDecl(c_elf, "R_RISCV_PCREL_HI20")) c_elf.R_RISCV_PCREL_HI20 else 23;
        pub const R_RISCV_RELAX = 51;
        pub const R_RISCV_ALIGN = 43;
        pub const R_RISCV_LO12_S = 28;
        pub const R_RISCV_PCREL_LO12_I = 24;
        pub const R_RISCV_PCREL_LO12_S = 25;
        pub const R_RISCV_CALL_PLT = 19;
        pub const R_RISCV_ADD32 = 35;
        pub const R_RISCV_SUB32 = 39;
        pub const R_RISCV_32_PCREL = 57;
        pub const R_RISCV_SUB8 = 37;
        pub const R_RISCV_SUB16 = 38;
        pub const R_RISCV_SUB6 = 52;
        pub const R_RISCV_SET6 = 53;
        pub const R_RISCV_SET8 = 54;
        pub const R_RISCV_SET16 = 55;
        pub const R_RISCV_SET32 = 56;
    };

    pub const api = struct {
        // relocation helpers — called from common/elf.zig via machine_reloc module.
        // No extern fn needed; called via @import("machine_reloc") with Zig-native ABI.
    };
};

// ============================================================================
// ar.* — Unix `ar` archive format namespace.
// ============================================================================
const c_ar = @cImport({
    @cInclude("sys/ar.h");
});

pub const ar = struct {
    pub const constants = struct {
        pub const ARMAG = c_ar.ARMAG;
        pub const SARMAG = c_ar.SARMAG;
        pub const ARFMAG = c_ar.ARFMAG;
    };
    pub const @"struct" = c_ar.struct_ar_hdr;
};

// ============================================================================
// mem.* — physical memory types, bootinfo struct aliases, page helpers.
// Scoped @cImport for <sys/bootinfo.h> + <machine/memory.h>; the Zig-native
// struct aliases below are laid out to match C exactly so the kernel reads
// the same bit-for-bit layout.
// ============================================================================
const c_mem = @cImport({
    @cInclude("sys/bootinfo.h");
    @cInclude("machine/memory.h");
});

pub const mem = struct {
    pub const MT_USABLE = c_mem.MT_USABLE;
    pub const MT_MEMHOLE = c_mem.MT_MEMHOLE;
    pub const MT_RESERVED = c_mem.MT_RESERVED;
    pub const MT_BOOTDISK = c_mem.MT_BOOTDISK;

    pub const PhysMem = extern struct {
        base: usize,
        size: usize,
        type: c_int,
    };

    pub const is_armv8m: bool = @hasDecl(c_mem, "CONFIG_ARMV8M");
    pub const Module = if (is_armv8m)
        extern struct {
            name: [16]u8,
            phys: usize,
            size: usize,
            entry: usize,
            text: usize,
            data: usize,
            textsz: usize,
            datasz: usize,
            bsssz: usize,
            exidx_start: usize,
            exidx_size: usize,
            got_base: usize,
        }
    else
        extern struct {
            name: [16]u8,
            phys: usize,
            size: usize,
            entry: usize,
            text: usize,
            data: usize,
            textsz: usize,
            datasz: usize,
            bsssz: usize,
            exidx_start: usize,
            exidx_size: usize,
        };

    pub const VidInfo = extern struct {
        pixel_x: c_int,
        pixel_y: c_int,
        text_x: c_int,
        text_y: c_int,
    };

    pub const BootInfo = extern struct {
        video: VidInfo,
        ram: [8]PhysMem,
        nr_rams: c_int,
        bootdisk: PhysMem,
        nr_tasks: c_int,
        kernel: Module,
        driver: Module,
        tasks: [1]Module,
    };

    pub const BOOTINFOSZ = c_mem.BOOTINFOSZ;
    pub const NMEMS = c_mem.NMEMS;

    pub const page_size: usize = switch (builtin.cpu.arch) {
        .arm => if (@hasDecl(c_mem, "CONFIG_MMU")) 0x1000 else 0x400,
        .thumb => if (@hasDecl(c_mem, "CONFIG_MMU")) 0x1000 else 0x400,
        else => 0x1000,
    };
    pub const PAGE_SIZE: usize = page_size;
    pub const PAGE_MASK: usize = PAGE_SIZE - 1;
    pub const round_page = struct {
        pub fn apply(x: usize) usize {
            return (x + PAGE_MASK) & ~PAGE_MASK;
        }
    }.apply;
    pub const trunc_page = struct {
        pub fn apply(x: usize) usize {
            return x & ~PAGE_MASK;
        }
    }.apply;
};

// ============================================================================
// video.* — display info (unused alias kept for backwards compatibility
// with domain code that referenced ffi.video.*).
// ============================================================================
pub const video = struct {
    pub const VidInfo = c_mem.struct_vidinfo;
    pub const TEXT_X_DEFAULT: c_int = 80;
    pub const TEXT_Y_DEFAULT: c_int = 25;
};

// ============================================================================
// arch.* — per-arch extern fn decls and BSS-extern state.
// ============================================================================
pub const arch = struct {
    pub extern fn outb(port: c_int, val: u8) callconv(.c) void;
    pub extern fn inb(port: c_int) callconv(.c) u8;
    pub extern var lo_mem: paddr_t;
    pub extern var hi_mem: paddr_t;
    pub extern var sram_got_base: elf.types.Addr;
    pub extern var current_img: [*]u8;
    pub extern var current_module: [*]mem.Module;
    pub extern var current_symtab: [*]elf.types.Sym;
    pub extern var elf_type: elf.types.Half;
    pub extern var text_vma: elf.types.Addr;
    pub extern var data_vma: elf.types.Addr;
    pub extern var text_runtime: elf.types.Addr;
    pub extern var data_runtime: elf.types.Addr;
    pub extern var sram_load_base: paddr_t;
    pub extern var sram_load_start: paddr_t;
};

// ============================================================================
// cfg.* — compile-time configuration constants from <conf/config.h> and
// <sys/param.h>. The raw @cImport is exposed as cfg.config so callers can
// reach arbitrary CONFIG_* symbols without enumerating every one here.
// ============================================================================
const c_cfg = @cImport({
    @cInclude("conf/config.h");
    @cInclude("sys/param.h");
    @cInclude("machine/syspage.h");
});

pub const cfg = struct {
    pub const config = c_cfg;

    pub const CONFIG_LOADER_TEXT: usize = @intCast(c_cfg.CONFIG_LOADER_TEXT);
    pub const CONFIG_BOOTIMG_BASE: usize = @intCast(c_cfg.CONFIG_BOOTIMG_BASE);
    pub const CONFIG_KERNEL_TEXT: usize = @intCast(c_cfg.CONFIG_KERNEL_TEXT);
    pub const CONFIG_SYSPAGE_BASE: usize = @intCast(c_cfg.CONFIG_SYSPAGE_BASE);
    pub const CONFIG_SYSPAGE_PHY_BASE: usize = @intCast(c_cfg.CONFIG_SYSPAGE_PHY_BASE);
    pub const CONFIG_RAM_SIZE: usize = @intCast(c_cfg.CONFIG_RAM_SIZE);
    pub const CONFIG_PL011_PHY_BASE: usize = if (@hasDecl(c_cfg, "CONFIG_PL011_PHY_BASE")) @intCast(c_cfg.CONFIG_PL011_PHY_BASE) else 0;
    pub const CONFIG_PL011_CLK: u32 = if (@hasDecl(c_cfg, "CONFIG_PL011_CLK")) @intCast(c_cfg.CONFIG_PL011_CLK) else 0;
    pub const KERNOFFSET: usize = if (@hasDecl(c_cfg, "KERNOFFSET")) @intCast(c_cfg.KERNOFFSET) else 0;
    pub const KERNBASE: usize = if (@hasDecl(c_cfg, "KERNBASE")) @intCast(c_cfg.KERNBASE) else 0;
    pub const BOOTINFO: usize = @intCast(c_cfg.BOOTINFO);
    pub const BOOTSTK: usize = @intCast(c_cfg.BOOTSTK);
    pub const BOOTSTKTOP: usize = @intCast(c_cfg.BOOTSTKTOP);
    pub const BOOTSTKSZ: usize = @intCast(c_cfg.BOOTSTKSZ);
    pub const SYSPAGE: usize = @intCast(c_cfg.SYSPAGE);
    pub const SYSPAGESZ: usize = if (@hasDecl(c_cfg, "SYSPAGESZ")) @intCast(c_cfg.SYSPAGESZ) else 0;
    pub const CONFIG_NS16550_PHY_BASE: usize = if (@hasDecl(c_cfg, "CONFIG_NS16550_PHY_BASE")) @intCast(c_cfg.CONFIG_NS16550_PHY_BASE) else 0;
    pub const CONFIG_NS16550_BASE: usize = if (@hasDecl(c_cfg, "CONFIG_NS16550_BASE")) @intCast(c_cfg.CONFIG_NS16550_BASE) else 0;

    pub const DEBUG: bool = @hasDecl(c_cfg, "DEBUG");
    pub const DEBUG_BOOTINFO: bool = @hasDecl(c_cfg, "DEBUG_BOOTINFO");
    pub const DEBUG_ELF: bool = @hasDecl(c_cfg, "DEBUG_ELF");
    pub const CONFIG_DIAG_SERIAL: bool = @hasDecl(c_cfg, "CONFIG_DIAG_SERIAL");
    pub const CONFIG_DIAG_BOCHS: bool = @hasDecl(c_cfg, "CONFIG_DIAG_BOCHS");
    pub const CONFIG_DIAG_VBA: bool = @hasDecl(c_cfg, "CONFIG_DIAG_VBA");
};

// ============================================================================
// addr.* — address-space conversion helpers.
// ============================================================================
pub const addr = struct {
    pub inline fn ptokv(pa: usize) usize {
        return pa + cfg.KERNOFFSET;
    }
    pub inline fn kvtop(va: usize) usize {
        return va - cfg.KERNOFFSET;
    }
};

// ============================================================================
// print — type-safe Zig-style formatter ({d}, {u}, {x}, {s}, {c}).
//
// Light-weight formatter. std.fmt's full formatter pulls ~2 KB of general-
// purpose code that breaches the 8 KB bootloader cap on Flash-constrained
// targets (arm-raspi0, arm-integrator, arm-gba). This implementation parses
// the format string at *runtime* in a single shared interpreter, so per-call-
// site code is just arg type-erasure + a call — no comptime-generated spec
// arrays, no per-call-site rodata beyond the format string literal itself.
//
// Supported specifiers:
//     {d}  signed decimal
//     {u}  unsigned decimal
//     {x}  unsigned hex (lowercase)
//     {s}  string ([]const u8 or [*:0]const u8)
//     {c}  single byte
//     {{   literal '{'
//     }}   literal '}'
//
// `print()` writes through boot.debug_putc, translating '\n' to '\r\n' for
// terminals that expect CRLF (QEMU -nographic, serial consoles).
// ============================================================================

const ArgKind = enum { Int, Uint, Ptr, Slice };
const ErasedArg = union(ArgKind) {
    Int: i64,
    Uint: u64,
    Ptr: [*]const u8,
    Slice: []const u8,
};

const DIGITS_LOWER = "0123456789abcdef";

fn emitByte(b: u8) void {
    if (b == '\n') machine_debug.debug_putc('\r');
    machine_debug.debug_putc(b);
}

fn emitStr(s: []const u8) void {
    for (s) |b| emitByte(b);
}

fn emitUint(val: u64, base: u8) void {
    var buf: [24]u8 = undefined;
    var u = val;
    var i: usize = buf.len;
    if (u == 0) {
        i -= 1;
        buf[i] = '0';
    } else {
        while (u != 0) {
            i -= 1;
            buf[i] = DIGITS_LOWER[@intCast(u % base)];
            u /= base;
        }
    }
    emitStr(buf[i..]);
}

/// Single shared runtime interpreter. Parses the format string at runtime,
/// dispatching to emit primitives for each spec/arg. NOT generic — one copy
/// for all call sites. No comptime-generated spec arrays.
fn printRuntimeRaw(fmt: []const u8, args: []const ErasedArg) void {
    var i: usize = 0;
    var arg_idx: usize = 0;
    var lit_start: usize = 0;
    while (i < fmt.len) {
        // {{ or }}
        if (i + 1 < fmt.len and fmt[i] == '{' and fmt[i + 1] == '{') {
            if (lit_start < i) emitStr(fmt[lit_start..i]);
            emitByte('{');
            i += 2;
            lit_start = i;
            continue;
        }
        if (i + 1 < fmt.len and fmt[i] == '}' and fmt[i + 1] == '}') {
            if (lit_start < i) emitStr(fmt[lit_start..i]);
            emitByte('}');
            i += 2;
            lit_start = i;
            continue;
        }
        // {spec}
        if (i + 2 < fmt.len and fmt[i] == '{' and fmt[i + 2] == '}') {
            if (lit_start < i) emitStr(fmt[lit_start..i]);
            const spec = fmt[i + 1];
            i += 3;
            lit_start = i;
            const arg = args[arg_idx];
            arg_idx += 1;
            switch (spec) {
                'd' => {
                    const val = arg.Int;
                    if (val < 0) emitByte('-');
                    const abs: u64 = if (val < 0) @intCast(-@as(i128, val)) else @intCast(val);
                    emitUint(abs, 10);
                },
                'u' => emitUint(arg.Uint, 10),
                'x' => emitUint(arg.Uint, 16),
                's' => switch (arg) {
                    .Slice => |slice| emitStr(slice),
                    .Ptr => |ptr| {
                        var len: usize = 0;
                        while (ptr[len] != 0) : (len += 1) {}
                        emitStr(ptr[0..len]);
                    },
                    .Int, .Uint => {},
                },
                'c' => emitByte(@intCast(arg.Int)),
                else => {},
            }
            continue;
        }
        i += 1;
    }
    if (lit_start < fmt.len) emitStr(fmt[lit_start..]);
}

/// Public typed formatter. `{d}` `{u}` `{x}` `{s}` `{c}`; `{{` and `}}` for
/// literal braces. The format string is parsed at *runtime* by a single
/// shared interpreter; per-call-site code is only arg type-erasure.
/// `inline fn` ensures args are monomorphised at compile time, but the
/// interpreter is non-generic (one copy total).
pub inline fn print(comptime fmt: []const u8, args: anytype) void {
    // Comptime: count specifiers and validate against arg count.
    const fields = @typeInfo(@TypeOf(args)).@"struct".fields;
    comptime var spec_count: usize = 0;
    comptime var i: usize = 0;
    inline while (i < fmt.len) : (i += 1) {
        if (i + 2 < fmt.len and fmt[i] == '{' and fmt[i + 2] == '}') {
            switch (fmt[i + 1]) {
                'd', 'u', 'x', 's', 'c' => spec_count += 1,
                else => @compileError("print: unknown specifier '{" ++ &[1]u8{fmt[i + 1]} ++ "}'"),
            }
            if (spec_count > fields.len) @compileError("print: format uses more specifiers than args");
            i += 2;
        } else if (i + 1 < fmt.len and (fmt[i] == '{' or fmt[i] == '}') and fmt[i] == fmt[i + 1]) {
            i += 1;
        }
    }
    if (spec_count != fields.len) @compileError("print: format specifier count does not match arg count");

    // Runtime: type-erase args into ErasedArg array, call shared interpreter.
    var erased_args: [8]ErasedArg = undefined;
    var arg_idx: usize = 0;
    inline for (fields) |field| {
        const val = @field(args, field.name);
        const T = @TypeOf(val);
        const info = @typeInfo(T);
        if (info == .int) {
            if (info.int.signedness == .signed) {
                erased_args[arg_idx] = ErasedArg{ .Int = @as(i64, @intCast(val)) };
            } else {
                erased_args[arg_idx] = ErasedArg{ .Uint = @as(u64, @intCast(val)) };
            }
        } else if (info == .pointer) {
            if (info.pointer.size == .slice) {
                erased_args[arg_idx] = ErasedArg{ .Slice = val };
            } else {
                erased_args[arg_idx] = ErasedArg{ .Ptr = val };
            }
        } else {
            @compileError("print: unsupported argument type " ++ @typeName(T));
        }
        arg_idx += 1;
    }
    printRuntimeRaw(fmt, erased_args[0..arg_idx]);
}
