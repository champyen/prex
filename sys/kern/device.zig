const std = @import("std");

const c = @import("c").c;

const ffi = @import("ffi");
const exception = ffi.exception;
const hal = ffi.hal;
const kern = ffi.kern;
const sched = ffi.sched;
const task = ffi.task;
const timer = ffi.timer;
const kutil = ffi.kutil;
const lib = ffi.lib;
const kmem = ffi.kmem;

// ---------------------------------------------------------------------------
// device_list: head of the linked list of all device objects
// ---------------------------------------------------------------------------
var device_list: ?*kern.Device = null;

// ---------------------------------------------------------------------------
// user_area – Stage 2 safety check for user-space pointer validation
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Helper functions – local implementations with C calling convention
// These are referenced by the dkient table via pointer mapping.
// ---------------------------------------------------------------------------

/// create – create a new device object.
/// Returns device pointer on success, null on failure.
fn create(drv: ?*hal.Driver, name: [*c]const u8, flags: c_int) callconv(.c) ?*kern.Device {
    var len: usize = 0;
    var priv: ?*anyopaque = null;

    sched.lock();
    defer sched.unlock();

    // Check the length of the name.
    len = lib.strnlen(name, hal.MAXDEVNAME);
    if (len == 0 or len >= hal.MAXDEVNAME) {
        return null;
    }

    // Check if the specified name is already used.
    if (lookup(name) != null) {
        lib.panic("duplicate device");
    }

    // Allocate a device structure.
    const dev_ptr: *kern.Device = @ptrCast(@alignCast(kmem.alloc(@sizeOf(kern.Device)) orelse @panic("create")));

    // Allocate driver private data if needed.
    if (drv != null and drv.?.devsz != 0) {
        priv = kmem.alloc(drv.?.devsz) orelse @panic("devsz");
        _ = lib.memset(priv, 0, drv.?.devsz);
    }

    _ = lib.strlcpy(@ptrCast(&dev_ptr.name), name, len + 1);
    dev_ptr.driver = drv;
    dev_ptr.flags = flags;
    dev_ptr.active = 1;
    dev_ptr.refcnt = 1;
    dev_ptr.@"private" = priv;
    dev_ptr.next = device_list;
    device_list = dev_ptr;

    return dev_ptr;
}

/// destroy – destroy a device object.
/// Returns 0 on success, ENODEV on failure.
fn destroy(dev: ?*kern.Device) callconv(.c) c_int {
    sched.lock();
    defer sched.unlock();
    if (valid(dev) == 0) {
        return kern.Errno.ENODEV;
    }
    dev.?.active = 0;
    release(dev);
    return 0;
}

/// lookup – look up a device object by name.
/// Returns device pointer if found, null otherwise.
fn lookup(name: [*c]const u8) callconv(.c) ?*kern.Device {
    var dev = device_list;
    while (dev) |d| : (dev = @ptrCast(d.next)) {
        if (lib.strncmp(&d.name, name, hal.MAXDEVNAME) == 0) {
            return d;
        }
    }
    return null;
}

/// valid – return true (1) if specified device is valid.
fn valid(dev: ?*kern.Device) callconv(.c) c_int {
    var tmp = device_list;
    while (tmp) |t| : (tmp = @ptrCast(t.next)) {
        if (t == dev) {
            if (dev) |d| {
                if (d.active != 0) return 1;
            }
            return 0;
        }
    }
    return 0;
}

/// reference – increment the reference count on an active device.
/// Returns 0 on success, ENODEV or EPERM on failure.
fn reference(dev: ?*kern.Device) callconv(.c) c_int {
    sched.lock();
    defer sched.unlock();
    if (valid(dev) == 0) {
        return kern.Errno.ENODEV;
    }
    if (task.capable(kern.CAP_RAWIO) == 0) {
        return kern.Errno.EPERM;
    }
    dev.?.refcnt += 1;
    return 0;
}

/// release – decrement the reference count; free when it reaches zero.
fn release(dev: ?*kern.Device) callconv(.c) void {
    sched.lock();
    defer sched.unlock();
    const dev_ptr = dev.?;
    dev_ptr.refcnt -= 1;
    if (dev_ptr.refcnt > 0) {
        return;
    }

    // Remove the device from the list.
    var tmp: *?*kern.Device = &device_list;
    while (tmp.*) |curr| {
        if (curr == dev_ptr) {
            tmp.* = @ptrCast(curr.next);
            break;
        }
        tmp = @ptrCast(&curr.next);
    }
    kmem.free(dev_ptr);
}

