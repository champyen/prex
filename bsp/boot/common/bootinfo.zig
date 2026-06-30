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
// Replaces common/bootinfo.c. Provides:
//   - bootinfo: pointer to the bootinfo structure in the SYSPAGE area
//     (initialized to kvtop(BOOTINFO) before main()).
//   - dump_bootinfo: DEBUG-only function that prints the bootinfo contents.
//
// The C version declares `struct bootinfo* const bootinfo = (struct bootinfo*)kvtop(BOOTINFO);`
// as a global variable with a load-time initializer. We replicate this in
// Zig with an init function called from main() before any other work.
//
// Namespace convention (see zig_boot_plan.md §4a "no raw c.* in domain
// code" rule): this file uses ONLY `ffi.mem.*`, `ffi.boot.*`, and `ffi.cfg.*`
// types. No `c.*` is referenced in this file.

const ffi = @import("ffi");

// bootinfo: pointer to the bootinfo structure in the SYSPAGE BSS.
// This must live in BSS so it can be initialized at startup. It is exported
// as a C symbol so the rest of the C-side bootloader (startup.c, main.c,
// load.c) can reference it.
pub var bootinfo: [*c]ffi.mem.BootInfo = undefined;

comptime {
    @export(&bootinfo, .{ .name = "bootinfo", .linkage = .strong });
}

export fn __boot_bootinfo_init() callconv(.c) void {
    // kvtop(BOOTINFO) — convert virtual BOOTINFO address to physical.
    // KERNOFFSET is the per-arch offset; KERNOFFSET=0 means 1:1 mapping.
    bootinfo = @ptrFromInt(ffi.cfg.BOOTINFO -% ffi.cfg.KERNOFFSET);
}

// Memory region type strings for dump_bootinfo.
const memtype: [5][*:0]const u8 = .{
    "",                        // index 0 unused
    "USABLE",
    "MEMHOLE",
    "RESERVED",
    "BOOTDISK",
};

comptime {
    if (ffi.cfg.DEBUG) {
        @export(&dumpBootinfo, .{ .name = "dump_bootinfo", .linkage = .strong });
    } else {
        @export(&dumpBootinfoNoop, .{ .name = "dump_bootinfo", .linkage = .strong });
    }
}

fn dumpBootinfo() callconv(.c) void {
    // Use the pointer directly to avoid copying the 1KB bootinfo struct
    // onto the stack (which would emit a __aeabi_memcpy4 call).
    const bi: [*]const ffi.mem.BootInfo = bootinfo;

    debugPrint("[Boot information]\n");

    debugPrint("nr_rams=");
    debugPrintNum(@intCast(bi[0].nr_rams), 10);
    debugPrint("\n");

    var i: c_int = 0;
    while (i < bi[0].nr_rams) : (i += 1) {
        const idx: usize = @intCast(i);
        const ram_entry = &bi[0].ram[idx];
        if (ram_entry.type != 0) {
            debugPrint("ram[");
            debugPrintNum(idx, 10);
            debugPrint("]:  base=");
            debugPrintNum(@intCast(ram_entry.base), 16);
            debugPrint(" size=");
            debugPrintNum(@intCast(ram_entry.size), 16);
            debugPrint(" type=");
            const t = ram_entry.type;
            if (t >= 0 and t < 5) {
                debugPrint(memtype[@intCast(t)]);
            }
            debugPrint("\n");
        }
    }

    debugPrint("bootdisk: base=");
    debugPrintNum(@intCast(bi[0].bootdisk.base), 16);
    debugPrint(" size=");
    debugPrintNum(@intCast(bi[0].bootdisk.size), 16);
    debugPrint("\n");

    debugPrint("entry    phys     size     text     data     textsz   datasz   bsssz    module\n");
    debugPrint("-------- -------- -------- -------- -------- -------- -------- -------- ------\n");
    printModule(&bi[0].kernel);
    printModule(&bi[0].driver);

    var m: [*]ffi.mem.Module = @ptrCast(@constCast(&bi[0].tasks[0]));
    i = 0;
    while (i < bi[0].nr_tasks) : (i += 1) {
        printTaskModule(m);
        m += 1;
    }
}

fn dumpBootinfoNoop() callconv(.c) void {}

fn printModule(m: *const ffi.mem.Module) void {
    debugPrintNum(@intCast(m.entry), 16);
    debugPrint(" ");
    debugPrintNum(@intCast(m.phys), 16);
    debugPrint(" ");
    debugPrintNum(@intCast(m.size), 16);
    debugPrint(" ");
    debugPrintNum(@intCast(m.text), 16);
    debugPrint(" ");
    debugPrintNum(@intCast(m.data), 16);
    debugPrint(" ");
    debugPrintNum(@intCast(m.textsz), 16);
    debugPrint(" ");
    debugPrintNum(@intCast(m.datasz), 16);
    debugPrint(" ");
    debugPrintNum(@intCast(m.bsssz), 16);
    debugPrint(" ");
    printName(@as([*:0]const u8, @ptrCast(&m.name)));
    debugPrint("\n");
}

// Inline version for many-pointer iteration (avoids the [*]→* ptrCast
// that triggers __aeabi_memcpy4 generation in Thumb).
fn printTaskModule(m: [*]ffi.mem.Module) void {
    // Manually copy fields to avoid Zig emitting a memcpy for the cast.
    const e: c_ulong = m[0].entry;
    const p: c_ulong = m[0].phys;
    const sz: c_ulong = m[0].size;
    const t: c_ulong = m[0].text;
    const d: c_ulong = m[0].data;
    const tsz: c_ulong = m[0].textsz;
    const dsz: c_ulong = m[0].datasz;
    const bsz: c_ulong = m[0].bsssz;
    const nm_arr: *const [16]u8 = &m[0].name;
    debugPrintNum(@intCast(e), 16);
    debugPrint(" ");
    debugPrintNum(@intCast(p), 16);
    debugPrint(" ");
    debugPrintNum(@intCast(sz), 16);
    debugPrint(" ");
    debugPrintNum(@intCast(t), 16);
    debugPrint(" ");
    debugPrintNum(@intCast(d), 16);
    debugPrint(" ");
    debugPrintNum(@intCast(tsz), 16);
    debugPrint(" ");
    debugPrintNum(@intCast(dsz), 16);
    debugPrint(" ");
    debugPrintNum(@intCast(bsz), 16);
    debugPrint(" ");
    printName(@as([*:0]const u8, @ptrCast(nm_arr)));
    debugPrint("\n");
}

fn printName(name: [*:0]const u8) void {
    var i: usize = 0;
    while (i < 16 and name[i] != 0) : (i += 1) {
        debugPrintChar(name[i]);
    }
}

// Local debug helpers — call debug_putc via the ffi.boot interface.
fn debugPrint(s: [*:0]const u8) void {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {
        debugPrintChar(s[i]);
    }
}

fn debugPrintChar(ch: u8) void {
    if (ch == '\n') {
        ffi.boot.debug_putc(@as(c_int, '\r'));
    }
    ffi.boot.debug_putc(@as(c_int, ch));
}

fn debugPrintNum(value: c_ulong, base: u8) void {
    if (value == 0) {
        debugPrintChar('0');
        return;
    }
    var buf: [16]u8 = undefined;
    var i: usize = 0;
    var v = value;
    while (v > 0) {
        const d = v % base;
        buf[i] = if (d < 10) ('0' + @as(u8, @intCast(d))) else ('a' + @as(u8, @intCast(d - 10)));
        i += 1;
        v /= base;
    }
    while (i > 0) {
        i -= 1;
        debugPrintChar(buf[i]);
    }
}
