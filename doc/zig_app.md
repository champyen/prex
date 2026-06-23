# Zig Application Development Guide

Prex+ supports developing user-space applications in the Zig programming language. This guide explains how to write, build, and integrate both native real-time tasks and standard POSIX processes using idiomatic Zig.

---

## 1. Application Types

Prex+ provides two distinct personalities for Zig applications, each with a dedicated wrapper library:

| Personality | Library | Type | Purpose |
| :--- | :--- | :--- | :--- |
| **Native RT** | `prex` | Real-Time Task | High-priority tasks using microkernel APIs directly. No server dependencies. |
| **POSIX** | `posix` | UNIX Process | Standard applications using POSIX syscalls (routed via system servers). |

---

## 2. Configuration

To enable Zig user-space support:
1.  Run `./configure` for your target.
2.  Ensure `CONFIG_ZIG_USR=y` is set in `conf/config.mk`.
3.  Ensure `#define CONFIG_ZIG_USR y` is present in `conf/config.h`.

---

## 3. Library Features (prex & posix)

Both libraries provide a consistent set of core utilities:

### `allocator`
*   **Native RT**: A `std.mem.Allocator` that wraps `vm_allocate` and `vm_free`. It provides page-aligned memory directly from the kernel.
*   **POSIX**: A `std.mem.Allocator` that wraps standard C `malloc` and `free`.

### `print`
*   **Native RT**: Routes formatted output to the kernel diagnostic log via `sys_log`.
*   **POSIX**: Routes formatted output to standard output (FD 1) via the POSIX `write` call.

### `panic`
*   Handles Zig runtime errors.
*   **Native RT**: Triggers a microkernel `sys_panic`.
*   **POSIX**: Prints the error to `stderr` and exits the process with status 1.
*   **Usage**: You must declare `pub const panic = prex.panic;` (or `posix.panic`) in your root source file.

### `c`
*   Exposes the raw C API for the selected personality (e.g., `c.task_self()`, `c.getpid()`).

---

## 4. Writing a Native RT Task

Native tasks are built as standalone executables (`.rt`) and usually loaded at boot time.

**Example: `my_task.zig`**
```zig
const std = @import("std");
const prex = @import("prex");

// Required for Zig runtime safety
pub const panic = prex.panic;

export fn main(argc: i32, argv: [*][*:0]u8, envp: [*][*:0]u8) callconv(.c) i32 {
    _ = argc; _ = argv; _ = envp;

    prex.print("Hello from Zig RT Task!\n", .{});

    // Use raw kernel API via prex.c
    var ticks: u32 = 0;
    _ = prex.c.sys_time(&ticks);
    
    return 0;
}
```

**Makefile:**
```make
TASK=   my_task.rt
include $(SRCDIR)/mk/task.mk
```

---

## 5. Writing a POSIX Program

POSIX programs are standard UNIX processes linked against `libc.a`.

**Example: `my_prog.zig`**
```zig
const std = @import("std");
const posix = @import("posix");

pub const panic = posix.panic;

export fn main(argc: i32, argv: [*][*:0]u8, envp: [*][*:0]u8) callconv(.c) i32 {
    _ = argc; _ = argv; _ = envp;

    posix.print("My Process ID is: {}\n", .{posix.c.getpid()});
    
    // Allocate memory using the Zig allocator
    const buf = posix.allocator.alloc(u8, 1024) catch return 1;
    defer posix.allocator.free(buf);

    return 0;
}
```

**Makefile:**
```make
PROG=   my_prog
include $(SRCDIR)/mk/prog.mk
```

---

## 6. Build & Integration

### Source Selection
The build system automatically detects `.zig` files. If `my_app.zig` exists in a directory alongside a Makefile using `mk/task.mk` or `mk/prog.mk`, the system will compile it using the Zig compiler instead of looking for `my_app.c`.

### Registration
*   **RT Tasks**: Add to `TASKS+=` in `conf/etc/tasks.mk`.
*   **POSIX Programs**: Add to `FILES+=` in `conf/etc/files.mk`.

### Verification
Use the `./verify_all.sh` script to ensure your application works across different architectures (ARM, x86, RISC-V) and memory configurations (MMU/noMMU).

---

## 7. Technical Notes

### Alignment
Zig is strict about memory alignment. On noMMU ARM targets, the build system automatically enables `+strict_align` to prevent Data Aborts caused by unaligned memory access.

### Floating Point
User applications are currently built with soft-float support (`-mfloat-abi=soft`) to maintain compatibility across all Prex+ supported hardware.

### Relocation
On noMMU targets, POSIX programs are linked as relocatable objects (`ET_REL`) if `_RELOC_OBJ_:=1` is set in the makefile. The `exec` server handles the final relocation at runtime.

---

## 8. Extending User-Space Libraries

To support new kernel features or POSIX APIs in your Zig applications, you may need to extend the core wrapper libraries in `usr/zig/`.

### Adding C Headers
Both `prex.zig` and `posix.zig` use `@cImport` to expose the Prex+ C interface.
1.  Locate the `pub const c = @cImport({ ... });` block at the top of the file.
2.  Add the necessary header file (e.g., `@cInclude("sys/msg.h");`).

### Creating Type-Safe Wrappers
Avoid using the raw `c` namespace in your application logic. Instead, add a Zig-friendly wrapper to the library:
```zig
// In usr/zig/prex.zig
pub fn createTask(name: []const u8) !c.task_t {
    var task: c.task_t = 0;
    // Note: C functions expect null-terminated strings
    var buf: [16]u8 = undefined;
    @memcpy(buf[0..name.len], name);
    buf[name.len] = 0;
    
    const err = c.task_create(c.task_self(), &buf, &task);
    if (err != 0) return error.SystemError;
    return task;
}
```

### Extending the Allocator
If you need a specialized allocator (e.g., an arena or a pool), add it to the relevant library. 
*   **Recommendation**: Always provide a `std.mem.Allocator` interface to ensure compatibility with Zig's standard library collections.

### Error Mapping
If a new C API introduces unique error codes, update the `toCError` function in `prex.zig` or implement a similar mapping in `posix.zig` to maintain consistency between Zig errors and POSIX/Kernel status codes.

---

## See Also

*   [Zig Kernel Development Guide](zig_kernel.md) — kernel-side FFI, single-translation-unit model, intrusive data structures
*   [Zig Driver Development Guide](zig_driver.md) — `dki.zig` API, static interface pattern, interrupt handling
*   [Build Guide](build.md) — toolchain, configuration
