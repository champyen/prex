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

const std = @import("std");
const dki = @import("dki");
const c = dki.c;

// VirtIO Block Request Types
const VIO_BLK_T_IN = 0;
const VIO_BLK_T_OUT = 1;
const VIO_BLK_T_FLUSH = 4;

// VirtIO Block Status
const VIO_BLK_S_OK = 0;
const VIO_BLK_S_IOERR = 1;
const VIO_BLK_S_UNSUPP = 2;

// VirtIO Device Status
const VIO_STATUS_ACKNOWLEDGE = 1;
const VIO_STATUS_DRIVER = 2;
const VIO_STATUS_DRIVER_OK = 4;
const VIO_STATUS_FEATURES_OK = 8;

// VirtQueue Descriptor Flags
const VRING_DESC_F_NEXT = 1;
const VRING_DESC_F_WRITE = 2;
const VRING_DESC_F_INDIRECT = 4;

const VringDesc = extern struct {
    addr: u64,
    len: u32,
    flags: u16,
    next: u16,
};

const VringAvail = extern struct {
    flags: u16,
    idx: u16,
    ring: [16]u16,
};

const VringUsedElem = extern struct {
    id: u32,
    len: u32,
};

const VringUsed = extern struct {
    flags: u16,
    idx: u16,
    ring: [16]VringUsedElem,
};

const VioBlkReq = extern struct {
    type: u32,
    reserved: u32,
    sector: u64,
};

const VQ_SIZE = 16;
const BSIZE = 512;
const MAX_PARTI = 4;

const VioBlkSoftc = extern struct {
    dev: c.device_t,
    base: usize,
    irq: c_int,
    irq_handle: c.irq_t,
    done_event: c.struct_event,
    lock_event: c.struct_event,

    avail: *volatile VringAvail,
    used: *volatile VringUsed,
    req: *VioBlkReq,
    status_ptr: *u8,
    parent_sc: ?*VioBlkSoftc,

    desc_ptr: [*]volatile VringDesc,
    desc_len: usize,

    start_sector: u32,
    nsectors: u32,

    last_used_idx: u32,
    busy: u32,
    
    mbr: [BSIZE]u8,
};

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    dki.panic(msg, error_return_trace, ret_addr);
}

export fn vio_blk_isr(arg: ?*anyopaque) callconv(.c) c_int {
    const sc: *VioBlkSoftc = @ptrCast(@alignCast(arg.?));
    const status = dki.bus_read_32(sc.base + c.VIO_MMIO_IRQ_STATUS);
    if (status != 0) {
        dki.bus_write_32(sc.base + c.VIO_MMIO_IRQ_ACK, status);
        return c.INT_CONTINUE;
    }
    return c.INT_DONE;
}

export fn vio_blk_ist(arg: ?*anyopaque) callconv(.c) void {
    const sc: *VioBlkSoftc = @ptrCast(@alignCast(arg.?));
    dki.sched_wakeup(&sc.done_event);
}

