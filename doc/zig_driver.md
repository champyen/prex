# Zig Driver Development Guide

Prex+ supports writing device drivers in the Zig programming language. This guide explains how to develop, build, and integrate Zig-based drivers into the Prex+ kernel.

---

## 1. Getting Started

### Prerequisites
*   **Zig Compiler**: Version 0.16.0 or higher.
*   **Target Architecture**: ARM (EABI/Thumb), x86, or RISC-V.

### Enabling Zig Support
To enable Zig driver compilation, you must set `CONFIG_ZIG_DRIVERS=y` in your configuration.
1.  Run `./configure` as usual.
2.  Add `CONFIG_ZIG_DRIVERS=y` to `conf/config.mk`.
3.  Add `#define CONFIG_ZIG_DRIVERS y` to `conf/config.h`.

---

## 2. Driver Structure

A Prex+ Zig driver is defined by an exported `Driver` structure. The build system uses a `select_src` macro that automatically prefers a `.zig` file over a `.c` file if both exist in the same directory.

### Basic Template
```zig
const std = @import("std");
const dki = @import("dki"); // Core Prex+ DKI/DDI Wrapper
const c = dki.c;

/// Private data for the driver
const MySoftc = struct {
    dev: c.device_t,
    // ...
};

/// Mandatory init function
export fn my_init(self: ?*dki.Driver) callconv(.c) c_int {
    // Initialize devops at runtime to avoid relocation issues
    my_devops.open = my_open;
    my_devops.read = my_read;
    
    const dev = dki.device_create(self.?, "mydev0", c.D_CHR) catch |err| return dki.toCError(err);
    // ...
    return 0;
}

export var my_devops = dki.DevOps{
    .open = null, // Set in init
    .read = null,
};

export var my_driver = dki.Driver{
    .name = "my_driver",
    .devops = &my_devops,
    .devsz = @sizeOf(MySoftc),
    .flags = 0,
    .probe = null,
    .init = my_init,
};
```

---

## 3. Core API (dki.zig)

The `dki` module provides type-safe wrappers for Prex+ kernel services.

### Memory Management
*   **`dki.ptokv(phys_addr)`**: Translates a physical address to a kernel virtual address based on the system's `KERNOFFSET`.
*   **`dki.allocator`**: A standard `std.mem.Allocator` implementation that uses `kmem_alloc` and `kmem_free`. Use this for idiomatic Zig collections.
*   **`dki.kmem_map(ptr, size)`**: Maps a user-space buffer into kernel space for I/O operations.

### Logging
*   **`dki.log(fmt, args)`**: A safe wrapper for the kernel `printf`. It uses Zig's compile-time format checking and ensures null-termination.
    ```zig
    dki.log("Device initialized: {} bytes\n", .{size});
    ```

### FFI & Calling Conventions
All functions called by the Prex kernel or loader (e.g., `open`, `read`, `probe`) **MUST** use the C calling convention:
```zig
fn my_read(dev: c.device_t, buf: [*]c_char, n: *usize, blk: c_int) callconv(.c) c_int { ... }
```

---

## 4. Architecture Specifics

The build system (`mk/zig.mk`) automatically tunes the Zig compiler for each supported architecture.

### ARM (EABI / Thumb)
*   **Target**: `arm-freestanding-eabi` or `thumb-freestanding-eabi`.
*   **Memory Helpers**: `dki.zig` provides AEABI helper implementations (`__aeabi_memcpy`, etc.) required by the ARM EABI for freestanding modules. These are implemented manually to avoid recursive calls back into themselves.

### RISC-V (RV32IMA)
*   **Target**: `riscv32-freestanding-none`.
*   **Floating Point**: Forced to soft-float (`generic_rv32+m+a`) to match the kernel's ABI. Zig drivers will not use floating-point registers.

### x86 (i386)
*   **Target**: `x86-freestanding-none`.
*   **Instruction Set**: Vector extensions (SSE, AVX, etc.) are explicitly disabled to prevent "Invalid Opcode" traps, as the Prex kernel does not enable or save/restore these registers during context switches.

---

## 5. Best Practices

### Null Termination
Zig string literals are not null-terminated by default unless specified. When passing names to `device_create`, use the `[*:0]const u8` type or standard Zig literals which are automatically converted by the `dki` wrapper.

### Runtime DevOps Initialization
Some Prex loaders (especially on ARM and x86) may have issues resolving multiple static relocations in the same data slot. It is highly recommended to initialize your `DevOps` function pointers inside your `init` function rather than statically in the struct.

### Error Handling
Use `dki.toCError(err)` to convert Zig errors into the positive `errno` integers expected by the Prex kernel.

---

## 6. Building and Verification

1.  Place your `.zig` file alongside the existing `.c` file (e.g., `ramdisk.zig` next to `ramdisk.c`).
2.  Update the `Makefile.inc` to use the `select_src` macro:
    ```makefile
    SRCS-$(CONFIG_MYDEV)+= $(call select_src,dev/path/mydev)
    ```
3.  Build the system:
    ```bash
    LC_ALL=C make
    ```
4.  Verify using QEMU:
    Check the boot logs to ensure your driver logs its initialization message.
