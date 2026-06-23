# Zig Kernel Development Guide

Prex+ supports writing kernel core code in the Zig programming language. The Prex+ microkernel can be built entirely from Zig sources, with C and Zig coexisting as peer languages. This guide explains the kernel-side FFI architecture, the single-translation-unit build model, idiomatic kernel patterns, and how to extend the kernel in Zig.

---

## 1. Getting Started

### Prerequisites
*   **Zig Compiler**: Version 0.16.0 or higher.
*   **Target Architecture**: ARM (EABI/Thumb), x86, or RISC-V.

### Enabling Zig Kernel Support
Zig kernel compilation is enabled by default. To verify or change:
1.  Run `./configure` as usual.
2.  Ensure `CONFIG_ZIG_KRNL=y` is set in `conf/config.mk`.
3.  Ensure `#define CONFIG_ZIG_KRNL y` is present in `conf/config.h`.

To disable Zig kernel (revert to the C kernel):
1.  Set `CONFIG_ZIG_KRNL=n` in `conf/config.mk`.
2.  Set `/* #define CONFIG_ZIG_KRNL y */` (comment out) in `conf/config.h`.

---

## 2. Architecture: Single Translation Unit

Unlike drivers and apps (each compiled as a separate root), the **entire kernel core compiles as one Zig translation unit** rooted at `sys/kern/main.zig`.

```
sys/kern/main.zig   ← single root
    ├─ sys/kern/{device,exception,irq,sched,smp,sysent,system,task,thread,timer}.zig
    ├─ sys/ipc/{msg,object}.zig
    ├─ sys/sync/{cond,mutex,sem}.zig
    └─ sys/mem/{kmem,page,vm,vm_nommu}.zig
```

Each of the 18 kernel `.zig` files is wired in via a separate `--dep` module declaration in `mk/zig.mk`. They are imported as siblings, not roots. This delivers:
*   **Cross-module inlining** — `pub inline fn` methods on `Queue` and `List` propagate across all kernel files.
*   **Whole-kernel dead-code elimination** — unused helpers vanish at compile time.
*   **Comptime checks across the kernel** — e.g. `@sizeOf(ffi.hal.Thread) == @sizeOf(c.struct_thread)` validated at `ffi.zig` build time.
*   **One consolidated `@export` block** at the bottom of `main.zig` lists every C-ABI symbol the kernel exports to C HAL/DRV and the boot layer.

The C kernel files (`sys/kern/*.c`, `sys/ipc/*.c`, etc.) remain in the source tree as a parallel track. `select_kernel_src` in `mk/own.mk` automatically picks `.zig` when `CONFIG_ZIG_KRNL=y` and `.c` otherwise — they are not compiled together.

---

## 3. FFI Namespaces (`sys/ffi.zig`)

`sys/ffi.zig` is the single canonical place for type aliases, constants, and FFI bindings used by every kernel `.zig` file. Consumer files hoist the namespaces they need at the top:

```zig
const c = @import("c").c;
const ffi = @import("ffi");
const hal = ffi.hal;
const kern = ffi.kern;
const lib = ffi.lib;
const sync = ffi.sync;
const IntrusiveList = lib.IntrusiveList;
```

### `ffi.hal` — Hardware Abstraction Layer
*   **Bindings**: `machine_startup`, `clock_init`, `interrupt_*`, `mmu_*`, `context_*`, `spl*`, `copyin/out`, `flush_cache`, etc.
*   **C struct aliases** (for C-compatible function parameters and field types): `hal.Thread`, `hal.Task`, `hal.Device`, `hal.IRQ`, `hal.Timer`, `hal.Event`, `hal.Mutex`, `hal.Cond`, `hal.Sem`, `hal.List`, `hal.Queue`, `hal.Segment`, `hal.VmMap`, etc. These are direct aliases to the C `@cImport` types.
*   **Zig `Spinlock` struct** with inline `lock`/`unlock`/`lock_irq`/`unlock_irq` methods that call the broken-macro C shims from `<sys/spinlock.h>`.
*   **Constants**: `PAGE_SIZE`, `KERNOFFSET`, `USERLIMIT`, `NPRI`, `MINPRI`, `CTX_*`, `IMODE_*`, `INT_*`, `PRI_*`, `DFLSTKSZ`, `KSTACKSZ`, `MAX*`, etc.

