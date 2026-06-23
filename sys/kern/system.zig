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
const builtin = @import("builtin");

const c = @import("c").c;
const ffi = @import("ffi");
const device = ffi.device;
const hal = ffi.hal;
const irq = ffi.irq;
const kern = ffi.kern;
const kutil = ffi.kutil;
const lib = ffi.lib;
const page = ffi.page;
const sched = ffi.sched;
const task = ffi.task;
const thread = ffi.thread;
const timer = ffi.timer;
const vm = ffi.vm;

// Helper for curthread/curtask


// Helper to validate user-space address bounds

// Declarations of extern C helpers for target macros
extern fn wrap_get_hostname() callconv(.c) [*c]const u8;
extern fn wrap_get_version() callconv(.c) [*c]const u8;
extern fn wrap_get_machine() callconv(.c) [*c]const u8;
extern fn wrap_get_build_date() callconv(.c) [*c]const u8;

var infobuf: [hal.MAXINFOSZ]u8 align(16) = undefined;
var kerninfo_inited: bool = false;
var kerninfo: hal.KernInfo = undefined;

fn init_kerninfo() void {
    if (kerninfo_inited) return;
    _ = lib.memset(&kerninfo, 0, @sizeOf(hal.KernInfo));
    _ = lib.strlcpy(&kerninfo.sysname, "Prex+", @sizeOf(@TypeOf(kerninfo.sysname)));
    _ = lib.strlcpy(&kerninfo.nodename, wrap_get_hostname(), @sizeOf(@TypeOf(kerninfo.nodename)));
    _ = lib.strlcpy(&kerninfo.release, wrap_get_version(), @sizeOf(@TypeOf(kerninfo.release)));
    _ = lib.strlcpy(&kerninfo.version, wrap_get_build_date(), @sizeOf(@TypeOf(kerninfo.version)));
    _ = lib.strlcpy(&kerninfo.machine, wrap_get_machine(), @sizeOf(@TypeOf(kerninfo.machine)));
    kerninfo_inited = true;
}

const is_debug = @hasDecl(c, "DEBUG");

/// Get system information.
pub fn sysinfo(sysinfo_type: c_int, buf: ?*anyopaque) callconv(.c) c_int {
    var error_val: c_int = 0;

    sched.lock();
    defer sched.unlock();

    switch (sysinfo_type) {
        hal.INFO_KERNEL => {
            init_kerninfo();
            _ = lib.memcpy(buf, &kerninfo, @sizeOf(hal.KernInfo));
        },
        hal.INFO_MEMORY => {
            page.info(@ptrCast(@alignCast(buf)));
        },
        hal.INFO_TIMER => {
            timer.info(@ptrCast(@alignCast(buf)));
        },
        hal.INFO_THREAD => {
            error_val = thread.info(@ptrCast(@alignCast(buf)));
        },
        hal.INFO_DEVICE => {
            error_val = device.info(@ptrCast(@alignCast(buf)));
        },
        hal.INFO_TASK => {
            error_val = task.info(@ptrCast(@alignCast(buf)));
        },
        hal.INFO_VM => {
            error_val = vm.info(@ptrCast(@alignCast(buf)));
        },
        hal.INFO_IRQ => {
            error_val = irq.info(@ptrCast(@alignCast(buf)));
        },
        else => {
            error_val = kern.Errno.EINVAL;
        },
    }

    return error_val;
}

