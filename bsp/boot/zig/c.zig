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

// bsp/boot/zig/c.zig — flat @cImport hub for the bootloader.
//
// Mirrors sys/c.zig: every C/asm symbol from <boot.h>, <sys/elf.h>,
// <sys/ar.h>, <sys/bootinfo.h>, <machdep.h>, <elf_reloc.h>, <load.h>,
// and <conf/config.h> is exposed flatly as `c.<name>`.
//
// This file is imported ONLY by bsp/boot/zig/ffi.zig. Domain .zig files
// in bsp/boot/common/ and bsp/boot/<arch>/<plat>/ must never import this
// file directly — they go through ffi.zig for typed/organized access.

// bsp/boot/zig/c.zig — flat @cImport hub for the bootloader.
//
// KERNEL, DEBUG, __arm__, __qemu_virt__, etc. are all defined by the
// build system (mk/own.mk → bsp/boot/Makefile → mk/zig.mk → zig build-obj
// -D flags). They propagate to the C preprocessor inside @cImport so
// `c.KERNEL`, `c.DEBUG`, etc. are visible here. Do NOT @cDefine them here
// — that would hardcode build-flavor constants.

pub const c = @cImport({
    // Standard C primitive types (c_int, c_long, c_ulong, c_uchar, ...).
    // These are re-exported by ffi.zig as `ffi.CInt` etc. for domain code.
    @cInclude("stdint.h");
    @cInclude("stddef.h");
    @cInclude("boot.h");        // bsp/boot/include/boot.h
    @cInclude("elf_reloc.h");
    @cInclude("machdep.h");
    @cInclude("load.h");
    @cInclude("sys/elf.h");
    @cInclude("sys/ar.h");
    @cInclude("sys/types.h");    // MUST be before sys/bootinfo.h (defines paddr_t)
    @cInclude("sys/bootinfo.h");
    @cInclude("sys/param.h");
    @cInclude("sys/elf.h");
    @cInclude("sys/ar.h");
    @cInclude("conf/config.h");
    @cInclude("machine/memory.h"); // KERNOFFSET, KERNBASE, PAGE_SIZE
});
