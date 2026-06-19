const std = @import("std");

const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});

// ---------------------------------------------------------------------------
// device_list: head of the linked list of all device objects
// ---------------------------------------------------------------------------
var device_list: ?*c.struct_device = null;

// ---------------------------------------------------------------------------
// user_area – Stage 2 safety check for user-space pointer validation
// ---------------------------------------------------------------------------
inline fn user_area(a: ?*anyopaque) bool {
    if (a == null) return false;
    if (@hasDecl(c, "CONFIG_MMU")) {
        return @intFromPtr(a) < c.USERLIMIT;
    } else {
        return true;
    }
}

// ---------------------------------------------------------------------------
// Helper functions – local implementations with C calling convention
// These are referenced by the dkient table via pointer mapping.
// ---------------------------------------------------------------------------

/// device_create – create a new device object.
/// Returns device pointer on success, null on failure.
fn device_create(drv: ?*c.struct_driver, name: [*c]const u8, flags: c_int) callconv(.c) ?*c.struct_device {
    var len: usize = 0;
    var priv: ?*anyopaque = null;

    c.sched_lock();

    // Check the length of the name.
    len = c.strnlen(name, c.MAXDEVNAME);
    if (len == 0 or len >= c.MAXDEVNAME) {
        c.sched_unlock();
        return null;
    }

    // Check if the specified name is already used.
    if (device_lookup(name) != null) {
        c.panic("duplicate device");
    }

    // Allocate a device structure.
    const dev: ?*c.struct_device = @ptrCast(@alignCast(c.kmem_alloc(@sizeOf(c.struct_device))));
    if (dev == null) {
        c.panic("device_create");
    }
    const dev_ptr = dev.?;

    // Allocate driver private data if needed.
    if (drv != null and drv.?.devsz != 0) {
        priv = c.kmem_alloc(drv.?.devsz);
        if (priv == null) {
            c.panic("devsz");
        }
        _ = c.memset(priv, 0, drv.?.devsz);
    }

    _ = c.strlcpy(@ptrCast(&dev_ptr.name), name, len + 1);
    dev_ptr.driver = drv;
    dev_ptr.flags = flags;
    dev_ptr.active = 1;
    dev_ptr.refcnt = 1;
    dev_ptr.@"private" = priv;
    dev_ptr.next = device_list;
    device_list = dev_ptr;

    c.sched_unlock();
    return dev_ptr;
}

/// device_destroy – destroy a device object.
/// Returns 0 on success, ENODEV on failure.
fn device_destroy(dev: ?*c.struct_device) callconv(.c) c_int {
    c.sched_lock();
    if (device_valid(dev) == 0) {
        c.sched_unlock();
        return c.ENODEV;
    }
    dev.?.active = 0;
    device_release(dev);
    c.sched_unlock();
    return 0;
}

/// device_lookup – look up a device object by name.
/// Returns device pointer if found, null otherwise.
fn device_lookup(name: [*c]const u8) callconv(.c) ?*c.struct_device {
    var dev = device_list;
    while (dev) |d| : (dev = @ptrCast(d.next)) {
        if (c.strncmp(&d.name, name, c.MAXDEVNAME) == 0) {
            return d;
        }
    }
    return null;
}