/// privateFn – return device's private data.
fn privateFn(dev: ?*kern.Device) callconv(.c) ?*anyopaque {
    if (dev == null) return null;
    return dev.?.@"private";
}

/// control – devctl from another device driver (internal).
fn control(dev: ?*kern.Device, cmd: c_ulong, arg: ?*anyopaque) callconv(.c) c_int {
    sched.lock();
    defer sched.unlock();
    const drv: ?*hal.Driver = if (dev) |d| d.driver else null;
    const ops: ?*c.struct_devops = if (drv) |dr| dr.devops else null;
    if (ops == null or ops.?.devctl == null) {
        return kern.Errno.EINVAL;
    }
    const err: c_int = ops.?.devctl.?(@ptrCast(dev), cmd, arg);
    return err;
}

/// broadcast – broadcast devctl command to all device objects.
fn broadcast(cmd: c_ulong, arg: ?*anyopaque, force: c_int) callconv(.c) c_int {
    var retval: c_int = 0;

    sched.lock();
    defer sched.unlock();

    var dev = device_list;
    while (dev) |d| : (dev = @ptrCast(d.next)) {
        const drv: ?*hal.Driver = d.driver;
        const ops: ?*c.struct_devops = if (drv) |dr| dr.devops else null;
        if (ops == null) continue;
        if (ops.?.devctl == null) continue;

        const err: c_int = ops.?.devctl.?(@as(?*c.struct_device, @ptrCast(d)), cmd, arg);
        if (err != 0) {
            if (force != 0) {
                retval = kern.Errno.EIO;
            } else {
                retval = err;
                break;
            }
        }
    }
    return retval;
}

// ---------------------------------------------------------------------------
// Public functions – exported with strong C linkage
// ---------------------------------------------------------------------------

/// open – open the specified device.
pub fn open(name: [*c]const u8, mode: c_int, devp: ?*?*kern.Device) callconv(.c) c_int {
    var str: [hal.MAXDEVNAME]u8 = undefined;
    const copy_err: c_int = hal.copyinstr(@ptrCast(name), @ptrCast(&str), hal.MAXDEVNAME);
    if (copy_err != 0) return copy_err;

    sched.lock();
    const dev: ?*kern.Device = lookup(@ptrCast(&str));
    if (dev == null) {
        sched.unlock();
        return kern.Errno.ENXIO;
    }
    const ref_err: c_int = reference(dev);
    if (ref_err != 0) {
        sched.unlock();
        return ref_err;
    }
    sched.unlock();

    const drv: ?*hal.Driver = dev.?.driver;
    const ops: ?*c.struct_devops = if (drv) |d| d.devops else null;
    var err: c_int = 0;
    if (ops != null and ops.?.open != null) {
        err = ops.?.open.?(@ptrCast(dev), mode);
    }
    if (err == 0) {
        const cp_err: c_int = hal.copyout(@ptrCast(&dev), @ptrCast(devp), @sizeOf(?*kern.Device));
        if (cp_err != 0) err = cp_err;
    }

    release(dev);
    return err;
}

/// close – close a device.
pub fn close(dev: ?*kern.Device) callconv(.c) c_int {
    const ref_err: c_int = reference(dev);
    if (ref_err != 0) return ref_err;

    const drv: ?*hal.Driver = dev.?.driver;
    const ops: ?*c.struct_devops = if (drv) |d| d.devops else null;
    var err: c_int = 0;
    if (ops != null and ops.?.close != null) {
        err = ops.?.close.?(@ptrCast(dev));
    }

    release(dev);
    return err;
}

/// read – read from a device.
pub fn read(dev: ?*kern.Device, buf: ?*anyopaque, nbyte: ?*usize, blkno: c_int) callconv(.c) c_int {
    if (!kutil.user_area(buf)) return kern.Errno.EFAULT;

    const ref_err: c_int = reference(dev);
    if (ref_err != 0) return ref_err;

    var count: usize = 0;
    if (nbyte != null) {
        const ci_err: c_int = hal.copyin(@ptrCast(nbyte), @ptrCast(&count), @sizeOf(usize));
        if (ci_err != 0) {
            release(dev);
            return kern.Errno.EFAULT;
        }
    }

    const drv: ?*hal.Driver = dev.?.driver;
    const ops: ?*c.struct_devops = if (drv) |d| d.devops else null;
    var err: c_int = 0;
    if (ops != null and ops.?.read != null) {
        err = ops.?.read.?(@ptrCast(dev), @ptrCast(buf), &count, blkno);
    }
    if (err == 0 and nbyte != null) {
        const co_err: c_int = hal.copyout(@ptrCast(&count), @ptrCast(nbyte), @sizeOf(usize));
        if (co_err != 0) err = co_err;
    }

    release(dev);
    return err;
}

