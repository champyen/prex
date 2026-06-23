# Zig Driver Development Guide

Prex+ supports writing device drivers in the Zig programming language. This guide explains how to develop, build, and integrate Zig-based drivers into the Prex+ kernel using modern, idiomatic Zig patterns.

---

## 1. Getting Started

### Prerequisites
*   **Zig Compiler**: Version 0.16.0 or higher.
*   **Target Architecture**: ARM (EABI/Thumb), x86, or RISC-V.

### Enabling Zig Support
To enable Zig driver compilation, you must set `CONFIG_ZIG_DRV=y` in your configuration.
1.  Run `./configure` as usual.
2.  Add `CONFIG_ZIG_DRV=y` to `conf/config.mk`.
3.  Add `#define CONFIG_ZIG_DRV y` to `conf/config.h`.

---

## 2. Driver Structure

The preferred way to structure a Zig driver in Prex+ is using a **Static Interface** pattern. This uses compile-time reflection to build the C-compatible jump table.

### Recommended Template
```zig
const std = @import("std");
const dki = @import("dki");
const c = dki.c;

/// Implementation of the driver interface
const Interface = struct {
    pub fn open(dev: c.device_t, mode: c_int) callconv(.c) c_int {
        // ...
        return 0;
    }

    pub fn read(dev: c.device_t, buf: [*]c_char, n: *usize, blk: c_int) callconv(.c) c_int {
        // ...
        return 0;
    }
};

/// Mandatory init function
export fn my_init(self: ?*dki.Driver) callconv(.c) c_int {
    // ALWAYS initialize DevOps at runtime. 
    // Static initialization causes relocation slot collisions on x86.
    my_devops = dki.wrap(Interface);
    
    _ = dki.device_create(self.?, "mydev0", c.D_CHR) catch |err| return dki.toCError(err);
    return 0;
}

export var my_devops = dki.DevOps{ .open = null };

export var my_driver = dki.Driver{
    .name = "my_driver",
    .devops = &my_devops,
    .devsz = @sizeOf(MySoftc),
    .init = my_init,
};
```

---

## 3. Core API (dki.zig)

### Static Interface Generation
*   **`dki.wrap(comptime T: type)`**: Uses metaprogramming to build a `DevOps` structure. It automatically detects functions like `open`, `close`, `read`, `write`, `ioctl`, and `devctl` in your implementation struct and verifies their C-calling convention signatures at compile-time.

### Memory Management
*   **`dki.allocator`**: A standard `std.mem.Allocator` implementation. **Zig 0.16.0 note**: The VTable now includes a mandatory `remap` field and uses `std.mem.Alignment` types.
*   **`dki.ptokv / dki.kvtop`**: Physical/Virtual address translation.
*   **`dki.kmem_map(ptr, size)`**: Maps user buffers for kernel I/O.

### Hardware I/O
*   **`dki.bus_read_32 / dki.bus_write_32`**: Safe helpers for memory-mapped I/O. Use these instead of Prex C macros, as Zig often fails to translate macros involving `volatile`.
*   **`dki.memoryBarrier()`**: Ensures memory operation ordering (cross-platform `asm volatile` barrier).

---

## 4. Interrupt Handling

Zig drivers can handle hardware interrupts using a standard ISR/IST pattern.

### Pattern for ISR/IST
```zig
export fn my_isr(arg: ?*anyopaque) callconv(.c) c_int {
    const sc: *Softc = @ptrCast(@alignCast(arg.?));
    // ... handle hardware ...
    return c.INT_CONTINUE; // or INT_DONE
}

export fn my_ist(arg: ?*anyopaque) callconv(.c) void {
    const sc: *Softc = @ptrCast(@alignCast(arg.?));
    dki.sched_wakeup(&sc.event);
}

// In init:
sc.irq = try dki.irq_attach(IRQ_NUM, c.IPL_BLOCK, 0, my_isr, my_ist, sc);
```

---

## 5. Design Patterns & Best Practices

### Robust Cleanup with `defer`
In driver code, state consistency is critical (e.g., flags like `busy`, or spinlocks). Use Zig's `defer` to ensure cleanup happens regardless of error paths or timeouts.
```zig
fn do_io(psc: *Softc) c_int {
    psc.busy = 1;
    // Guarantee busy flag is cleared on any return path
    defer psc.busy = 0;

    if (timeout) return c.ETIMEDOUT;
    if (error) return c.EIO;
    
    return 0;
}
```

### Subsystem Integration
Some drivers (like Serial or Block) attach to a subsystem instead of creating a device directly. In these cases:
1.  Set `.devops = null` in your `Driver` struct.
2.  Define your ops struct using the subsystem's type (e.g., `c.struct_serial_ops`).
3.  Call the subsystem's attach function (e.g., `c.serial_attach`).

### Kernel-Safe Standard Library
Since Prex drivers are **freestanding**, you cannot use `std` features that depend on an underlying OS.
*   **SAFE**: `std.mem`, `std.fmt`, `std.meta`, `std.atomic`, `std.enums`.
*   **UNSAFE**: `std.fs`, `std.os`, `std.io.getStdOut`, `std.net`.

### Pointer Strictness & Alignment
Zig is extremely strict about alignment, especially on RISC-V. 
*   Always use **`@alignCast()`** when converting from Prex internal pointers (like `device_private`) to your driver's softc.
*   Use **`extern struct`** for softc structures that must have a stable, predictable memory layout.

---

## 6. Building and Verification

1.  Update `Makefile.inc` with `$(call select_src,...)`.
2.  Build: `LC_ALL=C make`.
3.  Verify: Use `./verify_all.sh <target> [variant]` for automated multi-arch testing.

---

## See Also

*   [Zig Kernel Development Guide](zig_kernel.md) — kernel-side FFI, single-translation-unit model
*   [Zig Application Development Guide](zig_app.md) — user-space `prex`/`posix` libraries
*   [Build Guide](build.md) — toolchain, configuration