/// device_valid – return true (1) if specified device is valid.
fn device_valid(dev: ?*c.struct_device) callconv(.c) c_int {
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

/// device_reference – increment the reference count on an active device.
/// Returns 0 on success, ENODEV or EPERM on failure.
fn device_reference(dev: ?*c.struct_device) callconv(.c) c_int {
    c.sched_lock();
    if (device_valid(dev) == 0) {
        c.sched_unlock();
        return c.ENODEV;
    }
    if (c.task_capable(c.CAP_RAWIO) == 0) {
        c.sched_unlock();
        return c.EPERM;
    }
    dev.?.refcnt += 1;
    c.sched_unlock();
    return 0;
}

/// device_release – decrement the reference count; free when it reaches zero.
fn device_release(dev: ?*c.struct_device) callconv(.c) void {
    c.sched_lock();
    const dev_ptr = dev.?;
    dev_ptr.refcnt -= 1;
    if (dev_ptr.refcnt > 0) {
        c.sched_unlock();
        return;
    }

    // Remove the device from the list.
    var tmp: *?*c.struct_device = &device_list;
    while (tmp.*) |curr| {
        if (curr == dev_ptr) {
            tmp.* = @ptrCast(curr.next);
            break;
        }
        tmp = @ptrCast(&curr.next);
    }
    c.kmem_free(dev_ptr);
    c.sched_unlock();
}

/// device_private – return device's private data.
fn device_private(dev: ?*c.struct_device) callconv(.c) ?*anyopaque {
    if (dev == null) return null;
    return dev.?.@"private";
}

/// device_control – devctl from another device driver (internal).
fn device_control(dev: ?*c.struct_device, cmd: c_ulong, arg: ?*anyopaque) callconv(.c) c_int {
    c.sched_lock();
    const drv: ?*c.struct_driver = if (dev) |d| d.driver else null;
    const ops: ?*c.struct_devops = if (drv) |dr| dr.devops else null;
    if (ops == null or ops.?.devctl == null) {
        c.sched_unlock();
        return c.EINVAL;
    }
    const err: c_int = ops.?.devctl.?(dev, cmd, arg);
    c.sched_unlock();
    return err;
}

/// device_broadcast – broadcast devctl command to all device objects.
fn device_broadcast(cmd: c_ulong, arg: ?*anyopaque, force: c_int) callconv(.c) c_int {
    var retval: c_int = 0;

    c.sched_lock();

    var dev = device_list;
    while (dev) |d| : (dev = @ptrCast(d.next)) {
        const drv: ?*c.struct_driver = d.driver;
        const ops: ?*c.struct_devops = if (drv) |dr| dr.devops else null;
        if (ops == null) continue;
        if (ops.?.devctl == null) continue;

        const err: c_int = ops.?.devctl.?(d, cmd, arg);
        if (err != 0) {
            if (force != 0) {
                retval = c.EIO;
            } else {
                retval = err;
                break;
            }
        }
    }
    c.sched_unlock();
    return retval;
}

// ---------------------------------------------------------------------------
// Public functions – exported with strong C linkage
// ---------------------------------------------------------------------------

/// device_open – open the specified device.
pub fn device_open(name: [*c]const u8, mode: c_int, devp: ?*?*c.struct_device) callconv(.c) c_int {
    var str: [c.MAXDEVNAME]u8 = undefined;
    const copy_err: c_int = c.copyinstr(@ptrCast(name), @ptrCast(&str), c.MAXDEVNAME);
    if (copy_err != 0) return copy_err;

    c.sched_lock();
    const dev: ?*c.struct_device = device_lookup(@ptrCast(&str));
    if (dev == null) {
        c.sched_unlock();
        return c.ENXIO;
    }
    const ref_err: c_int = device_reference(dev);
    if (ref_err != 0) {
        c.sched_unlock();
        return ref_err;
    }
    c.sched_unlock();

    const drv: ?*c.struct_driver = dev.?.driver;
    const ops: ?*c.struct_devops = if (drv) |d| d.devops else null;
    var err: c_int = 0;
    if (ops != null and ops.?.open != null) {
        err = ops.?.open.?(dev, mode);
    }
    if (err == 0) {
        const cp_err: c_int = c.copyout(@ptrCast(&dev), @ptrCast(devp), @sizeOf(?*c.struct_device));
        if (cp_err != 0) err = cp_err;
    }

    device_release(dev);
    return err;
}

/// device_close – close a device.
pub fn device_close(dev: ?*c.struct_device) callconv(.c) c_int {
    const ref_err: c_int = device_reference(dev);
    if (ref_err != 0) return ref_err;

    const drv: ?*c.struct_driver = dev.?.driver;
    const ops: ?*c.struct_devops = if (drv) |d| d.devops else null;
    var err: c_int = 0;
    if (ops != null and ops.?.close != null) {
        err = ops.?.close.?(dev);
    }

    device_release(dev);
    return err;
}

/// device_read – read from a device.
pub fn device_read(dev: ?*c.struct_device, buf: ?*anyopaque, nbyte: ?*usize, blkno: c_int) callconv(.c) c_int {
    if (!user_area(buf)) return c.EFAULT;

    const ref_err: c_int = device_reference(dev);
    if (ref_err != 0) return ref_err;

    var count: usize = 0;
    if (nbyte != null) {
        const ci_err: c_int = c.copyin(@ptrCast(nbyte), @ptrCast(&count), @sizeOf(usize));
        if (ci_err != 0) {
            device_release(dev);
            return c.EFAULT;
        }
    }

    const drv: ?*c.struct_driver = dev.?.driver;
    const ops: ?*c.struct_devops = if (drv) |d| d.devops else null;
    var err: c_int = 0;
    if (ops != null and ops.?.read != null) {
        err = ops.?.read.?(dev, @ptrCast(buf), &count, blkno);
    }
    if (err == 0 and nbyte != null) {
        const co_err: c_int = c.copyout(@ptrCast(&count), @ptrCast(nbyte), @sizeOf(usize));
        if (co_err != 0) err = co_err;
    }

    device_release(dev);
    return err;
}

/// device_write – write to a device.
pub fn device_write(dev: ?*c.struct_device, buf: ?*anyopaque, nbyte: ?*usize, blkno: c_int) callconv(.c) c_int {
    if (!user_area(buf)) return c.EFAULT;

    const ref_err: c_int = device_reference(dev);
    if (ref_err != 0) return ref_err;

    var count: usize = 0;
    if (nbyte != null) {
        const ci_err: c_int = c.copyin(@ptrCast(nbyte), @ptrCast(&count), @sizeOf(usize));
        if (ci_err != 0) {
            device_release(dev);
            return c.EFAULT;
        }
    }

    const drv: ?*c.struct_driver = dev.?.driver;
    const ops: ?*c.struct_devops = if (drv) |d| d.devops else null;
    var err: c_int = 0;
    if (ops != null and ops.?.write != null) {
        err = ops.?.write.?(dev, @ptrCast(buf), &count, blkno);
    }
    if (err == 0 and nbyte != null) {
        const co_err: c_int = c.copyout(@ptrCast(&count), @ptrCast(nbyte), @sizeOf(usize));
        if (co_err != 0) err = co_err;
    }

    device_release(dev);
    return err;
}

/// device_gather_read – gather read from a device.
pub fn device_gather_read(dev: ?*c.struct_device, buf: ?*anyopaque, nbyte: ?*usize, io: ?*c.struct_dev_io) callconv(.c) c_int {
    if (!user_area(buf)) return c.EFAULT;

    const ref_err: c_int = device_reference(dev);
    if (ref_err != 0) return ref_err;

    var count: usize = 0;
    if (nbyte != null) {
        const ci_err: c_int = c.copyin(@ptrCast(nbyte), @ptrCast(&count), @sizeOf(usize));
        if (ci_err != 0) {
            device_release(dev);
            return c.EFAULT;
        }
    }

    var kio: c.struct_dev_io = undefined;
    if (io != null) {
        const ci_err: c_int = c.copyin(@ptrCast(io), @ptrCast(&kio), @sizeOf(c.struct_dev_io));
        if (ci_err != 0) {
            device_release(dev);
            return c.EFAULT;
        }
    }

    if (kio.blksz == 0) {
        device_release(dev);
        return c.EINVAL;
    }

    const drv: ?*c.struct_driver = dev.?.driver;
    const ops: ?*c.struct_devops = if (drv) |d| d.devops else null;
    var total: usize = 0;
    var err: c_int = 0;
    const p: [*]u8 = @ptrCast(buf);
    var offset: usize = 0;

    while (total < count) : ({
        offset += kio.blksz;
    }) {
        var b: c_int = 0;
        const ci_err: c_int = c.copyin(@ptrCast(@as([*]c_int, @ptrCast(kio.blkno)) + offset / kio.blksz), @ptrCast(&b), @sizeOf(c_int));
        if (ci_err != 0) {
            err = c.EFAULT;
            break;
        }
        var size: usize = kio.blksz;
        if (total + size > count) {
            size = count - total;
        }

        if (ops != null and ops.?.read != null) {
            err = ops.?.read.?(dev, @ptrCast(p + total), &size, b);
        }
        if (err != 0) break;

        total += size;
    }

    if (err == 0 or total > 0) {
        const co_err: c_int = c.copyout(@ptrCast(&total), @ptrCast(nbyte), @sizeOf(usize));
        if (err == 0) err = co_err;
    }

    device_release(dev);
    return err;
}

/// device_scatter_write – scatter write to a device.
pub fn device_scatter_write(dev: ?*c.struct_device, buf: ?*anyopaque, nbyte: ?*usize, io: ?*c.struct_dev_io) callconv(.c) c_int {
    if (!user_area(buf)) return c.EFAULT;

    const ref_err: c_int = device_reference(dev);
    if (ref_err != 0) return ref_err;

    var count: usize = 0;
    if (nbyte != null) {
        const ci_err: c_int = c.copyin(@ptrCast(nbyte), @ptrCast(&count), @sizeOf(usize));
        if (ci_err != 0) {
            device_release(dev);
            return c.EFAULT;
        }
    }

    var kio: c.struct_dev_io = undefined;
    if (io != null) {
        const ci_err: c_int = c.copyin(@ptrCast(io), @ptrCast(&kio), @sizeOf(c.struct_dev_io));
        if (ci_err != 0) {
            device_release(dev);
            return c.EFAULT;
        }
    }

    if (kio.blksz == 0) {
        device_release(dev);
        return c.EINVAL;
    }

    const drv: ?*c.struct_driver = dev.?.driver;
    const ops: ?*c.struct_devops = if (drv) |d| d.devops else null;
    var total: usize = 0;
    var err: c_int = 0;
    const p: [*]u8 = @ptrCast(buf);
    var offset: usize = 0;

    while (total < count) : ({
        offset += kio.blksz;
    }) {
        var b: c_int = 0;
        const ci_err: c_int = c.copyin(@ptrCast(@as([*]c_int, @ptrCast(kio.blkno)) + offset / kio.blksz), @ptrCast(&b), @sizeOf(c_int));
        if (ci_err != 0) {
            err = c.EFAULT;
            break;
        }
        var size: usize = kio.blksz;
        if (total + size > count) {
            size = count - total;
        }

        if (ops != null and ops.?.write != null) {
            err = ops.?.write.?(dev, @ptrCast(p + total), &size, b);
        }
        if (err != 0) break;

        total += size;
    }

    if (err == 0 or total > 0) {
        const co_err: c_int = c.copyout(@ptrCast(&total), @ptrCast(nbyte), @sizeOf(usize));
        if (err == 0) err = co_err;
    }

    device_release(dev);
    return err;
}

/// device_ioctl – I/O control request.
pub fn device_ioctl(dev: ?*c.struct_device, cmd: c_ulong, arg: ?*anyopaque) callconv(.c) c_int {
    const ref_err: c_int = device_reference(dev);
    if (ref_err != 0) return ref_err;

    const drv: ?*c.struct_driver = dev.?.driver;
    const ops: ?*c.struct_devops = if (drv) |d| d.devops else null;
    var err: c_int = 0;
    if (ops != null and ops.?.ioctl != null) {
        err = ops.?.ioctl.?(dev, cmd, arg);
    }

    device_release(dev);
    return err;
}

/// device_info – return device information.
pub fn device_info(info: ?*c.struct_devinfo) callconv(.c) c_int {
    if (info == null) return c.EINVAL;
    const target = info.?.cookie;
    var i: c_ulong = 0;
    var err: c_int = c.ESRCH;

    c.sched_lock();
    var dev = device_list;
    while (dev) |d| : (dev = @ptrCast(d.next)) {
        if (i == target) {
            info.?.cookie = i + 1;
            info.?.id = d;
            info.?.flags = d.flags;
            _ = c.strlcpy(@ptrCast(&info.?.name), @ptrCast(&d.name), c.MAXDEVNAME);
            err = 0;
            break;
        }
        i += 1;
    }
    c.sched_unlock();
    return err;
}

/// device_init – initialize device driver module.
pub fn device_init() callconv(.c) void {
    var bi: ?*c.struct_bootinfo = null;
    c.machine_bootinfo(@ptrCast(&bi));
    if (bi == null) return;

    const mod: ?*c.struct_module = &bi.?.driver;
    if (mod == null) return;

    const entry_fn: ?*const fn ([*]const ?*const anyopaque) callconv(.c) void = @ptrFromInt(mod.?.entry);
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
    @ptrCast(&c.copyin),
    //  1: copyout
    @ptrCast(&c.copyout),
    //  2: copyinstr
    @ptrCast(&c.copyinstr),
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
    @ptrCast(&c.spl0),
    // 12: splhigh
    @ptrCast(&c.splhigh),
    // 13: splx
    @ptrCast(&c.splx),
    // 14: timer_callout
    @ptrCast(&c.timer_callout),
    // 15: timer_stop
    @ptrCast(&c.timer_stop),
    // 16: timer_delay
    @ptrCast(&c.timer_delay),
    // 17: timer_ticks
    @ptrCast(&c.timer_ticks),
    // 18: sched_lock
    @ptrCast(&c.sched_lock),
    // 19: sched_unlock
    @ptrCast(&c.sched_unlock),
    // 20: sched_tsleep
    @ptrCast(&c.sched_tsleep),
    // 21: sched_wakeup
    @ptrCast(&c.sched_wakeup),
    // 22: sched_dpc
    @ptrCast(&c.sched_dpc),
    // 23: task_capable
    @ptrCast(&c.task_capable),
    // 24: exception_post
    @ptrCast(&c.exception_post),
    // 25: device_create (local)
    @ptrCast(&device_create),
    // 26: device_destroy (local)
    @ptrCast(&device_destroy),
    // 27: device_lookup (local)
    @ptrCast(&device_lookup),
    // 28: device_control (local)
    @ptrCast(&device_control),
    // 29: device_broadcast (local)
    @ptrCast(&device_broadcast),
    // 30: device_private (local)
    @ptrCast(&device_private),
    // 31: machine_bootinfo
    @ptrCast(&c.machine_bootinfo),
    // 32: machine_powerdown
    @ptrCast(&c.machine_powerdown),
    // 33: sysinfo
    @ptrCast(&c.sysinfo),
    // 34: DEBUG-dependent: panic or machine_abort
    @ptrCast(if (c.DEBUG != 0) @as(*const anyopaque, @ptrCast(&c.panic)) else @as(*const anyopaque, @ptrCast(&c.machine_abort))),
    // 35: DEBUG-dependent: printf or sys_nosys
    @ptrCast(if (c.DEBUG != 0) @as(*const anyopaque, @ptrCast(&c.printf)) else @as(*const anyopaque, @ptrCast(&c.sys_nosys))),
    // 36: DEBUG-dependent: dbgctl or sys_nosys
    @ptrCast(if (c.DEBUG != 0) @as(*const anyopaque, @ptrCast(&c.dbgctl)) else @as(*const anyopaque, @ptrCast(&c.sys_nosys))),
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
    @export(&device_open, .{ .name = "device_open", .linkage = .strong });
    @export(&device_close, .{ .name = "device_close", .linkage = .strong });
    @export(&device_read, .{ .name = "device_read", .linkage = .strong });
    @export(&device_write, .{ .name = "device_write", .linkage = .strong });
    @export(&device_gather_read, .{ .name = "device_gather_read", .linkage = .strong });
    @export(&device_scatter_write, .{ .name = "device_scatter_write", .linkage = .strong });
    @export(&device_ioctl, .{ .name = "device_ioctl", .linkage = .strong });
    @export(&device_info, .{ .name = "device_info", .linkage = .strong });
    @export(&device_init, .{ .name = "device_init", .linkage = .strong });
}