/// write – write to a device.
pub fn write(dev: ?*kern.Device, buf: ?*anyopaque, nbyte: ?*usize, blkno: c_int) callconv(.c) c_int {
    if (!kutil.user_area(buf)) return kern.Errno.EFAULT;

    const ref_err: c_int = reference(dev);
    if (ref_err != 0) return ref_err;

    var count: usize = 0;
    if (nbyte != null) {
        const ci_err: c_int = hal.copyin(@ptrCast(nbyte), @ptrCast(&count), @sizeOf(usize));
        if (ci_err != 0) {
            release(dev);
            return kern.Errno.EFAULT;
        }
    }

    const drv: ?*hal.Driver = dev.?.driver;
    const ops: ?*c.struct_devops = if (drv) |d| d.devops else null;
    var err: c_int = 0;
    if (ops != null and ops.?.write != null) {
        err = ops.?.write.?(@ptrCast(dev), @ptrCast(buf), &count, blkno);
    }
    if (err == 0 and nbyte != null) {
        const co_err: c_int = hal.copyout(@ptrCast(&count), @ptrCast(nbyte), @sizeOf(usize));
        if (co_err != 0) err = co_err;
    }

    release(dev);
    return err;
}

/// gatherRead – gather read from a device.
pub fn gatherRead(dev: ?*kern.Device, buf: ?*anyopaque, nbyte: ?*usize, io: ?*c.struct_dev_io) callconv(.c) c_int {
    if (!kutil.user_area(buf)) return kern.Errno.EFAULT;

    const ref_err: c_int = reference(dev);
    if (ref_err != 0) return ref_err;

    var count: usize = 0;
    if (nbyte != null) {
        const ci_err: c_int = hal.copyin(@ptrCast(nbyte), @ptrCast(&count), @sizeOf(usize));
        if (ci_err != 0) {
            release(dev);
            return kern.Errno.EFAULT;
        }
    }

    var kio: c.struct_dev_io = undefined;
    if (io != null) {
        const ci_err: c_int = hal.copyin(@ptrCast(io), @ptrCast(&kio), @sizeOf(c.struct_dev_io));
        if (ci_err != 0) {
            release(dev);
            return kern.Errno.EFAULT;
        }
    }

    if (kio.blksz == 0) {
        release(dev);
        return kern.Errno.EINVAL;
    }

    const drv: ?*hal.Driver = dev.?.driver;
    const ops: ?*c.struct_devops = if (drv) |d| d.devops else null;
    var total: usize = 0;
    var err: c_int = 0;
    const p: [*]u8 = @ptrCast(buf);
    var offset: usize = 0;

    while (total < count) : ({
        offset += kio.blksz;
    }) {
        var b: c_int = 0;
        const ci_err: c_int = hal.copyin(@ptrCast(@as([*]c_int, @ptrCast(kio.blkno)) + offset / kio.blksz), @ptrCast(&b), @sizeOf(c_int));
        if (ci_err != 0) {
            err = kern.Errno.EFAULT;
            break;
        }
        var size: usize = kio.blksz;
        if (total + size > count) {
            size = count - total;
        }

        if (ops != null and ops.?.read != null) {
            err = ops.?.read.?(@ptrCast(dev), @ptrCast(p + total), &size, b);
        }
        if (err != 0) break;

        total += size;
    }

    if (err == 0 or total > 0) {
        const co_err: c_int = hal.copyout(@ptrCast(&total), @ptrCast(nbyte), @sizeOf(usize));
        if (err == 0) err = co_err;
    }

    release(dev);
    return err;
}

