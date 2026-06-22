const std = @import("std");
const builtin = @import("builtin");

const c = @import("c").c;
const ffi = @import("ffi");
const device = ffi.device;
const hal = ffi.hal;
const irq = ffi.irq;
const kern = ffi.kern;
const page = ffi.page;
const task = ffi.task;
const timer = ffi.timer;
const kutil = ffi.kutil;
const lib = ffi.lib;

const sched = ffi.sched;
const thread = ffi.thread;
const vm = ffi.vm;
const smp = ffi.smp;

// Helper for curthread/curtask


// Helper to validate user-space address bounds

// Declarations of extern C helpers for target macros
extern fn wrap_get_hostname() callconv(.c) [*c]const u8;
extern fn wrap_get_version() callconv(.c) [*c]const u8;
extern fn wrap_get_machine() callconv(.c) [*c]const u8;
extern fn wrap_get_build_date() callconv(.c) [*c]const u8;

var infobuf: [hal.MAXINFOSZ]u8 align(16) = undefined;
var kerninfo_inited: bool = false;
var kerninfo: c.struct_kerninfo = undefined;

fn init_kerninfo() void {
    if (kerninfo_inited) return;
    _ = lib.memset(&kerninfo, 0, @sizeOf(c.struct_kerninfo));
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

    switch (sysinfo_type) {
        hal.INFO_KERNEL => {
            init_kerninfo();
            _ = lib.memcpy(buf, &kerninfo, @sizeOf(c.struct_kerninfo));
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

    sched.unlock();
    return error_val;
}

/// System call to get system information.
pub fn sysInfo(sysinfo_type: c_int, buf: ?*anyopaque) callconv(.c) c_int {
    var error_val: c_int = 0;
    var bufsz: usize = 0;

    if (buf == null or !kutil.user_area(buf))
        return kern.Errno.EFAULT;

    sched.lock();

    switch (sysinfo_type) {
        hal.INFO_KERNEL => {
            bufsz = @sizeOf(c.struct_kerninfo);
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
            sched.unlock();
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

    sched.unlock();
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
comptime {
    if (@import("root") == @This()) {
        @export(&sysinfo, .{ .name = "sysinfo", .linkage = .strong });
        @export(&sysInfo, .{ .name = "sys_info", .linkage = .strong });
        @export(&sysLog, .{ .name = "sys_log", .linkage = .strong });
        @export(&sysDebug, .{ .name = "sys_debug", .linkage = .strong });
        @export(&sysPanic, .{ .name = "sys_panic", .linkage = .strong });
        @export(&sysTime, .{ .name = "sys_time", .linkage = .strong });
        @export(&sysNosys, .{ .name = "sys_nosys", .linkage = .strong });
    }
}
