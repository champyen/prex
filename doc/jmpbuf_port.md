# Portability Abstraction: Stack Pointer Extraction from `jmp_buf`

This document details the design and rationale for introducing the architecture-dependent `_JB_SP` macro inside `<setjmp.h>` to resolve a fatal, MMU-specific user-space boot crash during `fork()` thread initialization in Prex+.

---

## 1. The Bug: Store/AMO Page Fault at `0xfffffffc`

During early boot in MMU mode, the `init` process printed `init: booting`, called `vfork()`, and immediately crashed in the child thread with a `Store/AMO page fault` at virtual address `0xfffffffc` with stack pointer `sp = 0xfffffff0`.

### Root Cause Analysis
1.  Prex implements `fork()` in user-space `libc` (`usr/lib/posix/process/fork.c`) using `setjmp(__fork_env)` in the parent thread, creating a new thread `t`, and calling `thread_load(t, __child_entry, NULL)` with a `NULL` stack pointer.
2.  In `__child_entry` (`fork.c`), the child thread immediately executes `longjmp(__fork_env, 1)` to restore the parent's register state (including `sp` and `ra`) and return `1` from `setjmp`.
3.  Because `thread_load` was called with `stack = NULL`, the kernel initialized the child thread's user stack pointer (`u->sp`) to `0`.
4.  When the child thread started in user mode at `__child_entry`, the compiler-generated C function prologue executed:
    ```assembly
    addi sp, sp, -16    # sp becomes 0xfffffff0
    sw   ra, 12(sp)     # Tries to write to 0xfffffffc
    ```
5.  **NOMMU Luck:** In NOMMU mode, writing to the out-of-bounds physical address `0xfffffffc` succeeds silently without a trap due to physical address wrap-around. The next instruction executes `longjmp` and restores the valid parent `sp` before anything fails.
6.  **MMU Failure:** In MMU mode, `0xfffffffc` is strictly protected kernel virtual space. The prologue write instantly triggers a `Store/AMO page fault` user trap, crashing the child thread *before* it can execute `longjmp` to restore its stack!

---
## 2. The Solution: Pre-loading Stack Pointer

To prevent this page fault, the child thread must start with a valid, fully-mapped stack pointer at its very first instruction (`__child_entry`).

The parent thread can extract its own valid stack pointer from `__fork_env` (which is a `jmp_buf` containing saved registers) and pass it to the child via `thread_load`.

```c
/* Load valid parent stack pointer instead of NULL */
thread_load(t, __child_entry, parent_sp);
```

---

## 3. The Portability Problem: Opaque `jmp_buf` Layout

`usr/lib/posix/process/fork.c` is a portable POSIX library file shared by all target platforms. However, `jmp_buf` is an **opaque, architecture-dependent array** of saved registers. The stack pointer is saved at completely different offsets and register indices on different CPU architectures:

### RISC-V
In `usr/arch/riscv/setjmp.S`:
```assembly
ENTRY(setjmp)
    sw ra, 0(a0)
    sw sp, 4(a0)     # sp is saved at offset 4 (Index 1)
```
*   Stack Pointer index is **`1`**.

### x86 (i386)
In `usr/arch/x86/setjmp.S`:
```assembly
ENTRY(setjmp)
    ...
    movl %esp, 8(%ecx)   # esp is saved at offset 8 (Index 2)
```
*   Stack Pointer index is **`2`**.

### ARM
In `usr/arch/arm/setjmp.S`:
```assembly
ENTRY(setjmp)
    ...
    str sp, [r0, #40]    # sp is saved at offset 40 (Index 10)
```
*   Stack Pointer index is **`10`**.

---

## 4. The Portability Macro: `_JB_SP`

To maintain clean POSIX portability in `fork.c` without introducing ugly architecture-specific `#ifdef` blocks inside library code, we introduced the architecture-dependent macro `_JB_SP` in `<setjmp.h>` representing the index of the stack pointer register inside `jmp_buf`:

*   **`include/riscv/setjmp.h`**:
    ```c
    #define _JB_SP 1
    ```
*   **`include/x86/setjmp.h`**:
    ```c
    #define _JB_SP 2
    ```
*   **`include/arm/setjmp.h`**:
    ```c
    #define _JB_SP 10
    ```

### Portable `fork.c` Implementation
Using `_JB_SP`, `fork.c` extracts the parent's stack pointer portably and robustly across all platforms:

```c
/* Extract parent stack pointer portably from jmp_buf */
void *parent_sp = (void*)((long*)__fork_env)[_JB_SP];

/* Load child thread with valid parent stack pointer */
thread_load(t, __child_entry, parent_sp);
```