### `ffi.kern` — Kernel Core Types
*   **Handle aliases**: `kern.TaskRef = c.task_t`, `kern.ThreadRef = c.thread_t`, `kern.DeviceRef`, `kern.ObjectRef`, `kern.MutexRef`, `kern.CondRef`, `kern.SemRef`, `kern.VmMapRef`, `kern.Pgd`, etc.
*   **C struct aliases**: `kern.Task`, `kern.Thread`.
*   **Zig extern structs with inline methods**: `kern.Device`, `kern.IRQ`, `kern.Timer` (with `comptime @sizeOf` asserts matching the C layout).
*   **Extern var**: `kern.kernel_task` (the global kernel task).
*   **Constants**: capability flags (`CAP_*`), task flags (`TF_*`), thread states (`TS_*`), sleep results (`SLP_*`), scheduling policies (`SCHED_FIFO`, `SCHED_RR`), VM options (`VM_*`), protection flags (`PROT_*`).
*   **`kern.Errno` namespace**: POSIX errno constants (`EINVAL`, `ENOMEM`, etc.) — used as return-value sentinels in Zig.

### `ffi.sync` — Synchronization Primitives
*   **Zig extern structs**: `sync.Event`, `sync.Mutex`, `sync.Cond`, `sync.Sem` — all use `lib.Queue` / `lib.List` for their linked-list fields and have inline `init`/`lock`/`unlock`/`isWaiting` methods. Layouts are validated against C via `comptime @sizeOf` asserts.
*   **Constants**: `MAXINHERIT`, `MAXSEMVAL`.
*   **C bindings**: `event_init`, `mutex_lock`, `mutex_unlock`, `cond_wait`, `cond_signal`, `sem_*`, etc.

### `ffi.mem` — Memory Management
*   **Zig extern structs**: `mem.Segment`, `mem.VmMap` (with `comptime @sizeOf` asserts).
*   **Constants**: `SEG_FREE`, `SEG_MAPPED`, `SEG_READ`, `SEG_WRITE`, `SEG_SHARED`.

### `ffi.lib` — Runtime + Intrusive Data Structures
*   **C runtime bindings**: `lib.memcpy`, `lib.memset`, `lib.memmove`, `lib.strlen`, `lib.strnlen`, `lib.strlcpy`, `lib.strncmp`, `lib.printf`, `lib.panic`.
*   **Zig data structures**:
    *   `lib.Queue` — `extern struct` with inline `init`, `isEmpty`, `insert`, `remove`, `enqueue`, `dequeue`, `first`, `nextNode`, `prevNode`, `entry`.
    *   `lib.List` — `extern struct` with inline list operations.
    *   `lib.IntrusiveQueue(T, Node, "field")` — comptime-validated type-safe helpers (`.node(p)`, `.parent(n)`) that work over a parent type `T` and a field of type `Node` (typically `lib.Queue` or `c.struct_queue`).
    *   `lib.IntrusiveList(T, Node, "field")` — same pattern for `lib.List`/`c.struct_list` fields.

### `ffi.kutil` — Kernel Utilities
*   `kutil.round_page(x)`, `kutil.trunc_page(x)` — page-aligned arithmetic.
*   `kutil.user_area(a)` — check if address is in user space.
*   `kutil.kvtop(va)`, `kutil.ptokv(pa)` — kernel-virtual ↔ physical address conversion.
*   `kutil.get_curthread()`, `kutil.get_curtask()` — current thread/task via SMP-aware fast path.
*   `kutil.cur_thread()`, `kutil.cur_task()` — non-optional variants.
*   `kutil.toReg(val)` — cast any value to a `kern.Register` (preserves both integer and pointer bit patterns).

### Other Subsystem Bindings
*   `ffi.smp`, `ffi.thread`, `ffi.sched`, `ffi.timer`, `ffi.irq`, `ffi.device`, `ffi.exception`, `ffi.msg`, `ffi.object`, `ffi.system`, `ffi.task`, `ffi.cond`, `ffi.mutex`, `ffi.sem`, `ffi.page`, `ffi.kmem`, `ffi.vm`, `ffi.deadlock` — function bindings grouped by kernel subsystem.

---

## 4. C-ABI Integration

### Single `@cImport` Root
`sys/c.zig` is the only `@cImport` declaration in the entire kernel:
```zig
pub const c = @cImport({
    @cDefine("KERNEL", "1");
    @cInclude("zig_kernel.h");
});
```

This is exposed to every kernel module as `--dep c`. Adding a new header only requires editing `sys/include/zig_kernel.h`.

