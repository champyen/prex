// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
// All rights reserved.

const ffi = @import("ffi");

pub fn startup() void {
    const bi = ffi.boot.bootinfo;

    // Usable: Entire DRAM (starting from 0x80000000)
    bi.ram[0].base = 0x80000000;
    bi.ram[0].size = ffi.cfg.CONFIG_RAM_SIZE;
    bi.ram[0].type = ffi.mem.MT_USABLE;

    // Reserved: System Page (0x80000000 - 0x8000FFFF)
    // This covers M-mode jump, System Page, BootInfo, Loader Stacks, and PGT.
    bi.ram[1].base = ffi.cfg.CONFIG_SYSPAGE_BASE;
    bi.ram[1].size = ffi.cfg.SYSPAGESZ;
    bi.ram[1].type = ffi.mem.MT_RESERVED;

    // Reserved: Bootloader (0x80010000 - 0x80013FFF)
    // For RISC-V, the M-mode trap handler stays resident in the bootloader.
    bi.ram[2].base = ffi.cfg.CONFIG_LOADER_TEXT;
    bi.ram[2].size = 0x4000; // 16KB
    bi.ram[2].type = ffi.mem.MT_RESERVED;

    bi.nr_rams = 3;
}
