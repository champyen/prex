// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2005-2009, Kohsuke Ohtani
// Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
// All rights reserved.

const ffi = @import("ffi");

extern var lo_mem: ffi.paddr_t;
extern var hi_mem: ffi.paddr_t;

pub fn startup() void {
    const bi = ffi.boot.bootinfo;

    // Screen size
    bi.video.text_x = 80;
    bi.video.text_y = 25;

    // Main memory
    bi.ram[0].base = 0;
    bi.ram[0].size = @intCast((1024 + hi_mem) * 1024);
    bi.ram[0].type = ffi.mem.MT_USABLE;
    bi.nr_rams = 1;

    // Add BIOS ROM and VRAM area
    if (hi_mem != 0) {
        bi.ram[1].base = lo_mem * 1024;
        bi.ram[1].size = @intCast((1024 - lo_mem) * 1024);
        bi.ram[1].type = ffi.mem.MT_MEMHOLE;
        bi.nr_rams += 1;
    }
}
