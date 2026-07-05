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

// bsp/boot/zig/ffi.zig — typed/organized namespace for the bootloader.
//
// Mirrors sys/ffi.zig. Every bootloader-relevant function and constant is
// re-exported under a per-domain sub-namespace so that domain .zig files
// (in bsp/boot/common/ and bsp/boot/<arch>/<plat>/) write:
//
//     const ffi = @import("ffi");
//     ffi.boot.panic("…");
//     ffi.elf.arm.R_ARM_ABS32
//     ffi.ar.constants.ARMAG
//     ffi.mem.MT_USABLE
//     ffi.cfg.config.CONFIG_LOADER_TEXT
//
// and NEVER touch c.<name> directly.
//
// This is Stage 1: the namespaces are skeletons populated as each port
// stage lands (see zig_boot_plan.md §4a for the full design).

const c = @import("c").c;
const builtin = @import("builtin");

// ============================================================================
// C-ABI types that are NOT Zig built-in primitives. These come from the
// @cImport namespace and are re-exported here so domain code can use them
// uniformly. Domain code should prefer the Zig built-in primitives
// (c_char, c_short, c_ushort, c_int, c_uint, c_long, c_ulong, c_longlong,
// c_ulonglong) directly when possible — no aliasing needed for those.
// ============================================================================
pub const size_t = c.size_t;
pub const ssize_t = c.ssize_t;
pub const intptr_t = c.intptr_t;
pub const uintptr_t = c.uintptr_t;
pub const paddr_t = c.paddr_t;
pub const vaddr_t = c.vaddr_t;
pub const psize_t = c.psize_t;
pub const vsize_t = c.vsize_t;

// ============================================================================
// boot.* — C-ABI entry points and BSS-extern state. These are the bootloader's
// external surface, called from head.S and from the linker.
// ============================================================================
pub const boot = struct {
    pub extern fn main() callconv(.c) c_int;
    pub extern fn panic(msg: [*c]const u8) callconv(.c) noreturn;
    pub extern fn startup() callconv(.c) void;
    pub extern fn debug_init() callconv(.c) void;
    pub extern fn debug_putc(c_val: c_int) callconv(.c) void;
    pub extern fn splash() callconv(.c) void;
    pub extern fn load_os() callconv(.c) void;
    pub extern fn dump_bootinfo(bi: ?*mem.BootInfo) callconv(.c) void;
    pub extern fn __boot_bootinfo_init() callconv(.c) void;
    pub const boot_bootinfo_init = __boot_bootinfo_init;
    pub extern fn printf(fmt: [*c]const u8, ...) callconv(.c) void;

    pub var bootinfo: *mem.BootInfo = @ptrCast(@as(*mem.BootInfo, @ptrFromInt(cfg.BOOTINFO -% cfg.KERNOFFSET)));
    pub extern var load_base: paddr_t;
    pub extern var load_start: paddr_t;
    pub extern var nr_img: c_int;

    pub extern fn memcpy(dest: ?*anyopaque, src: ?*const anyopaque, n: c_ulong) callconv(.c) ?*anyopaque;
    pub extern fn memset(dest: ?*anyopaque, c_val: c_int, n: c_ulong) callconv(.c) ?*anyopaque;
    pub extern fn strncmp(s1: [*c]const u8, s2: [*c]const u8, n: c_ulong) callconv(.c) c_int;
    pub extern fn strlcpy(dst: [*c]u8, src: [*c]const u8, siz: c_ulong) callconv(.c) c_ulong;
    pub extern fn atol(s: [*c]const u8) callconv(.c) c_long;
    pub extern fn _jump_to_kernel(entry: usize) callconv(.c) void;
    pub const jump_to_kernel = _jump_to_kernel;
};

