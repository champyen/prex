// SPDX-License-Identifier: BSD-2-Clause
//
// Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
// All rights reserved.
//
// bsp/boot/zig_main.zig — Root translation unit for the unified Zig bootloader.

const ffi = @import("ffi");

comptime {
    _ = @import("common/main.zig");
    _ = @import("common/bootinfo.zig");
    _ = @import("common/load.zig");
    _ = @import("common/elf.zig");
    _ = @import("common/splash.zig");
    _ = @import("string_mod");
    _ = @import("panic_mod");
    _ = @import("machine_startup");
    _ = @import("machine_debug");
    _ = @import("machine_reloc");
    _ = @import("zig/runtime.zig");
}