fn vio_blk_read(dev: c.device_t, buf: [*]c_char, nbyte: *usize, blkno: c_int) callconv(.c) c_int {
    const sc: *VioBlkSoftc = @ptrCast(@alignCast(dki.device_private(dev) orelse return c.ENODEV));
    const psc = sc.parent_sc orelse sc;

    if (sc.nsectors > 0 and blkno >= @as(c_int, @intCast(sc.nsectors)))
        return c.EIO;

    const kbuf = dki.kmem_map(buf, nbyte.*) catch return c.EFAULT;

    // Acquire device mutex
    dki.sched_lock();
    while (psc.busy != 0) {
        dki.sched_sleep(&psc.lock_event);
    }
    psc.busy = 1;
    dki.sched_unlock();

    // Ensure device is released no matter how we exit
    defer {
        dki.sched_lock();
        psc.busy = 0;
        dki.sched_wakeup(&psc.lock_event);
        dki.sched_unlock();
    }

    psc.status_ptr.* = 0xFF;
    psc.req.type = VIO_BLK_T_IN;
    psc.req.reserved = 0;
    psc.req.sector = @as(u64, @intCast(sc.start_sector)) + @as(u64, @intCast(blkno));

    psc.desc_ptr[0].addr = @as(u64, @intCast(dki.kvtop(psc.req)));
    psc.desc_ptr[0].len = @sizeOf(VioBlkReq);
    psc.desc_ptr[0].flags = VRING_DESC_F_NEXT;
    psc.desc_ptr[0].next = 1;

    psc.desc_ptr[1].addr = @as(u64, @intCast(dki.kvtop(kbuf)));
    psc.desc_ptr[1].len = @as(u32, @intCast(nbyte.*));
    psc.desc_ptr[1].flags = VRING_DESC_F_NEXT | VRING_DESC_F_WRITE;
    psc.desc_ptr[1].next = 2;

    psc.desc_ptr[2].addr = @as(u64, @intCast(dki.kvtop(psc.status_ptr)));
    psc.desc_ptr[2].len = 1;
    psc.desc_ptr[2].flags = VRING_DESC_F_WRITE;
    psc.desc_ptr[2].next = 0;

    psc.avail.ring[psc.avail.idx % 16] = 0;
    dki.memoryBarrier();
    psc.last_used_idx = psc.used.idx;
    psc.avail.idx +%= 1;
    dki.memoryBarrier();

    dki.bus_write_32(psc.base + c.VIO_MMIO_QUEUE_NOTIFY, 0);

    var timeout: u32 = 1000000;
    while (psc.used.idx == psc.last_used_idx) {
        if (timeout == 0) {
            dki.log("vio_block: timeout waiting for device {x}\n", .{psc.base});
            return c.ETIMEDOUT;
        }
        timeout -= 1;
        if (timeout > 999900) {
            dki.delay_usec(1);
        } else {
            dki.sched_sleep(&psc.done_event);
        }
        dki.memoryBarrier();
    }

    return if (psc.status_ptr.* == VIO_BLK_S_OK) 0 else c.EIO;
}

fn vio_blk_write(dev: c.device_t, buf: [*]const c_char, nbyte: *usize, blkno: c_int) callconv(.c) c_int {
    const sc: *VioBlkSoftc = @ptrCast(@alignCast(dki.device_private(dev) orelse return c.ENODEV));
    const psc = sc.parent_sc orelse sc;

    if (sc.nsectors > 0 and blkno >= @as(c_int, @intCast(sc.nsectors)))
        return c.EIO;

    const kbuf = dki.kmem_map(@ptrCast(@constCast(buf)), nbyte.*) catch return c.EFAULT;

    dki.sched_lock();
    while (psc.busy != 0) {
        dki.sched_sleep(&psc.lock_event);
    }
    psc.busy = 1;
    dki.sched_unlock();

    defer {
        dki.sched_lock();
        psc.busy = 0;
        dki.sched_wakeup(&psc.lock_event);
        dki.sched_unlock();
    }

    psc.status_ptr.* = 0xFF;
    psc.req.type = VIO_BLK_T_OUT;
    psc.req.reserved = 0;
    psc.req.sector = @as(u64, @intCast(sc.start_sector)) + @as(u64, @intCast(blkno));

    psc.desc_ptr[0].addr = @as(u64, @intCast(dki.kvtop(psc.req)));
    psc.desc_ptr[0].len = @sizeOf(VioBlkReq);
    psc.desc_ptr[0].flags = VRING_DESC_F_NEXT;
    psc.desc_ptr[0].next = 1;

    psc.desc_ptr[1].addr = @as(u64, @intCast(dki.kvtop(kbuf)));
    psc.desc_ptr[1].len = @as(u32, @intCast(nbyte.*));
    psc.desc_ptr[1].flags = VRING_DESC_F_NEXT;
    psc.desc_ptr[1].next = 2;

    psc.desc_ptr[2].addr = @as(u64, @intCast(dki.kvtop(psc.status_ptr)));
    psc.desc_ptr[2].len = 1;
    psc.desc_ptr[2].flags = VRING_DESC_F_WRITE;
    psc.desc_ptr[2].next = 0;

    psc.avail.ring[psc.avail.idx % 16] = 0;
    dki.memoryBarrier();
    psc.last_used_idx = psc.used.idx;
    psc.avail.idx +%= 1;
    dki.memoryBarrier();

    dki.bus_write_32(psc.base + c.VIO_MMIO_QUEUE_NOTIFY, 0);

    var timeout: u32 = 1000000;
    while (psc.used.idx == psc.last_used_idx) {
        if (timeout == 0) {
            dki.log("vio_block: timeout waiting for device {x}\n", .{psc.base});
            return c.ETIMEDOUT;
        }
        timeout -= 1;
        if (timeout > 999900) {
            dki.delay_usec(1);
        } else {
            dki.sched_sleep(&psc.done_event);
        }
        dki.memoryBarrier();
    }

    return if (psc.status_ptr.* == VIO_BLK_S_OK) 0 else c.EIO;
}

