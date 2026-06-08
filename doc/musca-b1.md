# Prex+ ARM Musca-B1 (Cortex-M33) BSP Support

This document describes the design and implementation of the Prex+ Board Support Package (BSP) for the ARM Musca-B1 dual-core Cortex-M33 platform. It details how ARMv8-M mainline architectural features are utilized and how position-independent Execute-in-Place (XIP) memory models are integrated into Prex+.

---

## 1. ARMv8-M / Cortex-M33 Hardware Features

The Cortex-M33 processor is based on the 32-bit ARMv8-M Mainline architecture. The key features of this CPU relevant to the Prex+ implementation include:

1.  **TrustZone for ARMv8-M:**
    *   Provides hardware-enforced isolation between **Secure (S)** and **Non-Secure (NS)** states.
    *   Execution transitions from Secure to Non-Secure mode can be initiated using standard branch instructions (`BXNS`, `BLXNS`), while transitions from Non-Secure to Secure mode must go through specific **Secure Gateway (SG)** instructions.
    *   The **Security Attribution Unit (SAU)** and **Implementation-Defined Attribution Unit (IDAU)** configure the security attributes of memory regions.
2.  **Dual Stack Pointer Architecture:**
    *   Cortex-M33 features separate stack pointers: the **Main Stack Pointer (MSP)** (used for exception handling and kernel execution) and the **Process Stack Pointer (PSP)** (used for user thread execution).
    *   Under TrustZone, both stack pointers are duplicated for the Secure and Non-Secure states (giving Secure MSP, Secure PSP, Non-Secure MSP, and Non-Secure PSP).
3.  **Execute-in-Place (XIP) Execution:**
    *   Cortex-M microcontrollers frequently execute code directly from flash memory (such as QSPI Flash) to conserve internal SRAM space.
4.  **Hardware Exception Frame stacking:**
    *   Upon entering an exception or interrupt, the hardware automatically stacks basic registers (`r0-r3`, `r12`, `lr`, `pc`, `xPSR`) to the active stack.

---

## 2. Prex+ Design and Architecture Decisions

To support the ARM Musca-B1 platform in a No-MMU configuration while maintaining the security, isolation, and efficiency of Prex+, the following design choices were adopted:

### A. TrustZone & Security Partitioning
*   **Secure State Kernel:** The Prex+ kernel and bootloader run in the **Secure** state, granting them full control over system configuration, interrupt routing, and hardware peripherals.
*   **Non-Secure State User Tasks:** User tasks and servers run in the **Non-Secure** state.
*   **SAU Initialization:** During machine startup, [machdep.c](../bsp/hal/arm/musca-b1/machdep.c) initializes the **Security Attribution Unit (SAU)** via `sau_init()` to mark Flash and SRAM regions partitioned for Non-Secure execution.
*   **Exception Return State:** Transitions between user space (Non-Secure Thread Mode) and kernel space (Secure Handler Mode) are handled via custom `EXC_RETURN` codes (e.g., `0xFFFFFFF9`).

### B. Stack Separation & Exception Frames
*   **MSP / PSP Isolation:** The kernel runs on the Main Stack Pointer (MSP), while user-space threads execute on the Process Stack Pointer (PSP).
*   **Registers Frame Construction:** 
    *   When an exception occurs (such as an SVCall system call or a SysTick timer tick), the hardware automatically pushes the standard frame (`r0-r3`, `r12`, `lr`, `pc`, `xPSR`).
    *   The exception vector handlers in [locore.S](../bsp/hal/arm/arch/armv8-m/locore.S) (`syscall_entry`, `interrupt_entry`) then push the remaining software-saved registers (`r4-r11`) to build the complete `struct cpu_regs` structure defined in [context.h](../bsp/hal/arm/include/context.h).
*   **System Call Passing:** The assembly dispatcher `syscall_entry` in [locore.S](../bsp/hal/arm/arch/armv8-m/locore.S) directly passes the address of this completed register frame pointer on the stack to `syscall_handler` in [sysent.c](../sys/kern/sysent.c).

