const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});

// Helper for curthread/curtask
inline fn get_curthread() ?*c.struct_thread {
    if (comptime @hasDecl(c, "CONFIG_SMP")) {
        return @ptrCast(hal_get_cpu_control().?.active_thread);
    } else {
        const env = struct {
            extern var curthread: c.thread_t;
        };
        return @ptrCast(env.curthread);
    }
}

inline fn get_curtask() ?*c.struct_task {
    if (get_curthread()) |curr| {
        return @ptrCast(curr.task);
    }
    return null;
}

extern fn hal_get_cpu_control() callconv(.c) ?*c.struct_cpu_control;

// Helper to validate user-space address bounds
inline fn user_area(a: ?*const anyopaque) bool {
    if (a == null) return false;
    if (@hasDecl(c, "CONFIG_MMU")) {
        return @intFromPtr(a) < c.USERLIMIT;
    } else {
        return true;
    }
}

// Declarations of extern C helpers for target macros
extern fn wrap_get_hostname() callconv(.c) [*c]const u8;
extern fn wrap_get_version() callconv(.c) [*c]const u8;
extern fn wrap_get_machine() callconv(.c) [*c]const u8;
extern fn wrap_get_build_date() callconv(.c) [*c]const u8;

var infobuf: [c.MAXINFOSZ]u8 align(16) = undefined;
var kerninfo_inited: bool = false;
var kerninfo: c.struct_kerninfo = undefined;

fn init_kerninfo() void {
    if (kerninfo_inited) return;
    _ = c.memset(&kerninfo, 0, @sizeOf(c.struct_kerninfo));
    _ = c.strlcpy(&kerninfo.sysname, "Prex+", @sizeOf(@TypeOf(kerninfo.sysname)));
    _ = c.strlcpy(&kerninfo.nodename, wrap_get_hostname(), @sizeOf(@TypeOf(kerninfo.nodename)));
    _ = c.strlcpy(&kerninfo.release, wrap_get_version(), @sizeOf(@TypeOf(kerninfo.release)));
    _ = c.strlcpy(&kerninfo.version, wrap_get_build_date(), @sizeOf(@TypeOf(kerninfo.version)));
    _ = c.strlcpy(&kerninfo.machine, wrap_get_machine(), @sizeOf(@TypeOf(kerninfo.machine)));
    kerninfo_inited = true;
}

const is_debug = @hasDecl(c, "DEBUG");

/// Get system information.
pub fn sysinfo(sysinfo_type: c_int, buf: ?*anyopaque) callconv(.c) c_int {
    var error_val: c_int = 0;

    c.sched_lock();

    switch (sysinfo_type) {
        c.INFO_KERNEL => {
            init_kerninfo();
            _ = c.memcpy(buf, &kerninfo, @sizeOf(c.struct_kerninfo));
        },
        c.INFO_MEMORY => {
            c.page_info(@ptrCast(@alignCast(buf)));
        },
        c.INFO_TIMER => {
            c.timer_info(@ptrCast(@alignCast(buf)));
        },
        c.INFO_THREAD => {
            error_val = c.thread_info(@ptrCast(@alignCast(buf)));
        },
        c.INFO_DEVICE => {
            error_val = c.device_info(@ptrCast(@alignCast(buf)));
        },
        c.INFO_TASK => {
            error_val = c.task_info(@ptrCast(@alignCast(buf)));
        },
        c.INFO_VM => {
            error_val = c.vm_info(@ptrCast(@alignCast(buf)));
        },
        c.INFO_IRQ => {
            error_val = c.irq_info(@ptrCast(@alignCast(buf)));
        },
        else => {
            error_val = c.EINVAL;
        },
    }

    c.sched_unlock();
    return error_val;
}