const Interface = struct {
    pub fn open(_: c.device_t, _: c_int) callconv(.c) c_int {
        return 0;
    }

    pub fn close(_: c.device_t) callconv(.c) c_int {
        return 0;
    }

    pub fn read(dev: c.device_t, buf: [*]c_char, nbyte: *usize, blkno: c_int) callconv(.c) c_int {
        return vio_blk_read(dev, buf, nbyte, blkno);
    }

    pub fn write(dev: c.device_t, buf: [*]const c_char, nbyte: *usize, blkno: c_int) callconv(.c) c_int {
        return vio_blk_write(dev, buf, nbyte, blkno);
    }
};

export var vio_blk_devops = dki.DevOps{
    .open = null,
    .close = null,
    .read = null,
    .write = null,
};

export var vio_block_driver = dki.Driver{
    .name = "vio_block",
    .devops = &vio_blk_devops,
    .devsz = @sizeOf(VioBlkSoftc),
    .flags = 0,
    .probe = null,
    .init = vio_block_init,
};

export fn vio_block_init(_: ?*dki.Driver) callconv(.c) c_int {
    vio_blk_devops = dki.wrap(dki.DevOps, Interface);
    return 0;
}

fn attach_partition(parent_sc: *VioBlkSoftc, name: [*:0]const u8, start: u32, size: u32) void {
    const dev = dki.device_create(&vio_block_driver, name, c.D_BLK | c.D_PROT) catch |err| {
        dki.log("Failed to create device {s}: {}\n", .{ name, err });
        return;
    };
    const sc: *VioBlkSoftc = @ptrCast(@alignCast(dki.device_private(dev).?));

    sc.dev = dev;
    sc.base = parent_sc.base;
    sc.irq = parent_sc.irq;
    sc.irq_handle = parent_sc.irq_handle;
    sc.start_sector = start;
    sc.nsectors = size;
    sc.parent_sc = parent_sc;

    dki.log("VirtIO Block partition {s}: start {}, size {}\n", .{ name, start, size });
}

var unit: i32 = 0;

/// Helper to read a little-endian u32 from a potentially unaligned byte buffer.
noinline fn readU32Le(buf: []const u8) u32 {
    var val: u32 = 0;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        const b: u8 = buf[i];
        val |= @as(u32, b) << @as(u5, @intCast(i * 8));
        asm volatile ("" : : [b] "r" (b) : .{ .memory = true });
    }
    return val;
}