### C. Position-Independent (PIC/ROPI) QSPI Flash XIP Loading
Since the platform executes code directly in Flash (Execute-in-Place) and does not feature an MMU for page translation:
1.  **Compiler Options:** All user space binaries are compiled using GCC flags enabling position independence:
    *   `-fpic`
    *   `-msingle-pic-base` (restricts GOT base to a fixed register)
    *   `-mpic-register=r9` (assigns the `r9` register to hold the GOT base address)
    *   `-mno-pic-data-is-text-relative` (forces variables to be referenced relative to the GOT base, not the PC)
2.  **Separate Segment Loading:** 
    *   In the bootloader ([elf.c](../bsp/boot/common/elf.c)) and kernel memory loader ([vm_nommu.c](../sys/mem/vm_nommu.c) via `vm_load`), the read-only sections (`.text` and `.rodata`) are mapped directly to their locations in QSPI Flash without copying.
    *   The writable sections (`.data`, `.bss`, and the Global Offset Table `.got`) are relocated to SRAM.
3.  **Dynamic GOT Relocation:** 
    *   The bootloader and user-space exec server resolve GOT references at load time.
    *   Symbol addresses in the GOT table residing in SRAM are relocated by resolving their relocations (`R_ARM_GOT_BREL` and `.rel.data` / `R_ARM_ABS32`).
    *   To prevent writing to read-only Flash, writes targeting segments mapped to QSPI Flash are filtered out during relocation resolution.
4.  **Register `r9` Management:** 
    *   The thread's GOT base address is tracked in `task->got_base` under `CONFIG_ARMV8M` in [task.c](../sys/kern/task.c).
    *   At thread load time, [thread_load.c](../usr/lib/prex/syscalls/thread_load.c) captures the active `r9` register in user space and passes it via the `thread_setup` system call.
    *   During context switches, the register `r9` is naturally saved and restored as part of the `r4-r11` context in [locore.S](../bsp/hal/arm/arch/armv8-m/locore.S).

### D. Memory Allocator Bounds
*   **Flash Protection:** Because user-space code executes in QSPI Flash, the system must ensure the page allocator does not attempt to recycle or manage Flash addresses as dynamic RAM.
*   **Page Allocator Verification:** In [page.c](../sys/mem/page.c), `page_free()` is updated to check if the target physical address falls within the usable RAM boundaries using `page_is_ram()`. Any attempt to free an address outside usable RAM (such as Flash) is ignored.

### E. Handler-to-Thread Escape in Idle Loop
*   In the ARMv8-M architecture, the CPU cannot switch back to Thread Mode while inside Handler Mode unless it performs an exception return.
*   **Idle loop escape:** If the system enters the idle loop (`machine_idle` in [machdep.c](../bsp/hal/arm/musca-b1/machdep.c)) from Handler Mode (i.e. if `ipsr != 0`), it constructs a dummy exception frame on the stack and executes an exception return (`bx lr` with `EXC_RETURN` = `0xFFFFFFF9`) to drop the CPU back to Thread Mode. This ensures the CPU enters the low-power `wfi` state correctly and does not remain stuck in Handler Mode.

### F. Zone-Based Memory Allocation & Address Translation
To manage physical RAM under the TrustZone-M memory split:
1.  **Zone Classification:** Memory is classified into two distinct zones:
    *   `PAGE_ZONE_SECURE`: Reserved for the Secure kernel, bootloader, kernel heap, and drivers.
    *   `PAGE_ZONE_NONSECURE`: Allocated dynamically for user tasks and servers.
2.  **Page Allocator Integration:** [page.c](../sys/mem/page.c) implements `page_alloc_zone(size, zone)`. 
    *   `page_alloc(size)` is a backward-compatible wrapper that requests pages from the `PAGE_ZONE_SECURE` pool.
    *   [vm_nommu.c](../sys/mem/vm_nommu.c) explicitly requests pages from `PAGE_ZONE_NONSECURE` when creating tasks and loading segment structures.