// ============================================================================
// elf.* — ELF loader namespace (skeleton; populated in Stage 4a + 4b).
// ============================================================================
pub const elf = struct {
    // elf.types — shared ELF struct aliases + format constants.
    pub const types = struct {
        pub const Ehdr = c.Elf32_Ehdr;
        pub const Phdr = c.Elf32_Phdr;
        pub const Shdr = c.Elf32_Shdr;
        pub const Sym = c.Elf32_Sym;
        pub const Rel = c.Elf32_Rel;
        pub const Rela = c.Elf32_Rela;
        pub const Addr = c.Elf32_Addr;
        pub const Off = c.Elf32_Off;
        pub const Word = c.Elf32_Word;
        pub const Half = c.Elf32_Half;
        pub const Sword = c.Elf32_Sword;

        // ELF header / identification (exposed as plain u8/u16/u32 values
        // so the constants have a concrete type at comptime; needed because
        // elf32_e_ident is u8[EI_NIDENT] which is many-pointer-indexed).
        pub const EI_MAG0: u8 = c.EI_MAG0;
        pub const EI_MAG1: u8 = c.EI_MAG1;
        pub const EI_MAG2: u8 = c.EI_MAG2;
        pub const EI_MAG3: u8 = c.EI_MAG3;
        pub const ELFMAG0: u8 = c.ELFMAG0;
        pub const ELFMAG1: u8 = c.ELFMAG1;
        pub const ELFMAG2: u8 = c.ELFMAG2;
        pub const ELFMAG3: u8 = c.ELFMAG3;
        pub const ELFMAG = c.ELFMAG;
        pub const SELFMAG = c.SELFMAG;

        // e_type
        pub const ET_NONE: u16 = c.ET_NONE;
        pub const ET_REL: u16 = c.ET_REL;
        pub const ET_EXEC: u16 = c.ET_EXEC;
        pub const ET_DYN: u16 = c.ET_DYN;
        pub const ET_CORE: u16 = c.ET_CORE;

        // p_type
        pub const PT_NULL: u32 = c.PT_NULL;
        pub const PT_LOAD: u32 = c.PT_LOAD;
        pub const PT_DYNAMIC: u32 = c.PT_DYNAMIC;
        pub const PT_NOTE: u32 = c.PT_NOTE;
        pub const PT_ARM_EXIDX: u32 = if (@hasDecl(c, "PT_ARM_EXIDX")) c.PT_ARM_EXIDX else 0x70000000;

        // sh_type
        pub const SHT_NULL: u32 = c.SHT_NULL;
        pub const SHT_PROGBITS: u32 = c.SHT_PROGBITS;
        pub const SHT_SYMTAB: u32 = c.SHT_SYMTAB;
        pub const SHT_STRTAB: u32 = c.SHT_STRTAB;
        pub const SHT_RELA: u32 = c.SHT_RELA;
        pub const SHT_REL: u32 = c.SHT_REL;
        pub const SHT_NOBITS: u32 = c.SHT_NOBITS;
        pub const SHT_ARM_EXIDX: u32 = if (@hasDecl(c, "SHT_ARM_EXIDX")) c.SHT_ARM_EXIDX else 0x70000003;

        // sh_flags
        pub const SHF_WRITE: u32 = c.SHF_WRITE;
        pub const SHF_ALLOC: u32 = c.SHF_ALLOC;
        pub const SHF_EXECINSTR: u32 = c.SHF_EXECINSTR;
        pub const SHF_LINK_ORDER: u32 = if (@hasDecl(c, "SHF_LINK_ORDER")) c.SHF_LINK_ORDER else 0x80;

        // p_flags
        pub const PF_X: u32 = c.PF_X;
        pub const PF_W: u32 = c.PF_W;
        pub const PF_R: u32 = c.PF_R;

        // symbol table
        pub const STN_UNDEF: u16 = c.STN_UNDEF;
        pub const STB_WEAK: u8 = c.STB_WEAK;
        pub const STT_NOTYPE: u8 = c.STT_NOTYPE;
        pub const SHN_ABS: u16 = c.SHN_ABS;
    };

    // Per-arch relocation type enums.
    pub const x86 = struct {
        pub const R_386_NONE = c.R_386_NONE;
        pub const R_386_32 = c.R_386_32;
        pub const R_386_PC32 = c.R_386_PC32;
        pub const R_386_PLT32 = c.R_386_PLT32;
    };
    pub const arm = struct {
        pub const R_ARM_NONE = c.R_ARM_NONE;
        pub const R_ARM_ABS32 = c.R_ARM_ABS32;
        pub const R_ARM_REL32 = c.R_ARM_REL32;
        pub const R_ARM_PC24 = c.R_ARM_PC24;
        pub const R_ARM_CALL = c.R_ARM_CALL;
        pub const R_ARM_JUMP24 = c.R_ARM_JUMP24;
        pub const R_ARM_PLT32 = c.R_ARM_PLT32;
        pub const R_ARM_MOVW_ABS_NC = c.R_ARM_MOVW_ABS_NC;
        pub const R_ARM_MOVT_ABS = c.R_ARM_MOVT_ABS;
        pub const R_ARM_THM_CALL = c.R_ARM_THM_CALL;
        pub const R_ARM_THM_JUMP24 = c.R_ARM_THM_JUMP24;
        pub const R_ARM_THM_MOVW_ABS_NC = c.R_ARM_THM_MOVW_ABS_NC;
        pub const R_ARM_THM_MOVT_ABS = c.R_ARM_THM_MOVT_ABS;
        pub const R_ARM_V4BX = c.R_ARM_V4BX;
        pub const R_ARM_PREL31 = 42; // R_ARM_PREL31 = 42 per ARM ELF spec
        pub const SHT_ARM_EXIDX = if (@hasDecl(c, "SHT_ARM_EXIDX")) c.SHT_ARM_EXIDX else 0x70000003;
    };
    pub const riscv = struct {
        pub const R_RISCV_NONE = if (@hasDecl(c, "R_RISCV_NONE")) c.R_RISCV_NONE else 0;
        pub const R_RISCV_32 = if (@hasDecl(c, "R_RISCV_32")) c.R_RISCV_32 else 1;
        pub const R_RISCV_64 = if (@hasDecl(c, "R_RISCV_64")) c.R_RISCV_64 else 2;
        pub const R_RISCV_RELATIVE = if (@hasDecl(c, "R_RISCV_RELATIVE")) c.R_RISCV_RELATIVE else 3;
        pub const R_RISCV_BRANCH = if (@hasDecl(c, "R_RISCV_BRANCH")) c.R_RISCV_BRANCH else 16;
        pub const R_RISCV_JAL = if (@hasDecl(c, "R_RISCV_JAL")) c.R_RISCV_JAL else 17;
        pub const R_RISCV_CALL = if (@hasDecl(c, "R_RISCV_CALL")) c.R_RISCV_CALL else 18;
        pub const R_RISCV_HI20 = if (@hasDecl(c, "R_RISCV_HI20")) c.R_RISCV_HI20 else 26;
        pub const R_RISCV_LO12_I = if (@hasDecl(c, "R_RISCV_LO12_I")) c.R_RISCV_LO12_I else 27;
        pub const R_RISCV_PCREL_HI20 = if (@hasDecl(c, "R_RISCV_PCREL_HI20")) c.R_RISCV_PCREL_HI20 else 23;
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

    // API functions. The function-pointer type aliases use `mem.Module` /
    // `elf.types.*` rather than the raw `c.struct_*` so domain code never
    // touches `c.*` directly (per zig_boot_plan.md §4a "no raw c.* in
    // domain code" rule).
    pub const api = struct {
        pub extern fn load_elf(img: [*]u8, size: usize, module: *mem.Module) callconv(.c) c_int;
        pub extern fn relocate_rel(rel: *elf.types.Rel, sym_val: elf.types.Addr, target_sect: [*]u8) callconv(.c) c_int;
        pub extern fn relocate_rela(rela: *elf.types.Rela, sym_val: elf.types.Addr, target_sect: [*]u8) callconv(.c) c_int;
    };
};

// ============================================================================
// ar.* — Unix `ar` archive format namespace.
// ============================================================================
pub const ar = struct {
    pub const constants = struct {
        pub const ARMAG = c.ARMAG;
        pub const SARMAG = c.SARMAG;
        pub const ARFMAG = c.ARFMAG;
    };
    pub const @"struct" = c.struct_ar_hdr;
};

// ============================================================================
// mem.* — physical memory types, bootinfo struct aliases, page helpers.
// ============================================================================
pub const mem = struct {
    pub const MT_USABLE = c.MT_USABLE;
    pub const MT_MEMHOLE = c.MT_MEMHOLE;
    pub const MT_RESERVED = c.MT_RESERVED;
    pub const MT_BOOTDISK = c.MT_BOOTDISK;

    // C's `struct physmem` uses paddr_t (unsigned long) for base and size.
    // On 32-bit targets, unsigned long = usize. Define our own layout
    // instead of using c.struct_physmem to avoid cimport typedef issues.
    pub const PhysMem = extern struct {
        base: usize,
        size: usize,
        type: c_int,
    };

    // C's `struct module` from <sys/bootinfo.h>. Use usize for paddr_t/vaddr_t/size_t
    // to match C's unsigned long on 32-bit targets.
    //
    // The struct layout must match C EXACTLY — see include/sys/bootinfo.h.
    // For ARMv8-M the C struct has a trailing `got_base` field; if we omit
    // it, the kernel reads subsequent modules with field offsets shifted by
    // 4 bytes (it would read `m->text` instead of `m->entry`, causing the
    // musca-b1 hard-fault crash).
    //
    // Zig handles the @hasDecl check. Since CONFIG_ARMV8M is defined via -D,
    // @hasDecl works. The Value 'y' doesn't matter — we only need to know
    // whether CONFIG_ARMV8M is declared.
    pub const is_armv8m: bool = @hasDecl(c, "CONFIG_ARMV8M");
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

    // C's `struct bootinfo` from <sys/bootinfo.h>. Define with Zig primitives.
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

    pub const VidInfo = extern struct {
        pixel_x: c_int,
        pixel_y: c_int,
        text_x: c_int,
        text_y: c_int,
    };

    pub const BOOTINFOSZ = c.BOOTINFOSZ;
    pub const NMEMS = c.NMEMS;

    // Function-pointer type aliases
    // Function-pointer type aliases (interfaces) for bootinfo/module ops.
    // Domain code references these types; the actual function pointers
    // live in `boot.*` and `elf.api.*` below.
    pub const BootInfoDumper = *const fn ([*c]BootInfo) callconv(.c) void;
    pub const ModuleOp = *const fn ([*c]Module) callconv(.c) c_int;

    // PAGE_SIZE matches include/<arch>/memory.h:
    //   - arm nommu: 1024 (1KB)
    //   - arm mmu:   4096 (4KB)
    //   - riscv:     4096 (always)
    //   - x86:       4096 (always)
    // CONFIG_MMU value (y/1) is opaque to Zig cimport, so we use a filename-
    // style table derived from builtin.cpu.arch + the build's --mcpu flag.
    pub const page_size: usize = switch (builtin.cpu.arch) {
        .arm => if (@hasDecl(c, "CONFIG_MMU")) 0x1000 else 0x400,
        .thumb => if (@hasDecl(c, "CONFIG_MMU")) 0x1000 else 0x400,
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
// video.* — display info.
// ============================================================================
pub const video = struct {
    pub const VidInfo = c.struct_vidinfo;
    pub const TEXT_X_DEFAULT: c_int = 80;
    pub const TEXT_Y_DEFAULT: c_int = 25;
};

// ============================================================================
// arch.* — per-arch extern fn decls and helpers (populated as reloc engines land).
// ============================================================================
pub const arch = struct {
    // x86: assembly helpers in bsp/boot/x86/pc/head.S
    pub extern fn outb(port: c_int, val: u8) callconv(.c) void;
    pub extern fn inb(port: c_int) callconv(.c) u8;

    // x86: BSS counters populated by head.S
    pub extern var lo_mem: paddr_t;
    pub extern var hi_mem: paddr_t;

    // ARMv8-M: relocation helpers (defined in bsp/boot/zig/reloc/arm_reloc.zig)
    pub extern var sram_got_base: elf.types.Addr;
    pub extern var current_img: [*]u8;
    pub extern var current_module: [*]mem.Module;
    pub extern var current_symtab: [*]elf.types.Sym;
    pub extern var elf_type: elf.types.Half;
    pub extern var text_vma: elf.types.Addr;
    pub extern var data_vma: elf.types.Addr;
    pub extern var text_runtime: elf.types.Addr;
    pub extern var data_runtime: elf.types.Addr;

    // ARMv8-M: load base/start for SRAM relocation (defined in bsp/boot/zig/reloc/arm_reloc.zig
    // or bsp/boot/arm/arch/machdep.c; extern because they live in BSS)
    pub extern var sram_load_base: paddr_t;
    pub extern var sram_load_start: paddr_t;
};

// ============================================================================
// cfg.* — compile-time configuration constants.
//   cfg.config  : CONFIG_* from conf/config.h
//   cfg.syspage : BOOTINFO, BOOTSTK, BOOTSTKTOP, etc.
//   cfg.kernel  : KERNOFFSET, KERNBASE
// ============================================================================
pub const cfg = struct {
    // CONFIG_LOADER_TEXT, CONFIG_BOOTIMG_BASE, etc. — flat aliases for
    // domain code that needs build configuration. Only the well-known
    // CONFIG_ and BOOTINFO/BOOTSTK symbols are enumerated; if more are
    // needed they should be added here, not via `usingnamespace`.
    pub const CONFIG_LOADER_TEXT: usize = @intCast(c.CONFIG_LOADER_TEXT);
    pub const CONFIG_BOOTIMG_BASE: usize = @intCast(c.CONFIG_BOOTIMG_BASE);
    pub const CONFIG_KERNEL_TEXT: usize = @intCast(c.CONFIG_KERNEL_TEXT);
    pub const CONFIG_SYSPAGE_BASE: usize = @intCast(c.CONFIG_SYSPAGE_BASE);
    pub const CONFIG_SYSPAGE_PHY_BASE: usize = @intCast(c.CONFIG_SYSPAGE_PHY_BASE);
    pub const CONFIG_RAM_SIZE: usize = @intCast(c.CONFIG_RAM_SIZE);
    pub const CONFIG_PL011_PHY_BASE: usize = if (@hasDecl(c, "CONFIG_PL011_PHY_BASE")) @intCast(c.CONFIG_PL011_PHY_BASE) else 0;
    pub const CONFIG_PL011_CLK: u32 = if (@hasDecl(c, "CONFIG_PL011_CLK")) @intCast(c.CONFIG_PL011_CLK) else 0;
    pub const KERNOFFSET: usize = if (@hasDecl(c, "KERNOFFSET")) @intCast(c.KERNOFFSET) else 0;
    pub const KERNBASE: usize = if (@hasDecl(c, "KERNBASE")) @intCast(c.KERNBASE) else 0;
    pub const BOOTINFO: usize = @intCast(c.BOOTINFO);
    pub const BOOTSTK: usize = @intCast(c.BOOTSTK);
    pub const BOOTSTKTOP: usize = @intCast(c.BOOTSTKTOP);
    pub const BOOTSTKSZ: usize = @intCast(c.BOOTSTKSZ);
    pub const SYSPAGE: usize = @intCast(c.SYSPAGE);
    pub const SYSPAGESZ: usize = if (@hasDecl(c, "SYSPAGESZ")) @intCast(c.SYSPAGESZ) else 0;
    pub const CONFIG_NS16550_PHY_BASE: usize = if (@hasDecl(c, "CONFIG_NS16550_PHY_BASE")) @intCast(c.CONFIG_NS16550_PHY_BASE) else 0;
    pub const CONFIG_NS16550_BASE: usize = if (@hasDecl(c, "CONFIG_NS16550_BASE")) @intCast(c.CONFIG_NS16550_BASE) else 0;

    // Compile-time feature gates exposed to domain code (Zig 0.16 does not
    // support `c.X` introspection outside of `c.zig`).
    pub const DEBUG: bool = @hasDecl(c, "DEBUG");
    pub const DEBUG_BOOTINFO: bool = @hasDecl(c, "DEBUG_BOOTINFO");
    pub const DEBUG_ELF: bool = @hasDecl(c, "DEBUG_ELF");
    pub const CONFIG_DIAG_SERIAL: bool = @hasDecl(c, "CONFIG_DIAG_SERIAL");
    pub const CONFIG_DIAG_BOCHS: bool = @hasDecl(c, "CONFIG_DIAG_BOCHS");
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
// print — type-safe string formatting utilizing std.fmt.format
// ============================================================================
const std = @import("std");

pub noinline fn printStr(ptr: [*]const u8) void {
    var idx: usize = 0;
    while (ptr[idx] != 0) : (idx += 1) {
        c.debug_putc(@intCast(ptr[idx]));
    }
}

pub noinline fn printHex(u: u32) void {
    const digits = "0123456789abcdef";
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        const shift: u5 = @intCast((7 - i) * 4);
        const digit_val = (u >> shift) & 0xf;
        c.debug_putc(@intCast(digits[digit_val]));
    }
}

pub noinline fn printDec(val: u32) void {
    const digits = "0123456789";
    var u: u32 = val;
    if (u == 0) {
        c.debug_putc('0');
        return;
    }
    var buf: [10]u8 = undefined;
    var idx: usize = 0;
    while (u > 0) {
        buf[idx] = digits[u % 10];
        idx += 1;
        u /= 10;
    }
    while (idx > 0) {
        idx -= 1;
        c.debug_putc(@intCast(buf[idx]));
    }
}

noinline fn printVal(val: anytype) void {
    const T = @TypeOf(val);
    if (@typeInfo(T) == .pointer) {
        printStr(@ptrCast(val));
    } else {
        printDec(@bitCast(@as(i32, @intCast(val))));
    }
}

pub noinline fn print(format: [*c]const u8, args: anytype) void {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    const fields = args_type_info.@"struct".fields;

    var arg_idx: usize = 0;
    var i: usize = 0;
    while (format[i] != 0) {
        if (format[i] == '{') {
            if (format[i + 1] == '}') {
                inline for (fields, 0..) |field, f_idx| {
                    if (f_idx == arg_idx) {
                        const val = @field(args, field.name);
                        printVal(val);
                    }
                }
                arg_idx += 1;
                i += 2;
                continue;
            } else if (format[i + 2] == '}') {
                const spec = format[i + 1];
                inline for (fields, 0..) |field, f_idx| {
                    if (f_idx == arg_idx) {
                        const val = @field(args, field.name);
                        const T = @TypeOf(val);
                        if (spec == 'x') {
                            const u: u32 = if (@typeInfo(T) == .pointer) @intCast(@intFromPtr(val)) else @bitCast(@as(i32, @intCast(val)));
                            printHex(u);
                        } else if (spec == 'd') {
                            if (@typeInfo(T) == .pointer) {
                                printHex(@intCast(@intFromPtr(val)));
                            } else {
                                printDec(@bitCast(@as(i32, @intCast(val))));
                            }
                        } else if (spec == 's') {
                            if (@typeInfo(T) == .pointer) {
                                printStr(@ptrCast(val));
                            } else {
                                printDec(@bitCast(@as(i32, @intCast(val))));
                            }
                        }
                    }
                }
                arg_idx += 1;
                i += 3;
                continue;
            }
        }
        
        const byte = format[i];
        if (byte == '\n') {
            c.debug_putc('\r');
        }
        c.debug_putc(@intCast(byte));
        i += 1;
    }
}

