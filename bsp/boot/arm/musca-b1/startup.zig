// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
// All rights reserved.

const ffi = @import("ffi");

pub export fn startup() callconv(.c) void {
    const bi = ffi.boot.bootinfo;
    bi.video.text_x = 80;
    bi.video.text_y = 25;
    bi.ram[0].base = ffi.cfg.CONFIG_SYSPAGE_PHY_BASE;
    bi.ram[0].size = ffi.cfg.CONFIG_RAM_SIZE;
    bi.ram[0].type = ffi.mem.MT_USABLE;
    bi.nr_rams = 1;
}
