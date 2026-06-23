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
const ffi = @import("ffi");
const hal = ffi.hal;
const kern = ffi.kern;
const lib = ffi.lib;

const c = @import("c").c;

const sched = ffi.sched;
const kmem = ffi.kmem;
const thread = ffi.thread;
const sync = ffi.sync;

var IST_NONE: ?*const fn (?*anyopaque) callconv(.c) void = undefined;

var irq_table = std.mem.zeroes([hal.MAXIRQS]?*kern.IRQ);

inline fn ISTPRI(pri: c_int) c_int {
    return hal.PRI_IST + (hal.IPL_HIGH - pri);
}

fn irq_thread(arg: ?*anyopaque) callconv(.c) void {
    const irq: *kern.IRQ = @ptrCast(@alignCast(arg.?));
    const fn_ptr = irq.ist;
    const data = irq.data;

    _ = hal.splhigh();

    while (true) {
        if (irq.istreq <= 0) {
            _ = sched.tsleep(&irq.istevt, 0);
        }
        irq.istreq -= 1;
        std.debug.assert(irq.istreq >= 0);

        _ = hal.spl0();
        fn_ptr.?(data);
        _ = hal.splhigh();
    }
}

pub fn attach(vector: c_int, pri: c_int, shared: c_int, isr: ?*const fn (?*anyopaque) callconv(.c) c_int, ist: ?*const fn (?*anyopaque) callconv(.c) void, data: ?*anyopaque) callconv(.c) ?*kern.IRQ {
    std.debug.assert(isr != null);

    sched.lock();
    defer sched.unlock();

    const irq_mem = kmem.alloc(@sizeOf(kern.IRQ)) orelse @panic("irq_attach");
    const irq: *kern.IRQ = @ptrCast(@alignCast(irq_mem));
    errdefer kmem.free(irq);

    _ = lib.memset(irq, 0, @sizeOf(kern.IRQ));
    irq.vector = vector;
    irq.priority = pri;
    irq.isr = isr;
    irq.ist = ist;
    irq.data = data;

    if (ist != IST_NONE) {
        irq.thread = thread.kcreate(irq_thread, irq, ISTPRI(pri)) orelse @panic("irq_attach");
        sync.event_init(@as(?*anyopaque, @ptrCast(&irq.istevt)), "interrupt");
    }
    irq_table[@intCast(vector)] = irq;
    const mode: c_int = if (shared != 0) hal.IMODE_LEVEL else hal.IMODE_EDGE;
    hal.interrupt_setup(vector, mode);
    hal.interrupt_unmask(vector, pri);

    return irq;
}

pub fn detach(irq: ?*kern.IRQ) callconv(.c) void {
    std.debug.assert(irq != null);
    std.debug.assert(irq.?.vector < hal.MAXIRQS);

    hal.interrupt_mask(irq.?.vector);
    irq_table[@intCast(irq.?.vector)] = null;
    if (irq.?.thread != null) {
        _ = thread.kterminate(irq.?.thread);
    }

    kmem.free(irq);
}

pub fn handler(vector: c_int) callconv(.c) void {
    const irq = irq_table[@intCast(vector)] orelse {
        return;
    };
    std.debug.assert(irq.isr != null);

    irq.count +%= 1;

    const rc = irq.isr.?(irq.data);

    if (rc == hal.INT_CONTINUE) {
        std.debug.assert(irq.ist != IST_NONE);
        irq.istreq += 1;
        sched.wakeup(&irq.istevt);
        std.debug.assert(irq.istreq != 0);
    }
}

pub fn info(irq_info_ptr: ?*hal.IrqInfo) callconv(.c) c_int {
    var vec = irq_info_ptr.?.cookie;

    while (vec < hal.MAXIRQS) {
        if (irq_table[@intCast(vec)] != null) {
            break;
        }
        vec += 1;
    }
    if (vec >= hal.MAXIRQS) {
        return kern.Errno.ESRCH;
    }

    const irq = irq_table[@intCast(vec)].?;
    irq_info_ptr.?.vector = irq.vector;
    irq_info_ptr.?.count = irq.count;
    irq_info_ptr.?.priority = irq.priority;
    irq_info_ptr.?.istreq = irq.istreq;
    irq_info_ptr.?.thread = irq.thread;
    irq_info_ptr.?.cookie = vec + 1;
    return 0;
}

pub fn init() callconv(.c) void {
    @as(*usize, @ptrCast(&IST_NONE)).* = @as(usize, @bitCast(@as(isize, -1)));
    hal.interrupt_init();
    _ = hal.spl0();
}