/// System call to get system information.
pub fn sysInfo(sysinfo_type: c_int, buf: ?*anyopaque) callconv(.c) c_int {
    var error_val: c_int = 0;
    var bufsz: usize = 0;

    if (buf == null or !kutil.user_area(buf))
        return kern.Errno.EFAULT;

    sched.lock();
    defer sched.unlock();

    switch (sysinfo_type) {
        hal.INFO_KERNEL => {
            bufsz = @sizeOf(hal.KernInfo);
        },
        hal.INFO_MEMORY => {
            bufsz = @sizeOf(hal.MemInfo);
        },
        hal.INFO_TIMER => {
            bufsz = @sizeOf(hal.TimerInfo);
        },
        hal.INFO_THREAD => {
            bufsz = @sizeOf(hal.ThreadInfo);
        },
        hal.INFO_DEVICE => {
            bufsz = @sizeOf(hal.DeviceInfo);
        },
        hal.INFO_TASK => {
            bufsz = @sizeOf(hal.TaskInfo);
        },
        hal.INFO_VM => {
            bufsz = @sizeOf(hal.VmInfo);
        },
        hal.INFO_IRQ => {
            bufsz = @sizeOf(hal.IrqInfo);
        },
        else => {
            return kern.Errno.EINVAL;
        },
    }

    error_val = hal.copyin(buf, &infobuf, bufsz);
    if (error_val == 0) {
        error_val = sysinfo(sysinfo_type, &infobuf);
        if (error_val == 0) {
            error_val = hal.copyout(&infobuf, buf, bufsz);
        }
    }

    return error_val;
}

/// Logging system call.
pub fn sysLog(str: [*c]const u8) callconv(.c) c_int {
    if (comptime !is_debug) {
        return kern.Errno.ENOSYS;
    } else {
        var buf: [hal.DBGMSGSZ]u8 = undefined;
        if (hal.copyinstr(str, &buf, hal.DBGMSGSZ) != 0) {
            return kern.Errno.EINVAL;
        }
        lib.printf("%s", &buf);
        return 0;
    }
}

/// Kernel debug service.
pub fn sysDebug(cmd: c_int, data: ?*anyopaque) callconv(.c) c_int {
    if (comptime !is_debug) {
        return kern.Errno.ENOSYS;
    } else {
        var error_val: c_int = kern.Errno.EINVAL;
        var task_ref: kern.TaskRef = null;

        switch (cmd) {
            hal.DBGC_LOGSIZE, hal.DBGC_GETLOG, hal.DBGC_SAVEBT => {
                error_val = hal.dbgctl(cmd, data);
            },
            hal.DBGC_TRACE => {
                task_ref = @ptrCast(@alignCast(data));
                if (task.valid(task_ref) == 0) {
                    error_val = kern.Errno.ESRCH;
                } else {
                    _ = hal.dbgctl(cmd, task_ref);
                    error_val = 0;
                }
            },
            hal.DBGC_FLUSHCACHE => {
                if (@hasDecl(c, "CONFIG_CACHE")) {
                    hal.flush_cache();
                }
                error_val = 0;
            },
            else => {},
        }
        return error_val;
    }
}

/// Panic system call.
pub fn sysPanic(str: [*c]const u8) callconv(.c) c_int {
    if (comptime is_debug) {
        var buf: [hal.DBGMSGSZ]u8 = undefined;
        sched.lock();
        _ = hal.copyinstr(str, &buf, hal.DBGMSGSZ - 20);
        lib.printf("User panic: %s\n", &buf);
        const cur_task = kutil.get_curtask();
        const cur_thread = kutil.get_curthread();
        const name_ptr: [*c]const u8 = if (cur_task) |t| @ptrCast(&t.name) else "unknown";
        lib.printf(" task=%s thread=%lx\n", name_ptr, @intFromPtr(cur_thread));
        hal.dump_backtrace();
        hal.machine_abort();
    } else {
        if (kutil.get_curtask()) |t| {
            _ = task.terminate(t);
        }
    }
    return 0;
}

/// Get system time - return ticks since OS boot.
pub fn sysTime(ticks: ?*c_ulong) callconv(.c) c_int {
    const t = timer.ticks();
    return hal.copyout(&t, ticks, @sizeOf(c_ulong));
}

/// nonexistent system call.
pub fn sysNosys() callconv(.c) c_int {
    return kern.Errno.EINVAL;
}

// Comptime exports – public API functions with strong C linkage
