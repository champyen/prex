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

## 4. Object-Oriented Layout-Compatible Wrapper Pattern

- **Layout-Compatible `extern struct` Wrapper**: For complex or intrusive C structures (e.g., linked lists, queues, trees), define a layout-compatible `extern struct` in Zig. This allows defining inline object-oriented methods directly on the structure while maintaining binary compatibility with the underlying C library representation.
- **Type-Safe Intrusive Traversal**: Use `@fieldParentPtr` within the wrapper methods to resolve parent struct pointers from embedded fields, removing the need for manual pointer arithmetic, offsets, or unsafe casts at call sites.
- **Wrapper Design Guidelines**:
  - Declare the wrapper as an `extern struct` to guarantee that the field order and alignments match the C ABI.
  - Keep methods `inline` so that compiler optimizations compile them down to direct field accesses, avoiding call overhead.
  - Leverage native Zig optional pointers (`?*Self`) for safety and compile-time checks, ensuring they correspond exactly to nullable C pointers in the ABI.

### Concrete Example: Intrusive `List` Wrapper

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
    pub inline fn first(self: *List) ?*List {
        return self.next;
    }
    pub inline fn nextNode(self: *List) ?*List {
        return self.next;
    }
    pub inline fn entry(self: *List, comptime ParentType: type, comptime field_name: []const u8) *ParentType {
        const raw_self: *c.struct_list = @ptrCast(self);
        return @fieldParentPtr(field_name, raw_self);
    }
};
```

- **Clean Call Sites**: Cast the address of a C struct's field to a pointer of the layout-compatible Zig wrapper using `@ptrCast`, and call methods directly on it. Use `entry` for safe traversal:
  ```zig
  const p_link: *ffi.List = @ptrCast(&p.p_link);
  p_link.remove();
  head.insert(p_link);

  // Retrieve parent container:
  const parent_proc = p_link.entry(ffi.Proc, "p_link");
  ```

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

---

## 7. Packed Structs for Bit-Field Assignments & Registers

- **Use `packed struct` with Backing Integer Types**: Instead of manual bitwise shifts (`>>`, `<<`) and bitwise masking (`&`, `|`) to parse or construct register values, relocation fields, or hardware flags, define a `packed struct(T)` where `T` is the exact unsigned integer width (e.g., `u32`, `u16`, `u8`).
- **Bi-directional Casting via `@bitCast`**: Convert raw word values or arrays directly to/from the packed struct representation using `@bitCast`. This guarantees compile-time size matching and provides a type-safe, clean interface to individual bit fields.
- **Handling Signed Offsets & Sign Extensions**: Reconstruct sign-extended offset structures using a matching backing layout. Let fields align naturally with their widths, allowing `@bitCast` to seamlessly map the structure into a signed integer (`i32` or similar) for arithmetic.

### Example: Relocation Header Fields (ELF Info)

Instead of manually extracting indices and types with shifts:
```zig
const sym = r.r_info >> 8;
const r_type = r.r_info & 0xff;
```

Use a packed struct to represent the standard ELF `r_info` layouts:
```zig
const RelInfo = packed struct(u32) {
    type: u8,
    sym: u24,
};

// Access cleanly using @bitCast
const rel_info = @as(RelInfo, @bitCast(r.r_info));
const sym_idx = rel_info.sym;
```

### Example: Hardware Registers & Relocation Bitfields (ARM Branch Offset)

Instead of manually masking, shifting, and writing complex bit combinations:
```zig
var addend: u32 = where[0] & 0x00ffffff;
if ((addend & 0x00800000) != 0) {
    addend |= 0xff000000;
}
const tmp: u32 = sym_val - @intFromPtr(where) + (addend << 2);
where[0] = (where[0] & 0xff000000) | ((tmp >> 2) & 0x00ffffff);
```

Define packed instruction and offset layouts:
```zig
const ArmBranchInstruction = packed struct(u32) {
    imm24_val: u23,
    imm24_sign: u1,
    opcode: u8,
};

const ArmBranchOffset = packed struct(u32) {
    _pad: u2 = 0,
    imm24_val: u23,
    imm24_sign: u1,
    sign_extension: u6,
};

// Read instruction bits type-safely:
const inst: ArmBranchInstruction = @bitCast(where[0]);

// Decode sign-extended addend via @bitCast to signed integer:
const offset_struct = ArmBranchOffset{
    .imm24_val = inst.imm24_val,
    .imm24_sign = inst.imm24_sign,
    .sign_extension = if (inst.imm24_sign == 1) @as(u6, 0x3f) else 0,
};
const addend: i32 = @bitCast(offset_struct);

// Perform arithmetic safely:
const tmp: i32 = @bitCast(
    @as(u32, @bitCast(sym_val)) - @as(u32, @intCast(@intFromPtr(where))) + @as(u32, @bitCast(addend)),
);

// Re-encode into the target instruction:
const new_offset = @as(ArmBranchOffset, @bitCast(tmp));
var new_inst = inst;
new_inst.imm24_val = new_offset.imm24_val;
new_inst.imm24_sign = new_offset.imm24_sign;
where[0] = @bitCast(new_inst);
```
