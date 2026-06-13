const std = @import("std");
const dki = @import("dki");
const c = dki.c;

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    dki.panic(msg, error_return_trace, ret_addr);
}

/// RAM disk softc (private data)
const RamdiskSoftc = struct {
    dev: c.device_t,
    addr: [*]u8,
    size: usize,
};

const BSIZE = 512;

/// Read function for the RAM disk
export fn ramdisk_read(dev: c.device_t, buf: [*]c_char, nbyte: *usize, blkno: c_int) callconv(.c) c_int {
    const sc: *RamdiskSoftc = @ptrCast(@alignCast(dki.device_private(dev) orelse return c.ENODEV));
    const offset = @as(usize, @intCast(blkno)) * BSIZE;

    if (offset >= sc.size) {
        return c.EIO;
    }

    var nr_read = nbyte.*;
    if (offset + nr_read > sc.size) {
        nr_read = sc.size - offset;
    }

    const kbuf = dki.kmem_map(buf, nr_read) catch return c.EFAULT;

    @setRuntimeSafety(false);
    const d: [*]volatile u8 = @ptrCast(kbuf);
    const s: [*]volatile const u8 = @ptrCast(sc.addr);
    for (0..nr_read) |i| d[i] = s[offset + i];
    nbyte.* = nr_read;

    return 0;
}

/// Write function for the RAM disk
export fn ramdisk_write(dev: c.device_t, buf: [*]const c_char, nbyte: *usize, blkno: c_int) callconv(.c) c_int {
    const sc: *RamdiskSoftc = @ptrCast(@alignCast(dki.device_private(dev) orelse return c.ENODEV));
    const offset = @as(usize, @intCast(blkno)) * BSIZE;

    if (offset >= sc.size) return c.EIO;

    var nr_write = nbyte.*;
    if (offset + nr_write > sc.size) {
        nr_write = sc.size - offset;
    }

    const kbuf = dki.kmem_map(@ptrCast(@constCast(buf)), nr_write) catch return c.EFAULT;

    @setRuntimeSafety(false);
    var d: [*]volatile u8 = @ptrCast(sc.addr);
    const s: [*]volatile const u8 = @ptrCast(kbuf);
    for (0..nr_write) |i| d[offset + i] = s[i];
    nbyte.* = nr_write;

    return 0;
}

/// Probe function
export fn ramdisk_probe(_: ?*dki.Driver) callconv(.c) c_int {
    var bi: ?*c.bootinfo = null;
    c.machine_bootinfo(@ptrCast(&bi));

    if (bi.?.bootdisk.size == 0) {
        dki.log("ramdisk_zig: no bootdisk found...\n", .{});
        return c.ENXIO;
    }
    return 0;
}

/// Init function
export fn ramdisk_init(self: ?*dki.Driver) callconv(.c) c_int {
    var bi: ?*c.bootinfo = null;
    c.machine_bootinfo(@ptrCast(&bi));

    // Initialize devops at runtime
    ramdisk_devops.open = ramdisk_open;
    ramdisk_devops.close = ramdisk_close;
    ramdisk_devops.read = ramdisk_read;
    ramdisk_devops.write = ramdisk_write;

    const dev = dki.device_create(self.?, "ram0", c.D_BLK | c.D_PROT) catch |err| {
        dki.log("ramdisk_init: device_create failed\n", .{});
        return dki.toCError(err);
    };

    const priv = dki.device_private(dev) orelse {
        dki.log("ramdisk_init: device_private is null\n", .{});
        return c.ENOMEM;
    };
    const sc: *RamdiskSoftc = @ptrCast(@alignCast(priv));

    sc.dev = dev;
    sc.addr = dki.ptokv(bi.?.bootdisk.base);
    sc.size = @intCast(bi.?.bootdisk.size);

    dki.log("RAM disk (Zig) at 0x{x} ({}K bytes)\n", .{ @intFromPtr(sc.addr), sc.size / 1024 });
    return 0;
}

export fn ramdisk_open(_: c.device_t, _: c_int) callconv(.c) c_int {
    return 0;
}

export fn ramdisk_close(_: c.device_t) callconv(.c) c_int {
    return 0;
}

export var ramdisk_devops = dki.DevOps{
    .open = null,
    .close = null,
    .read = null,
    .write = null,
};

export var ramdisk_driver = dki.Driver{
    .name = "ramdisk",
    .devops = &ramdisk_devops,
    .devsz = @sizeOf(RamdiskSoftc),
    .flags = 0,
    .probe = ramdisk_probe,
    .init = ramdisk_init,
};