/// System call to get system information.
pub fn sys_info(sysinfo_type: c_int, buf: ?*anyopaque) callconv(.c) c_int {
    var error_val: c_int = 0;
    var bufsz: usize = 0;

    if (buf == null or !user_area(buf))
        return c.EFAULT;

    c.sched_lock();

    switch (sysinfo_type) {
        c.INFO_KERNEL => {
            bufsz = @sizeOf(c.struct_kerninfo);
        },
        c.INFO_MEMORY => {
            bufsz = @sizeOf(c.struct_meminfo);
        },
        c.INFO_TIMER => {
            bufsz = @sizeOf(c.struct_timerinfo);
        },
        c.INFO_THREAD => {
            bufsz = @sizeOf(c.struct_threadinfo);
        },
        c.INFO_DEVICE => {
            bufsz = @sizeOf(c.struct_devinfo);
        },
        c.INFO_TASK => {
            bufsz = @sizeOf(c.struct_taskinfo);
        },
        c.INFO_VM => {
            bufsz = @sizeOf(c.struct_vminfo);
        },
        c.INFO_IRQ => {
            bufsz = @sizeOf(c.struct_irqinfo);
        },
        else => {
            c.sched_unlock();
            return c.EINVAL;
        },
    }

    error_val = c.copyin(buf, &infobuf, bufsz);
    if (error_val == 0) {
        error_val = sysinfo(sysinfo_type, &infobuf);
        if (error_val == 0) {
            error_val = c.copyout(&infobuf, buf, bufsz);
        }
    }

    c.sched_unlock();
    return error_val;
}

/// Logging system call.
pub fn sys_log(str: [*c]const u8) callconv(.c) c_int {
    if (comptime !is_debug) {
        return c.ENOSYS;
    } else {
        var buf: [c.DBGMSGSZ]u8 = undefined;
        if (c.copyinstr(str, &buf, c.DBGMSGSZ) != 0) {
            return c.EINVAL;
        }
        c.printf("%s", &buf);
        return 0;
    }
}

/// Kernel debug service.
pub fn sys_debug(cmd: c_int, data: ?*anyopaque) callconv(.c) c_int {
    if (comptime !is_debug) {
        return c.ENOSYS;
    } else {
        var error_val: c_int = c.EINVAL;
        var task: c.task_t = null;

        switch (cmd) {
            c.DBGC_LOGSIZE, c.DBGC_GETLOG, c.DBGC_SAVEBT => {
                error_val = c.dbgctl(cmd, data);
            },
            c.DBGC_TRACE => {
                task = @ptrCast(@alignCast(data));
                if (c.task_valid(task) == 0) {
                    error_val = c.ESRCH;
                } else {
                    _ = c.dbgctl(cmd, task);
                    error_val = 0;
                }
            },
            c.DBGC_FLUSHCACHE => {
                if (@hasDecl(c, "CONFIG_CACHE")) {
                    c.flush_cache();
                }
                error_val = 0;
            },
            else => {},
        }
        return error_val;
    }
}

/// Panic system call.
pub fn sys_panic(str: [*c]const u8) callconv(.c) c_int {
    if (comptime is_debug) {
        var buf: [c.DBGMSGSZ]u8 = undefined;
        c.sched_lock();
        _ = c.copyinstr(str, &buf, c.DBGMSGSZ - 20);
        c.printf("User panic: %s\n", &buf);
        const cur_task = get_curtask();
        const cur_thread = get_curthread();
        const name_ptr: [*c]const u8 = if (cur_task) |t| @ptrCast(&t.name) else "unknown";
        c.printf(" task=%s thread=%lx\n", name_ptr, @intFromPtr(cur_thread));
        c.dump_backtrace();
        c.machine_abort();
    } else {
        if (get_curtask()) |t| {
            _ = c.task_terminate(t);
        }
    }
    return 0;
}

/// Get system time - return ticks since OS boot.
pub fn sys_time(ticks: ?*c_ulong) callconv(.c) c_int {
    const t = c.timer_ticks();
    return c.copyout(&t, ticks, @sizeOf(c_ulong));
}

/// nonexistent system call.
pub fn sys_nosys() callconv(.c) c_int {
    return c.EINVAL;
}

// Comptime exports – public API functions with strong C linkage
comptime {
    @export(&sysinfo, .{ .name = "sysinfo", .linkage = .strong });
    @export(&sys_info, .{ .name = "sys_info", .linkage = .strong });
    @export(&sys_log, .{ .name = "sys_log", .linkage = .strong });
    @export(&sys_debug, .{ .name = "sys_debug", .linkage = .strong });
    @export(&sys_panic, .{ .name = "sys_panic", .linkage = .strong });
    @export(&sys_time, .{ .name = "sys_time", .linkage = .strong });
    @export(&sys_nosys, .{ .name = "sys_nosys", .linkage = .strong });
}