### `sys/include/zig_kernel.h`
The header includes the full kernel C API and renames macros that Zig 0.16 cannot translate:
```c
#define curthread __broken_curthread
#define spinlock_lock __broken_spinlock_lock
#define event_init __broken_event_init
// ... (and #undef at the bottom)
```

These `__broken_*` names are then declared as `extern fn` in the Zig namespace, with inline-method wrappers (e.g. `ffi.hal.Spinlock.lock`) that call them.

### `sys/include/zig_helper.h`
Provides inline implementations that replace void-typed C macros (which Zig 0.16 mis-translates as `anyopaque`-returning functions). Examples: `deadlock_*`, `event_init`, `spinlock_*` (when `CONFIG_SMP` is disabled).

### `sys/lib/queue.zig` (C-ABI Bridge)
Zig 0.16's `@cImport` auto-generates method aliases on `c.struct_queue` (e.g. `c.struct_queue.remove` → `queue_remove`). The `c_export` struct in `sys/lib/queue.zig` provides the four C-ABI functions (`enqueue`, `dequeue`, `queue_insert`, `queue_remove`) that those auto-methods call. This is the only place in the kernel where a C-ABI bridge is required.

The c.struct_list type has the same auto-generated methods, but the kernel never calls them — `thread.zig` and `timer.zig` use local inline wrappers (`list_init`, `list_insert`, `list_remove`) that do direct field access on `*hal.List`. So no c_export-style bridge is needed for list.

---

## 5. Intrusive Data Structures

Prex+ uses intrusive linked lists and queues throughout the kernel (e.g. `struct thread` embeds a `struct list link` and a `struct queue sched_link`). Two type-safe wrapper patterns are provided:

### `lib.IntrusiveQueue(T, Node, "field")`
```zig
const Q = lib.IntrusiveQueue(kern.Thread, lib.Queue, "sched_link");
runq[pri].enqueue(Q.node(t));   // get a *Queue pointer to t's embedded sched_link
Q.parent(node);                  // walk back from a node pointer to the parent T
```
The `comptime` block validates at compile time that `T` actually has a field named `field_name`.

### `lib.IntrusiveList(T, Node, "field")`
Same pattern for `c.struct_list` / `lib.List` fields:
```zig
const L = lib.IntrusiveList(kern.Task, hal.List, "link");
const task = L.parent(n);
```

The `Node` type can be either `lib.Queue`/`lib.List` (Zig types with inline methods) or `c.struct_queue`/`c.struct_list` (C types). For C-typed nodes, prefer the Zig-typed version via `IntrusiveQueue(T, lib.Queue, "field")` to avoid the auto-dispatch path.

---

## 6. Design Patterns & Best Practices

### Robust Lock Handling with `defer` / `errdefer`
Spinlocks and the kernel lock are RAII-style. Always pair `sched.lock()` with `defer sched.unlock()` (or `errdefer` if early-exit on error is possible):
```zig
fn do_work(t: kern.ThreadRef) !void {
    sched.lock();
    defer sched.unlock();
    const s = hal.splhigh();
    defer hal.splx(s);
    // ... critical section ...
    if (bad) return kern.Errno.EINVAL;
}
```

### `orelse` for Sentinel Returns
Functions returning `?*T` (e.g. `kutil.get_curthread()`) use `orelse` to propagate an error sentinel:
```zig
const t = kutil.get_curthread() orelse return kern.Errno.ESRCH;
```

### Comptime Configuration
Use `comptime @hasDecl(c, "CONFIG_*")` for compile-time feature detection:
```zig
if (comptime @hasDecl(c, "CONFIG_SMP")) {
    smp.init_early();
}
```

### Per-File Convention
*   **Hoist only the namespace**, not individual types: `const hal = ffi.hal;` (not `const Thread = ffi.hal.Thread;`).
*   **Use namespaced access** in the body: `hal.Thread`, `kern.Errno.EINVAL`, `lib.IntrusiveQueue(...)`, `sync.Mutex`.
*   **Local aliases** are allowed for very frequent names: `const IntrusiveList = lib.IntrusiveList;`.
*   **Order const declarations alphabetically** within a file for diff stability.

### `extern struct` Discipline
*   Use `extern struct` for any struct that must share memory layout with a C struct (e.g. `hal.Thread` is `c.struct_thread`).
*   Validate layouts with `comptime { std.debug.assert(@sizeOf(MyZig) == @sizeOf(c.struct_c)); }` in `ffi.zig`.