export fn vio_block_attach(base: usize, irq: c_int) callconv(.c) c_int {
    const u = unit;
    unit += 1;
    
    var name_buf = [16]u8{ 'v', 'd', '0', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    if (u < 10) name_buf[2] = @as(u8, @intCast('0' + u));

    const dev = dki.device_create(&vio_block_driver, @ptrCast(&name_buf), c.D_BLK | c.D_PROT) catch |err| return dki.toCError(err);
    const sc: *VioBlkSoftc = @ptrCast(@alignCast(dki.device_private(dev).?));

    sc.dev = dev;
    sc.base = base;
    sc.irq = irq;
    sc.last_used_idx = 0;
    sc.start_sector = 0;
    sc.nsectors = 0;
    sc.parent_sc = null;
    sc.busy = 0;

    dki.event_init(&sc.done_event, "vio_blk");
    dki.event_init(&sc.lock_event, "vio_lock");

    dki.bus_write_32(base + c.VIO_MMIO_STATUS, 0);

    var status: u32 = VIO_STATUS_ACKNOWLEDGE | VIO_STATUS_DRIVER;
    dki.bus_write_32(base + c.VIO_MMIO_STATUS, status);
    dki.bus_write_32(base + c.VIO_MMIO_DRV_FEATURE, 0);
    dki.bus_write_32(base + c.VIO_MMIO_PAGE_SIZE, 4096);

    dki.bus_write_32(base + c.VIO_MMIO_QUEUE_SEL, 0);
    const q_max = dki.bus_read_32(base + c.VIO_MMIO_QUEUE_NUM_MAX);
    if (q_max < VQ_SIZE) {
        dki.log("VirtQueue size too small: {}\n", .{q_max});
        return -1;
    }

    const raw_pa = dki.page_alloc(8192 + 4096);
    if (raw_pa == 0) {
        dki.log("Failed to allocate VQ memory\n", .{});
        return -1;
    }
    const vq_pa = (raw_pa + 4095) & ~@as(usize, 4095);
    const vq_mem = dki.ptokv(vq_pa);
    @memset(vq_mem[0..8192], 0);

    sc.desc_ptr = @as([*]volatile VringDesc, @ptrCast(@alignCast(vq_mem)));
    sc.desc_len = VQ_SIZE;
    sc.avail = @ptrCast(@alignCast(vq_mem + VQ_SIZE * @sizeOf(VringDesc)));
    sc.used = @ptrCast(@alignCast(vq_mem + 4096));

    dki.bus_write_32(base + c.VIO_MMIO_QUEUE_SIZE, VQ_SIZE);
    dki.bus_write_32(base + c.VIO_MMIO_QUEUE_ALIGN, 4096);
    dki.bus_write_32(base + c.VIO_MMIO_QUEUE_PFN, @as(u32, @intCast(vq_pa >> 12)));

    status |= VIO_STATUS_DRIVER_OK;
    dki.bus_write_32(base + c.VIO_MMIO_STATUS, status);

    sc.irq_handle = dki.irq_attach(irq, c.IPL_BLOCK, 1, vio_blk_isr, vio_blk_ist, sc) catch |err| return dki.toCError(err);

    sc.req = dki.allocator.create(VioBlkReq) catch return c.ENOMEM;
    sc.status_ptr = dki.allocator.create(u8) catch return c.ENOMEM;

    dki.log("VirtIO Block initialized at 0x{x}, irq {} as vd{}\n", .{ base, irq, u });

    const cap_low = dki.bus_read_32(base + c.VIO_MMIO_CFG);
    sc.nsectors = cap_low;

    var count: usize = BSIZE;
    if (vio_blk_read(dev, @ptrCast(&sc.mbr), &count, 0) == 0) {
        if (sc.mbr[510] == 0x55 and sc.mbr[511] == 0xaa) {
            var found = false;
            var i: u32 = 0;
            while (i < MAX_PARTI) : (i += 1) {
                const off = 446 + i * 16;
                const pstart = readU32Le(sc.mbr[off + 8 .. off + 12]);
                const psize = readU32Le(sc.mbr[off + 12 .. off + 16]);
                
                if (psize > 0) {
                    var pname_buf = [16]u8{ 'v', 'd', '0', 'p', '0', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
                    pname_buf[2] = @as(u8, @intCast('0' + u));
                    pname_buf[4] = @as(u8, @intCast('1' + i));
                    attach_partition(sc, @ptrCast(&pname_buf), pstart, psize);
                    found = true;
                }
            }
            if (found) return 0;
        }
        dki.log("No partition found on vd{}, using whole disk as p1\n", .{ u });
        var pname_buf = [16]u8{ 'v', 'd', '0', 'p', '1', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
        pname_buf[2] = @as(u8, @intCast('0' + u));
        attach_partition(sc, @ptrCast(&pname_buf), 0, sc.nsectors);
    }

    return 0;
}