/// scatterWrite – scatter write to a device.
pub fn scatterWrite(dev: ?*kern.Device, buf: ?*anyopaque, nbyte: ?*usize, io: ?*c.struct_dev_io) callconv(.c) c_int {
    if (!kutil.user_area(buf)) return kern.Errno.EFAULT;

    const ref_err: c_int = reference(dev);
    if (ref_err != 0) return ref_err;

    var count: usize = 0;
    if (nbyte != null) {
        const ci_err: c_int = hal.copyin(@ptrCast(nbyte), @ptrCast(&count), @sizeOf(usize));
        if (ci_err != 0) {
            release(dev);
            return kern.Errno.EFAULT;
        }
    }

    var kio: c.struct_dev_io = undefined;
    if (io != null) {
        const ci_err: c_int = hal.copyin(@ptrCast(io), @ptrCast(&kio), @sizeOf(c.struct_dev_io));
        if (ci_err != 0) {
            release(dev);
            return kern.Errno.EFAULT;
        }
    }

    if (kio.blksz == 0) {
        release(dev);
        return kern.Errno.EINVAL;
    }

    const drv: ?*hal.Driver = dev.?.driver;
    const ops: ?*c.struct_devops = if (drv) |d| d.devops else null;
    var total: usize = 0;
    var err: c_int = 0;
    const p: [*]u8 = @ptrCast(buf);
    var offset: usize = 0;

    while (total < count) : ({
        offset += kio.blksz;
    }) {
        var b: c_int = 0;
        const ci_err: c_int = hal.copyin(@ptrCast(@as([*]c_int, @ptrCast(kio.blkno)) + offset / kio.blksz), @ptrCast(&b), @sizeOf(c_int));
        if (ci_err != 0) {
            err = kern.Errno.EFAULT;
            break;
        }
        var size: usize = kio.blksz;
        if (total + size > count) {
            size = count - total;
        }

        if (ops != null and ops.?.write != null) {
            err = ops.?.write.?(@ptrCast(dev), @ptrCast(p + total), &size, b);
        }
        if (err != 0) break;

        total += size;
    }

    if (err == 0 or total > 0) {
        const co_err: c_int = hal.copyout(@ptrCast(&total), @ptrCast(nbyte), @sizeOf(usize));
        if (err == 0) err = co_err;
    }

    release(dev);
    return err;
}

/// ioctl – I/O control request.
pub fn ioctl(dev: ?*kern.Device, cmd: c_ulong, arg: ?*anyopaque) callconv(.c) c_int {
    const ref_err: c_int = reference(dev);
    if (ref_err != 0) return ref_err;

    const drv: ?*hal.Driver = dev.?.driver;
    const ops: ?*c.struct_devops = if (drv) |d| d.devops else null;
    var err: c_int = 0;
    if (ops != null and ops.?.ioctl != null) {
        err = ops.?.ioctl.?(@ptrCast(dev), cmd, arg);
    }

    release(dev);
    return err;
}

/// info – return device information.
pub fn info(dev_info: ?*hal.DeviceInfo) callconv(.c) c_int {
    if (dev_info == null) return kern.Errno.EINVAL;
    const target = dev_info.?.cookie;
    var i: c_ulong = 0;
    var err: c_int = kern.Errno.ESRCH;

    sched.lock();
    defer sched.unlock();
    var dev = device_list;
    while (dev) |d| : (dev = @ptrCast(d.next)) {
        if (i == target) {
            dev_info.?.cookie = i + 1;
            dev_info.?.id = @as(?*c.struct_device, @ptrCast(d));
            dev_info.?.flags = d.flags;
            _ = lib.strlcpy(@ptrCast(&dev_info.?.name), @ptrCast(&d.name), hal.MAXDEVNAME);
            err = 0;
            break;
        }
        i += 1;
    }
    return err;
}

/// init – initialize device driver module.
pub fn init() callconv(.c) void {
    var bi: ?*hal.BootInfo = null;
    hal.machine_bootinfo(@ptrCast(&bi));
    if (bi == null) return;

    const mod: ?*hal.Module = &bi.?.driver;
    if (mod == null) return;

    const entry_fn: ?*const fn ([*]const ?*const anyopaque) callconv(.c) void = @ptrCast(@alignCast(@as(?*anyopaque, @ptrFromInt(mod.?.entry))));
    if (entry_fn == null) return;

    entry_fn.?(@ptrCast(&dkient));
}

// ---------------------------------------------------------------------------
// Driver-Kernel Interface (DKI) export table
// Maps to indices defined in sys/include/sys/dki_table.h
// ---------------------------------------------------------------------------
const dkifn_t = ?*const anyopaque;