3.  **Address Aliasing and Translation:**
    *   The kernel's page allocator tracks all physical RAM using its canonical Secure addresses (`0x3xxxxxxx`).
    *   When mapping memory to user space, the VM manager translates these tracking addresses to their Non-Secure aliases (`0x2xxxxxxx`) by clearing bit 28 (`pa & ~0x10000000`).
4.  **Copyin/Copyout Protection:** The kernel uses `LDRT` (Load Unprivileged) and `STRT` (Store Unprivileged) in copy-in and copy-out helpers to prevent unprivileged user tasks from tricking the Secure kernel into accessing Secure memory regions, which triggers an immediate hardware **SecureFault**.

---

## 3. Memory Layout Configuration

The physical memory parameters configured in [musca-b1.base](../conf/arm/musca-b1.base) map the segments between QSPI Flash and System SRAM as follows:

### A. BOOTIMG_BASE (0x1001ffbc)
*   **Purpose:** Specifies the starting memory address in Flash where the system archive (`tmp.a`) is located.
*   **Derivation:**
    1. The bootloader executable (`bootldr`) executes from Flash (`LOADER_TEXT` = `0x10000000`).
    2. During the image packing process (configured in [image.mk](../mk/image.mk)), the bootloader is padded to exactly `131,004` bytes (`128KB - 68 bytes`) using `dd`.
    3. `0x10000000` + `131,004` bytes (`0x1ffbc` in hex) places the start of the concatenated system archive `tmp.a` at exactly `0x1001ffbc`.
    4. Therefore, `BOOTIMG_BASE` is defined as `0x1001ffbc` so the bootloader can locate and parse the archive directly in place.

### B. KERNEL_DATA (0x30004400)
*   **Purpose:** Establishes the starting address of the kernel's writable `.data` and `.bss` segments in Secure System SRAM.
*   **Usage & Derivation:**
    1. Secure System SRAM begins at `0x30000000` (`CONFIG_SYSPAGE_BASE`).
    2. The system page structures for NOMMU systems (containing vectors, interrupt stacks, sys mode stack, abort stack, and bootloader stack) occupy the first `16KB` (`0x4000` bytes), reserving the range `0x30000000 - 0x30004000`.
    3. The bootloader's own `.data` and `.bss` sections are loaded immediately following at `0x30004000` with `1KB` (`0x400` bytes) allocated for bootloader variables, utilizing memory up to `0x30004400`.
    4. Therefore, `0x30004400` is the first safe, aligned SRAM address for `KERNEL_DATA` to avoid memory conflicts.
    5. During load time, `load_elf` in [elf.c](../bsp/boot/common/elf.c) reads the kernel ELF segment headers and copies the `.data` segment from Flash directly to this destination address in SRAM.

### C. SRAM Partitioning (TrustZone 1:3 Split)
By default, the 512 KB physical System SRAM is partitioned at a **1:3 ratio** (128 KB Secure / 384 KB Non-Secure) to optimize RAM availability for user-space tasks and servers:

1.  **Secure SRAM Region (128 KB, `0x30000000 - 0x3001FFFF`):**
    *   **Syspage & Boot Info (`0x30000000 - 0x30004000`, 16 KB):** Reserved for system page structures, vectors, and bootloader variables/stacks.
    *   **Kernel Writable Memory (`0x30004400 - 0x3001FFFF`, ~111 KB):** Holds the kernel `.data`, `.bss`, heap, and Main Stack Pointer (MSP) stack.
2.  **Non-Secure SRAM Region (384 KB, `0x20020000 - 0x2007FFFF`):**
    *   Mapped to the Non-Secure alias address space.
    *   Configured as Non-Secure in the Security Attribution Unit (SAU) Region 2.
    *   Used dynamically by the VM allocator for user tasks and servers. Address translation maps user space pointers to this range, and unprivileged memory copy helpers (`copyin`, `copyout`) access these addresses safely.

*(Note: If debugging or memory protection resolution requires wider boundaries, the system supports a fallback **1:1 split** partitioning 256 KB Secure RAM from `0x30000000` to `0x3003FFFF` and 256 KB Non-Secure RAM from `0x20040000` to `0x2007FFFF`.)*