### Zig `main.zig` Is the Only Root
Do not add `pub fn main()` or top-level `comptime { @export(...) }` blocks in any other kernel `.zig` file. Add the new symbol to `main.zig`'s `comptime { @export(...) }` block instead. Each kernel module exports its public API as plain `pub fn`; `main.zig` re-exports them at the C ABI as needed.

### Freestanding Constraints
The Prex+ kernel is **freestanding** — no `std.fs`, `std.os`, `std.io.getStdOut`, `std.net`.
*   **SAFE**: `std.mem`, `std.fmt`, `std.meta`, `std.atomic`, `std.debug.assert`, `std.debug.print`, `std.enums`, `std.builtin`.
*   **Use `lib.printf` for kernel output**, not `std.debug.print` (which may link to host I/O).

### Alignment
*   On noMMU ARM targets, the build system enables `+strict_align` automatically.
*   Always use `@alignCast()` when casting pointers between types with different alignment guarantees.
*   RISC-V is strict — unaligned struct fields will fail to compile.

### Floating Point
The kernel itself uses soft-float (no FPU). User applications can use hard-float where supported.

---

## 7. Adding a New Kernel Module

To add a new `foo.zig` to the kernel core (e.g. a new subsystem `sys/kern/foo.zig`):

1.  **Create `sys/kern/foo.zig`** with `pub fn init() callconv(.c) c_int { ... }` and any helpers.
2.  **Add `@import("foo_mod")` in `sys/kern/main.zig`** alongside the other `const foo = @import("foo_mod");` lines.
3.  **Add the module to `mk/zig.mk`** in the `ZIG_MODULES` list:
    ```make
    $(COMMON_DEPS) -Mfoo_mod=$(SRCDIR)/sys/kern/foo.zig $(ZIGFLAGS) \
    ```
4.  **Add the build entry in `sys/Makefile`**:
    ```make
    SRCS+=		$(call select_kernel_src,kern/foo) \
    ```
5.  **Call `foo.init()` in `main()`** of `sys/kern/main.zig` at the appropriate point in the boot sequence.
6.  **Add `@export(&foo.fn_name, ...)`** in the C-ABI export block at the bottom of `main.zig` if C HAL/DRV needs to call it.

---

## 8. Building and Verification

1.  Configure: `./configure --target=<arch> --cross-prefix=<prefix>`.
2.  Build: `make -j4`.
3.  Verify: `./verify_all.sh` — runs all 16 target/variant combinations (arm-qemu-virt, arm-raspi0, arm-integrator, x86-pc, arm-gba, riscv-qemu-virt, arm-musca-b1, each with mmu/nommu and SMP where applicable).

The Zig kernel is verified to produce identical observable behavior to the C kernel (same boot sequence, same syscalls, same QEMU shell prompt at the end of each test).

---

## 9. Migration Notes (C → Zig)

When porting a C file from the parallel C track (`sys/kern/foo.c`):

1.  **Copy the function signatures** verbatim. The Zig function's C-ABI surface must match the C version exactly.
2.  **Replace C `struct foo *` with `c.struct_foo`** (or its `ffi.*` alias if one exists).
3.  **Replace `c.queue_t` / `c.list_t` with `lib.Queue` / `lib.List`** in Zig-declared variables. C-typed fields keep their `c.struct_*` type.
4.  **Use `defer`/`errdefer`/`orelse`** instead of `goto cleanup;` chains and explicit `if (x == NULL) return -EINVAL;` guards.
5.  **Move the `comptime { @export(...) }` block** to `sys/kern/main.zig` (or, for HAL-internal symbols, leave it in the module if it remains a separate root in the build system).
6.  **Add the module** to `mk/zig.mk` and `sys/Makefile` as described in §7.
7.  **Verify with `./verify_all.sh`**. Pay attention to `nm sys/prex | grep ' U '` — undefined references that appear indicate a missing `@export` or a C symbol that should be removed.

The C file is left in the source tree as a fallback — `select_kernel_src` will pick the `.zig` version when `CONFIG_ZIG_KRNL=y`, otherwise the `.c` version.

---

## See Also

*   [Zig Driver Development Guide](zig_driver.md) — `dki.zig` API, static interface pattern
*   [Zig Application Development Guide](zig_app.md) — user-space `prex`/`posix` libraries
*   [Build Guide](build.md) — toolchain, configuration
*   [Source Tree](tree.md) — directory layout