const dkient = [40]dkifn_t{
    //  0: copyin
    @ptrCast(&hal.copyin),
    //  1: copyout
    @ptrCast(&hal.copyout),
    //  2: copyinstr
    @ptrCast(&hal.copyinstr),
    //  3: kmem_alloc
    @ptrCast(&c.kmem_alloc),
    //  4: kmem_free
    @ptrCast(&c.kmem_free),
    //  5: kmem_map
    @ptrCast(&c.kmem_map),
    //  6: page_alloc
    @ptrCast(&c.page_alloc),
    //  7: page_free
    @ptrCast(&c.page_free),
    //  8: page_reserve
    @ptrCast(&c.page_reserve),
    //  9: irq_attach
    @ptrCast(&c.irq_attach),
    // 10: irq_detach
    @ptrCast(&c.irq_detach),
    // 11: spl0
    @ptrCast(&hal.spl0),
    // 12: splhigh
    @ptrCast(&hal.splhigh),
    // 13: splx
    @ptrCast(&hal.splx),
    // 14: timer_callout
    @ptrCast(&c.timer_callout),
    // 15: timer_stop
    @ptrCast(&c.timer_stop),
    // 16: timer_delay
    @ptrCast(&c.timer_delay),
    // 17: timer_ticks
    @ptrCast(&timer.ticks),
    // 18: sched_lock
    @ptrCast(&sched.lock),
    // 19: sched_unlock
    @ptrCast(&sched.unlock),
    // 20: sched_tsleep
    @ptrCast(&c.sched_tsleep),
    // 21: sched_wakeup
    @ptrCast(&c.sched_wakeup),
    // 22: sched_dpc
    @ptrCast(&c.sched_dpc),
    // 23: task_capable
    @ptrCast(&c.task_capable),
    // 24: exception_post
    @ptrCast(&exception.post),
    // 25: create (local)
    @ptrCast(&create),
    // 26: destroy (local)
    @ptrCast(&destroy),
    // 27: lookup (local)
    @ptrCast(&lookup),
    // 28: control (local)
    @ptrCast(&control),
    // 29: broadcast (local)
    @ptrCast(&broadcast),
    // 30: privateFn (local)
    @ptrCast(&privateFn),
    // 31: machine_bootinfo
    @ptrCast(&hal.machine_bootinfo),
    // 32: machine_powerdown
    @ptrCast(&hal.machine_powerdown),
    // 33: sysinfo
    @ptrCast(&c.sysinfo),
    // 34: DEBUG-dependent: panic or machine_abort
    @ptrCast(if (c.DEBUG != 0) @as(*const anyopaque, @ptrCast(&lib.panic)) else @as(*const anyopaque, @ptrCast(&hal.machine_abort))),
    // 35: DEBUG-dependent: printf or sys_nosys
    @ptrCast(if (c.DEBUG != 0) @as(*const anyopaque, @ptrCast(&lib.printf)) else @as(*const anyopaque, @ptrCast(&c.sys_nosys))),
    // 36: DEBUG-dependent: dbgctl or sys_nosys
    @ptrCast(if (c.DEBUG != 0) @as(*const anyopaque, @ptrCast(&hal.dbgctl)) else @as(*const anyopaque, @ptrCast(&c.sys_nosys))),
    // 37: hal_uart_lock
    @ptrCast(&c.hal_uart_lock),
    // 38: hal_uart_unlock
    @ptrCast(&c.hal_uart_unlock),
    // 39: ksem_post
    @ptrCast(&c.ksem_post),
};

// ---------------------------------------------------------------------------
// Comptime exports – public API functions with strong C linkage
// ---------------------------------------------------------------------------
comptime {
    if (@import("root") == @This()) {
        @export(&open, .{ .name = "device_open", .linkage = .strong });
        @export(&close, .{ .name = "device_close", .linkage = .strong });
        @export(&read, .{ .name = "device_read", .linkage = .strong });
        @export(&write, .{ .name = "device_write", .linkage = .strong });
        @export(&gatherRead, .{ .name = "device_gather_read", .linkage = .strong });
        @export(&scatterWrite, .{ .name = "device_scatter_write", .linkage = .strong });
        @export(&ioctl, .{ .name = "device_ioctl", .linkage = .strong });
        @export(&info, .{ .name = "device_info", .linkage = .strong });
        @export(&init, .{ .name = "device_init", .linkage = .strong });
    }
}
