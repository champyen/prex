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

// bsp/boot/common/bootinfo.zig — boot information for the bootloader.
//
// Replaces common/bootinfo.c.
//
// All functions exposed as plain Zig — callable directly via @import
// from other files in this module (root). No C ABI boundary needed
// because the bootloader is a standalone Zig program.
//
// The `bootinfo` global BSS pointer is still exported under C name
// `bootinfo` because the C-fallback bootloader path references it.
const ffi = @import("ffi");

// bootinfo: pointer to the bootinfo structure in the SYSPAGE BSS.
pub var bootinfo: [*c]ffi.mem.BootInfo = undefined;

comptime {
    @export(&bootinfo, .{ .name = "bootinfo", .linkage = .strong });
}

pub fn boot_bootinfo_init() void {
    // kvtop(BOOTINFO) — convert virtual BOOTINFO address to physical.
    // KERNOFFSET is the per-arch offset; KERNOFFSET=0 means 1:1 mapping.
    bootinfo = @ptrFromInt(ffi.cfg.BOOTINFO -% ffi.cfg.KERNOFFSET);
}

// Memory region type strings for dumpBootinfo.
const memtype: [5][*:0]const u8 = .{
    "",                        // index 0 unused
    "USABLE",
    "MEMHOLE",
    "RESERVED",
    "BOOTDISK",
};

pub fn dumpBootinfo() void {
    const bi: [*]const ffi.mem.BootInfo = bootinfo;
    var i: c_int = 0;

    ffi.print("[Boot information]\n", .{});
    ffi.print("nr_rams={d}\n", .{bi[0].nr_rams});

    while (i < bi[0].nr_rams) : (i += 1) {
        const idx: usize = @intCast(i);
        const ram_entry = &bi[0].ram[idx];
        if (ram_entry.type != 0) {
            const t = ram_entry.type;
            const type_str: [*c]const u8 = if (t >= 0 and t < 5) memtype[@intCast(t)] else "";
            ffi.print("ram[{d}]:  base={x} size={x} type={s}\n", .{ i, ram_entry.base, ram_entry.size, type_str });
        }
    }

    ffi.print("bootdisk: base={x} size={x}\n", .{ bi[0].bootdisk.base, bi[0].bootdisk.size });
    ffi.print("entry    phys     size     text     data     textsz   datasz   bsssz    module\n", .{});

    ffi.print("-------- -------- -------- -------- -------- -------- -------- -------- ------\n", .{});
    printModule(&bi[0].kernel);
    printModule(&bi[0].driver);

    var m: [*]ffi.mem.Module = @ptrCast(@constCast(&bi[0].tasks[0]));
    i = 0;
    while (i < bi[0].nr_tasks) : (i += 1) {
        printModule(@ptrCast(m));
        m += 1;
    }
}

pub fn dumpBootinfoNoop() void {}

fn printModule(m: *const ffi.mem.Module) void {
    ffi.print("{x} {x} {x} {x} {x} {x} {x} {x} {s}\n", .{ m.entry, m.phys, m.size, m.text, m.data, m.textsz, m.datasz, m.bsssz, @as([*c]const u8, @ptrCast(&m.name)) });
}
