# Guidelines for Migrating C Codebases to Idiomatic Zig in Systems Programming

This document defines best practices for refactoring legacy C modules to idiomatic, type-safe Zig in bare-metal, embedded, and operating systems development.

---

## 1. Unified Compilation Architecture & Module Boundaries

- **Single Root Module**: Standalone binaries, libraries, or modules should build only a single root Zig file (e.g. `main.zig`) in the build configuration. Sub-modules (representing specific features, files, or subsystems) must be imported directly inside the root file via `@import(...)`.
- **Comptime Force Evaluation**: To prevent the compiler from optimizing out unused sub-modules and their C-ABI `export` functions, always reference imports in a `comptime` block inside the root file:
  ```zig
  const submodule = @import("submodule.zig");
  comptime {
      _ = submodule;
  }
  ```
- **Eliminate `callconv(.c)` for Internal Functions**: Functions called strictly between Zig modules within the same compilation unit must use standard Zig calling conventions. Reserve `callconv(.c)` and `export` strictly for external C callbacks, assembly entry points, or linker-exported entry symbols.
- **Centralized FFI Module (`ffi.zig`)**: Consolidate all `@cImport` calls, C global getters/setters, and raw pointer castings in a single `ffi.zig` file to act as the boundary gateway.

---

## 2. Structured Library Namespaces

Logic modules must not access raw, monolithic C namespaces directly. Instead, split standard libraries and system call frameworks into distinct, type-safe namespaces:

- **Memory Allocations**: Route allocations through a safe library namespace (e.g. `prog.stdlib.malloc`).
- **Error Constants**: Access system errors (e.g., `EINVAL`, `ENOMEM`) from kernel/OS headers via a unified error namespace (e.g. `prog.errno.EINVAL`) to avoid hardcoded architectural discrepancies.
- **System Calls**: Consolidate OS/kernel calls under a kernel namespace (e.g. `task.prex.*`).

---

## 3. Idiomatic C-to-Zig Error Handling

- **Error Unions (`!T`)**: Map C-style integer return codes to native Zig error sets (e.g., `error.OutOfMemory`, `error.InvalidArgument`). 
- **Error Propagation (`try`)**: Use `try` for propagation across internal functions instead of manual C-style `if (err != 0) return err;` branches.
- **Automatic Resource Cleanup (`errdefer`)**: Utilize `errdefer` to automate cleanup of resources (e.g., freeing buffers, releasing locks, closing descriptors) on error paths, eliminating manual `goto`-style cleanups.
- **Boundary Error Conversion**: At top-level C-ABI entry points, catch Zig errors and map them back to positive POSIX errno integers using error conversion wrappers (`catch |err| return toCError(err)`).

---

## 4. Object-Oriented Layout-Compatible Wrapper Pattern

For complex or intrusive C structures, define layout-compatible `extern struct` wrappers in Zig:

- **Methods on extern struct**: Declaring methods directly on `extern struct` types allows object-oriented logic while maintaining binary compatibility with the underlying C representations.
- **Conditional Fields for Portability**: If a C struct contains platform-conditional fields (e.g. `#if defined(__arm__)`), declare matching conditional fields in the `extern struct` to guarantee identical size and alignment on all architectures:
  ```zig
  pub const Descriptor = extern struct {
      field_a: u32,
      conditional_ptr: if (comptime is_arm) ?*anyopaque else [0]u8 = .{},
  };
  ```
- **Type-Safe Intrusive Traversal**: Leverage `@fieldParentPtr` within inline wrapper methods to cleanly navigate intrusive containers (like linked lists or trees) without manual pointer math or unsafe casts.

---

## 5. Memory Allocation & Bounded Slices

- **Bounded Zeroed Allocations**: Define generic allocation helpers (e.g. `allocZeroed`) that wrap raw allocator output into type-safe, correctly aligned, bounded slices (`[]u8`) and initialize them via `@memset`, avoiding manual casting at call sites.
- **Array-to-Slice Wrapping**: Always wrap raw buffers into bounded slices (`buf[0..len]`) immediately upon receipt from C interfaces to enforce memory bounds checking.

---

## 6. Packed Structs for Bit-Field Assignments & Registers

Instead of manual bitwise shifts (`>>`, `<<`) and bitwise masking (`&`, `|`) to parse or construct registers, bitfields, or hardware headers, define a `packed struct(T)` where `T` is the exact backing integer width.

- **Bi-directional Casting via `@bitCast`**: Convert raw word values or arrays directly to/from the packed struct representation using `@bitCast` to ensure compile-time size matching.
- **Sign Extensions**: Reconstruct sign-extended offset structures using a matching backing layout, allowing `@bitCast` to seamlessly map the structure into a signed integer for arithmetic.

### Example: Relocation Header Fields (ELF Info)
```zig
const RelInfo = packed struct(u32) {
    type: u8,
    sym: u24,
};

const rel_info = @as(RelInfo, @bitCast(r.r_info));
const sym_idx = rel_info.sym;
```

### Example: Symbol Attributes (ELF Symbol Info)
```zig
pub const SymInfo = packed struct(u8) {
    type: u4,
    bind: u4,
};

const info: SymInfo = @bitCast(sym.st_info);
if (info.bind == STB_WEAK) { ... }
```
