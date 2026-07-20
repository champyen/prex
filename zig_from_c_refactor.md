# Best Practices & Guidelines for Refactoring C Modules to Zig

This document summarizes the architectural considerations, design patterns, and C-FFI rules established during the porting and refactoring of userland servers (e.g., `usr/server/proc`) and kernel components in Prex from C to Zig.

---

## 1. Unified Compilation Architecture & Module Boundaries

- **Single Root Module**: For standalone servers or modules, compile only the root module (`proc.zig`) and any indispensable C glue (`proc_hash_tables.c`) in the `Makefile`. Sub-modules (`proc_pid.zig`, `proc_fork.zig`, etc.) should be imported directly inside the root file via `@import(...)`.
- **Eliminate `callconv(.c)` and `@export` for Internal Functions**: Functions called strictly between Zig modules within the same compilation unit should use standard Zig calling conventions without `@export` or `callconv(.c)`. Reserve `callconv(.c)` and `@export` strictly for external C callbacks or GCC link-time exported symbols.
- **Centralized FFI Module (`ffi.zig`)**: Maintain a single `ffi.zig` per module to consolidate `@cImport` of module-private C headers (e.g., `proc.h`), C global getters/setters (`get_curproc()`), and casting utilities.

---

## 2. Structured Library Namespaces (`prog` & `task`)

Userland modules must import the central `@import("prog")` and `@import("task")` modules instead of accessing a monolithic, raw `c` namespace:

- **Memory**: `prog.stdlib.malloc`, `prog.stdlib.free`
- **Error Constants**: `prog.errno.ENOMEM`, `prog.errno.EINVAL`, `prog.errno.ESRCH`
- **Signal Constants**: `prog.signal.SIGCHLD`, `prog.signal.SIGINT`
- **Termios / Ioctl**: `prog.termios.TIOCGPGRP`, `prog.termios.TIOCSETSIGT`
- **IPC Messages & Headers**: `prog.ipc.proc`, `prog.ipc.exec`, `prog.ipc.ipc`
- **Kernel System Calls**: `task.prex.task_self`, `task.prex.msg_send`, `task.prex.exception_raise`

---

## 3. Idiomatic C-to-Zig Error Handling

- **Internal Error Unions (`!T`)**: Replace internal functions that return C integer errno values (`c_int`) with native Zig error unions (`!void`, `!task.prex.pid_t`). Use standard POSIX-aligned error set names (`error.OutOfMemory`, `error.InvalidArgument`, `error.NotFound`, `error.PermissionDenied`, `error.ResourceLimit`, `error.NoChildProcesses`).
- **Error Propagation (`try`)**: Propagate errors across internal function calls using `try` instead of manual `if (err != 0) return err;`.
- **Automatic Resource Cleanup (`errdefer`)**: Replace manual cleanup flags or duplicate `free()` calls with `errdefer prog.stdlib.free(ptr)`.
- **Boundary Error Conversion (`toCError`)**: At top-level C-ABI message dispatch handlers, map Zig error sets back to positive POSIX errno integers using `ffi.catchToCError(...)` or `catch |err| return ffi.toCError(err)`.

```zig
// Example: Top-level message handler converting Zig error union to C errno
fn proc_setpgid(msg: *ffi.Msg) callconv(.c) c_int {
    const pid_val = ffi.msgData(task.prex.pid_t, msg.data[0]);
    const pgid_val = ffi.msgData(task.prex.pid_t, msg.data[1]);
    return ffi.catchToCError(pid.sys_setpgid(pid_val, pgid_val));
}
```

---

## 4. Object-Oriented Intrusive Lists

- **Intrusive `List` Layout-Compatible Type**: Define an `extern struct` layout-compatible with `c.struct_list` (containing `next: ?*List` and `prev: ?*List`) with inline methods: `init()`, `insert()`, `remove()`, `empty()`, `first()`, `nextNode()`, and `entry()`.
- **Type-Safe `entry` Traversal**: Implement `entry` using `@fieldParentPtr` internally so call sites don't need manual pointer arithmetic or casting.

```zig
pub const List = extern struct {
    next: ?*List = null,
    prev: ?*List = null,

    pub inline fn init(self: *List) void {
        self.next = self;
        self.prev = self;
    }
    pub inline fn insert(self: *List, node: *List) void {
        node.next = self.next;
        node.prev = self;
        self.next.?.prev = node;
        self.next = node;
    }
    pub inline fn remove(self: *List) void {
        self.prev.?.next = self.next;
        self.next.?.prev = self.prev;
    }
    pub inline fn empty(self: *List) bool {
        return self.next == self;
    }
    pub inline fn first(self: *List) *List {
        return self.next.?;
    }
    pub inline fn nextNode(self: *List) *List {
        return self.next.?;
    }
    pub inline fn entry(self: *List, comptime ParentType: type, comptime field_name: []const u8) *ParentType {
        const raw_self: *c.struct_list = @ptrCast(self);
        return @fieldParentPtr(field_name, raw_self);
    }
};
```

- **Clean Call Sites**: Cast C struct fields using `@ptrCast` (e.g., `const p_link: *ffi.List = @ptrCast(&p.p_link);`) and call methods directly (`p_link.remove()`, `head.insert(p_link)`).

---

## 5. Memory Allocation & Bounded Slices

- **Slice-Based Allocator Wrapper (`allocZeroed`)**: Eliminate repeated `@ptrCast`, `@alignCast`, and `@memset` blocks by using a generic helper `allocZeroed(comptime T: type) ?*T` that allocates via `malloc`, casts to `*T`, wraps the buffer in a bounded slice `[0..@sizeOf(T)]`, and zeroes it via `@memset`.

```zig
pub fn allocZeroed(comptime T: type) ?*T {
    const mem = prog.stdlib.malloc(@sizeOf(T)) orelse return null;
    const ptr: *T = @ptrCast(@alignCast(mem));
    const slice: []u8 = @as([*]u8, @ptrCast(ptr))[0..@sizeOf(T)];
    @memset(slice, 0);
    return ptr;
}
```

- **Safe Buffer Slices**: Wrap array/buffer outputs in bounded slices (e.g., `const slice = buf[0..@intCast(n)]`).

---

## 6. C Header Integration & `@cImport` Pitfalls

- **No Hardcoded Constants**: Never re-define C constants (such as `PID_MAX`, `TIOCGPGRP`, `ID_MAXBUCKETS`) as hardcoded numbers in Zig files. Always import them from C headers (`c.PID_MAX`, `prog.termios.TIOCGPGRP`).
- **Bitwise Shifts in C Macros & `_IOC`**: Bitwise shift macros in C preprocessors (such as `_IOC` in `include/sys/ioctl.h`) must explicitly cast all operands to `(u_long)`:
  ```c
  #define _IOC(inout, group, num, len) ((u_long)(inout) | ((u_long)((len) & IOCPARM_MASK) << 16) | ((u_long)(group) << 8) | (u_long)(num))
  ```
  Otherwise, Zig's `@cImport` will translate bit shifts on `0x80000000U` into invalid signed 32-bit integer operations that fail compilation on 32-bit target architectures.
