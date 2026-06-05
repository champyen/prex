# Detailed Implementation Plan: Position-Independent (PIC/ROPI) QSPI XIP Model (ARM Musca-B1 BSP)

This document outlines the complete architectural design and implementation steps for Prex+ support on the ARM Musca-B1 (Cortex-M33) board using a Position-Independent (ROPI/RWPI) Execute-in-Place (XIP) execution model. Under this design:
* Internal eFlash usage is entirely dropped.
* The system boots and executes all code directly from external QSPI Flash.
* Writable variables and stacks are allocated in SRAM.
* Parallel build (`make -j`) is fully preserved because user tasks do not require static address partitioning.

---

## 1. Memory and Execution Layout

User tasks are compiled as position-independent executables, allowing their code (`.text` / `.rodata`) to execute directly from their locations inside the OS archive (`tmp.a`) in QSPI Flash. The kernel executes in-place from QSPI Flash at a fixed link address.

### 1.1 Memory Allocation Table (Primary 1:3 Split)

By default, the 512 KB of physical System SRAM is partitioned at a **1:3 ratio** (128 KB Secure / 384 KB Non-Secure) to maximize RAM availability for the multiple user-space tasks.

| Component | Target Memory Region | Physical Address Range | Size | Access Type | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Bootloader (`bootldr`)** | QSPI Flash (Secure) | `0x10000000 - 0x10001FFF` | **8 KB** | Read-Only (XIP) | Boot entry vector and early stage loader. |
| **OS Archive (`tmp.a`)** | QSPI Flash (Secure) | `0x10002000 - 0x107FFFFF` | **~7.9 MB** | Read-Only | Contains the position-independent user tasks. |
| **Kernel Code (`prex+`)** | QSPI Flash (Secure) | `0x10002044 - ...` | **~24 KB** | Read-Only (XIP) | Runs in-place from Flash at a fixed link address. |
| **System Page (Syspage)** | System SRAM (Shared) | `0x30000000 - 0x30001FFF` | **8 KB** | Read-Write | Prex+ Syspage (Secure: `0x30000000` / NS: `0x20000000`). |
| **Kernel RAM** | System SRAM (Secure) | `0x30002000 - 0x3001FFFF` | **120 KB** | Read-Write | Kernel `.data`/`.bss`, heap, stack. |
| **NSC Veneers** | QSPI Flash (Callable) | `0x1001F000 - 0x1001FFFF` | **4 KB** | Read-Only (NSC) | Secure Gate veneers for system calls. |
| **User Tasks Code** | QSPI Flash (Non-Secure) | `0x00002000 + offset` | **Dynamic** | Read-Only (XIP) | Executes in-place directly from the archive in Flash. |
| **User Tasks RAM** | System SRAM (Non-Secure) | `0x20020000 - 0x2007FFFF` | **384 KB** | Read-Write | User `.data`/`.bss`, task stacks, heap. |

### 1.2 Alternative Fallback Plan (1:1 Split)
> [!NOTE]
> In case of unexpected development issues (e.g. alignment constraints, MPC controller resolution limits, or debugging tool issues with the 128KB boundary), the system will fallback to a **1:1 split** (256 KB Secure / 256 KB Non-Secure):
> * **Secure SRAM Range:** `0x30000000 - 0x3003FFFF` (Kernel RAM)
> * **Non-Secure SRAM Range:** `0x20040000 - 0x2007FFFF` (User Tasks RAM)

### 1.3 Boot and Relocation Sequence
1. **Power-On Reset:** The Cortex-M33 boots in Secure state with the SVTOR pointing to `0x10000000`.
2. **Bootloader Execution:** `bootldr` runs directly from QSPI Flash (`0x10000000`). It initializes the System SRAM MPC (Memory Protection Controller) to configure the 128 KB Secure / 384 KB Non-Secure boundary.
3. **Kernel Loading:** `bootldr` parses the kernel ELF.
   * Bypasses copying `.text`/`.rodata` (maps `m->text` directly to the kernel's text start inside the OS Archive at `0x10002044` in QSPI Flash).
   * Copies the kernel's `.data` section to Secure SRAM (`0x30002000`), and zero-fills `.bss`.
4. **User Tasks Loading:** `bootldr` parses each user task ELF.
   * Bypasses copying `.text`/`.rodata` (maps `m->text` directly to the task's offset in QSPI Flash at `0x00002000 + offset`).
   * Copies each task's `.data` section to Non-Secure SRAM (`0x20020000` range under 1:3 primary plan), and zero-fills `.bss`. **Each task's starting address in Non-Secure SRAM is aligned to a 4 KB page boundary** to simplify MPC configuration.
   * Sets the initial task context register `r9` (static base register) to point to the task's data segment in SRAM.
5. **Kernel Hand-off:** `bootldr` jumps to the kernel's Secure entry point in QSPI Flash (resolved entry at `0x10002401`). VTOR is pointed directly to the aligned vector table in QSPI Flash (`0x10002400`), and no vector table copy to SRAM is performed.
6. **Task Launch:** The Secure kernel initializes the SAU, sets up the security boundaries, and branches to user tasks via `BXNS` with `r9` loaded with the task's SRAM base.

---

## 2. Memory Architecture & HAL Design

To enforce memory zoning (allocating kernel structs in Secure SRAM and user task segments in Non-Secure SRAM) without modifying generic allocation routines, we implement a HAL-mediated memory zone classification architecture.

### 2.1 Zone Definitions (`include/sys/page.h`)
We define flags to represent the target security domain:
```c
#define PAGE_ZONE_SECURE      0  /* Kernel RAM (Secure) */
#define PAGE_ZONE_NONSECURE    1  /* User Tasks RAM (Non-Secure) */
#define PAGE_ZONE_ANY         2  /* Fallback / Generic */
```

### 2.2 HAL Memory Query Interface (`include/hal.h`)
The core page allocator queries physical block attributes using a platform-dependent hook:
```c
/* Returns PAGE_ZONE_SECURE, PAGE_ZONE_NONSECURE, or PAGE_ZONE_ANY */
int hal_mem_zone(paddr_t pa);
```

#### HAL Implementation (ARM Musca-B1):
```c
int hal_mem_zone(paddr_t pa)
{
#ifdef FALLBACK_1_1
    if (pa >= 0x30000000 && pa <= 0x3003FFFF) return PAGE_ZONE_SECURE;
    if (pa >= 0x20040000 && pa <= 0x2007FFFF) return PAGE_ZONE_NONSECURE;
#else
    /* Primary 1:3 split */
    if (pa >= 0x30000000 && pa <= 0x3001FFFF) return PAGE_ZONE_SECURE;
    if (pa >= 0x20020000 && pa <= 0x2007FFFF) return PAGE_ZONE_NONSECURE;
#endif
    return PAGE_ZONE_SECURE; /* Default fallback */
}
```

### 2.3 Page Allocator Integration (`sys/mem/page.c`)
We introduce zone-specific allocation inside the core page allocator:
```c
paddr_t page_alloc_zone(psize_t size, int zone)
{
    /* 
     * 1. Traverse the free page list starting from page_head.
     * 2. Call hal_mem_zone(block_addr) on each block.
     * 3. Allocate only if:
     *    - block_zone == zone, OR
     *    - zone == PAGE_ZONE_ANY
     */
}

/* Backward-compatible wrapper for kernel heap & drivers */
paddr_t page_alloc(psize_t size)
{
    return page_alloc_zone(size, PAGE_ZONE_SECURE);
}
```

### 2.4 User VM Allocator Hook (`sys/mem/vm_nommu.c`)
When allocating virtual memory segments for new tasks, pages are explicitly requested from the Non-Secure zone:
```c
/* In vm_nommu.c: seg_alloc() */
if ((pa = page_alloc_zone(size, PAGE_ZONE_NONSECURE)) == 0)
    return NULL; /* Out of user-domain memory */
```

### 2.5 Address Aliasing, Translation, and Unprivileged Copying
In TrustZone-M, physical SRAM is mapped to both Secure (`0x3xxxxxxx`) and Non-Secure (`0x2xxxxxxx`) address spaces. We manage this mapping using the following principles:

1. **Canonical Tracker:** The kernel's page allocator tracks and manages all pages using their canonical Secure addresses (`0x30xxxxxx`).
2. **Address Translation:** When a page is allocated for a user task, the VM manager clears bit 28 (`pa & ~0x10000000`) to translate it to its Non-Secure alias (`0x20xxxxxx`) before returning it to user space.
3. **Unprivileged Safe Copying:** The kernel uses `LDRT` (Load Unprivileged) and `STRT` (Store Unprivileged) in `copyin()` and `copyout()` when reading or writing to user-space Non-Secure addresses. This prevents user-space pointer-forgery exploits targeting Secure memory, triggering an immediate hardware **SecureFault** if an invalid address is supplied.

---

## 3. Architectural Design & Register Frames

### 3.1 Stack Usage
* **MSP (Main Stack Pointer)**: Reserved exclusively for the kernel (Handler Mode and initial kernel boot/Thread Mode).
* **PSP (Process Stack Pointer)**: Used for all User Mode tasks.

When an exception occurs while running a User Mode task, the Cortex-M33 hardware automatically stacks the basic frame onto `PSP`:
$$\text{Hardware Stack Frame (32 bytes)} = \{ r0, r1, r2, r3, r12, lr, pc, xPSR \}$$
The CPU then switches to Handler Mode and uses `MSP`.

### 3.2 Unified Register Frame (`struct cpu_regs`)
To avoid modifying generic kernel code (e.g., [`syscall_handler`](file:///home/champ/workspace/gemini_playground/prex/sys/kern/sysent.c#L87)), we must present a contiguous [`cpu_regs`](file:///home/champ/workspace/gemini_playground/prex/bsp/hal/arm/include/context.h#L72) structure on the kernel stack (`MSP`).

The memory layout of [`cpu_regs`](file:///home/champ/workspace/gemini_playground/prex/bsp/hal/arm/include/context.h#L72) for `ARMv8-M` is:
```c
struct cpu_regs {
    /* Software stacked (32 bytes) */
    uint32_t r4;
    uint32_t r5;
    uint32_t r6;
    uint32_t r7;
    uint32_t r8;
    uint32_t r9;      /* Static Base (PIC data pointer) */
    uint32_t r10;
    uint32_t r11;
    
    /* Hardware stacked (32 bytes) */
    uint32_t r0;
    uint32_t r1;
    uint32_t r2;
    uint32_t r3;
    uint32_t r12;
    uint32_t lr;
    uint32_t pc;
    uint32_t cpsr;   /* xPSR */
    
    /* Padding & Control Registers (12 bytes) */
    uint32_t sp;     /* Original PSP value (PSP + 32) */
    uint32_t svc_sp; /* Kernel Stack Pointer (MSP) */
    uint32_t svc_lr; /* EXC_RETURN value */
};
```

---

## 4. Security Attribution Unit (SAU) Configuration

During kernel startup, the SAU defines boundaries between Secure, Non-Secure Callable (NSC), and Non-Secure memory partitions:

```c
#define SAU_CTRL  (*(volatile uint32_t*)0xE000EDD0)
#define SAU_RNR   (*(volatile uint32_t*)0xE000EDD8)
#define SAU_RBAR  (*(volatile uint32_t*)0xE000EDDC)
#define SAU_RLAR  (*(volatile uint32_t*)0xE000EDE0)

void sau_init(void)
{
    /* 1. Disable SAU temporarily */
    SAU_CTRL &= ~1;

    /* 2. Configure Region 0: Non-Secure User Tasks Execution (QSPI Flash Non-Secure Alias) */
    SAU_RNR = 0;
    SAU_RBAR = 0x00020000 & 0xFFFFFFE0;
    SAU_RLAR = (0x007FFFFF & 0xFFFFFFE0) | 1; /* Enable, Non-secure */

    /* 3. Configure Region 1: Non-Secure Callable (NSC) Veneers in QSPI Flash */
    SAU_RNR = 1;
    SAU_RBAR = 0x1001F000 & 0xFFFFFFE0;
    SAU_RLAR = (0x1001FFFF & 0xFFFFFFE0) | 3; /* Enable, Non-secure Callable (NSC) */

    /* 4. Configure Region 2: Non-Secure RAM (System SRAM Non-Secure Alias) */
    SAU_RNR = 2;
#ifdef FALLBACK_1_1
    SAU_RBAR = 0x20040000 & 0xFFFFFFE0;       /* Start at 256KB offset */
#else
    SAU_RBAR = 0x20020000 & 0xFFFFFFE0;       /* Start at 128KB offset (1:3 split) */
#endif
    SAU_RLAR = (0x2007FFFF & 0xFFFFFFE0) | 1; /* Enable, Non-secure */

    /* 5. Enable SAU */
    SAU_CTRL |= 1;

    /* Enforce memory and instruction synchronization */
    __asm__ volatile("dsb\n\tisb" : : : "memory");
}
```

---

## 5. Implementation Steps

### Step 5.1: Modify User Compilation Flags
Add `-fropi -frwpi` and `-ffixed-r9` to the build settings for user tasks, and configure linker scripts to support position independent references. All libraries under `./usr/lib` (including `libc` and `libposix`) are also compiled with these flags.

### Step 5.2: Update ELF Loader for XIP
Modify `load_executable` in [elf.c](file:///home/champ/workspace/gemini_playground/prex/bsp/boot/common/elf.c) to handle XIP:
```c
            if (!(phdr->p_flags & PF_W)) {
                /* Text / RO data (XIP from QSPI Flash) */
                if (m->text == 0) {
                    m->text = (vaddr_t)ptokv(img + phdr->p_offset); // Point directly to Flash
                    m->textsz = (size_t)phdr->p_memsz;
                } else {
                    m->textsz = (size_t)((phdr->p_vaddr + phdr->p_memsz) - m->text);
                }
                /* DO NOT memcpy to phys_base. Code executes in-place. */
            } else {
                /* Data & BSS (Relocated to SRAM) */
                if (m->data == 0) {
                    m->data = (vaddr_t)ptokv(load_base); // SRAM location
                }
                m->datasz = (size_t)((phdr->p_vaddr + phdr->p_filesz) - m->data);
                m->bsssz = (size_t)((phdr->p_vaddr + phdr->p_memsz) - m->data) - m->datasz;

                if (phdr->p_filesz > 0) {
                    memcpy((char*)load_base, img + phdr->p_offset, (size_t)phdr->p_filesz);
                }
                if (phdr->p_memsz > phdr->p_filesz) {
                    memset((char*)load_base + phdr->p_filesz, 0, (size_t)(phdr->p_memsz - phdr->p_filesz));
                }
                load_base = round_page(load_base + phdr->p_memsz);
            }
```

### Step 5.3: Set Up `r9` in Initial Thread Context
During task initialization (in `thread_create` / `context_init`), set the task's context register `r9` to point to its SRAM data region (`m->data`).

### Step 5.4: Enforce MSP/PSP Stack Separation in `locore.S`
We will rewrite `syscall_entry` and `syscall_ret` in [locore.S](file:///home/champ/workspace/gemini_playground/prex/bsp/hal/arm/arch/armv8-m/locore.S) to perform stack-to-stack copy (unification) of the registers.

```assembly
ENTRY(syscall_entry)
    /* Check if exception was taken from user space (PSP) */
    tst     lr, #4                  /* EXC_RETURN bit 2 is 1 if PSP was active */
    bne     syscall_from_user

    /* ----------------------------------------------------
     * Case A: SVC called from Kernel Mode (MSP)
     * ---------------------------------------------------- */
    push    {r4-r11}
    mov     r0, sp                  /* r0 = regs */
    ldr     r1, [sp, #32 + 24]      /* Stacked PC */
    ldrb    r4, [r1, #-2]           /* Get SVC immediate number */
    b       syscall_dispatch

    /* ----------------------------------------------------
     * Case B: SVC called from User Mode (PSP)
     * ---------------------------------------------------- */
syscall_from_user:
    mrs     r12, psp                /* r12 = User PSP pointer */

    /* Allocate space for struct cpu_regs on MSP (76 bytes) */
    sub     sp, sp, #76

    /* Save software-saved registers r4-r11 at MSP offset 0 */
    stmia   sp, {r4-r11}

    /* Copy hardware frame {r0-r3, r12, lr, pc, xPSR} from PSP to MSP offset 32 */
    ldmia   r12!, {r4-r11}          /* Pop user registers into temp regs */
    add     r0, sp, #32
    stmia   r0, {r4-r11}            /* Store into MSP frame */

    /* Restore clobbered r4-r11 from MSP offset 0 */
    ldmia   sp, {r4-r11}

    /* Save user SP (original PSP before exception = current r12) */
    str     r12, [sp, #64]          /* cpu_regs.sp = original PSP */

    /* Save EXC_RETURN to svc_lr */
    str     lr, [sp, #72]           /* cpu_regs.svc_lr = EXC_RETURN */

    /* Retrieve SVC number from copied stacked PC (offset 56 on MSP) */
    ldr     r1, [sp, #56]           /* Stacked PC */
    ldrb    r0, [r1, #-2]           /* SVC number (1st parameter) */

    /* Update PSP to reflect hardware frame removal */
    msr     psp, r12

syscall_dispatch:
    mov     r1, sp                  /* regs (2nd parameter) */
    bl      syscall_handler         /* Call C dispatcher */

    /* Store the system call return value (in r0) into the stacked r0 */
    str     r0, [sp, #32]           /* cpu_regs.r0 = return value */

syscall_ret:
    /* Check where to return */
    ldr     lr, [sp, #72]           /* Restore EXC_RETURN */
    tst     lr, #4
    beq     syscall_ret_to_kernel

    /* ----------------------------------------------------
     * Return to User Mode (PSP)
     * ---------------------------------------------------- */
    /* Read current PSP and allocate space for hardware frame */
    mrs     r0, psp
    sub     r0, r0, #32

    /* Copy hardware frame from MSP offset 32 to user stack */
    add     r1, sp, #32
    ldmia   r1, {r4-r11}            /* Load saved registers */
    stmia   r0, {r4-r11}            /* Store onto user stack */

    /* Restore r4-r11 from MSP offset 0 */
    ldmia   sp, {r4-r11}

    /* Deallocate cpu_regs on MSP */
    add     sp, sp, #76

    /* Commit updated PSP */
    mrs     r1, psp
    sub     r1, r1, #32
    msr     psp, r1

    bx      lr                      /* Return to user via EXC_RETURN */

syscall_ret_to_kernel:
    pop     {r4-r11}
    add     sp, sp, #8              /* Pop padding */
    bx      lr
```

### Step 5.5: Implement Context Switching
Context switching is executed synchronously using `cpu_switch` inside `locore.S` to preserve stack frames.

```assembly
ENTRY(cpu_switch)
    stmia   r0, {r4-r11}            /* Save r4-r11 */
    str     sp, [r0, #32]           /* Save sp */
    str     lr, [r0, #36]           /* Save lr */

    ldmia   r1, {r4-r11}            /* Restore r4-r11 */
    ldr     sp, [r1, #32]           /* Restore sp */
    ldr     pc, [r1, #36]           /* Restore pc */
```

### Step 5.6: SysTick & NVIC Interrupt Priorities
Modify [clock.c](file:///home/champ/workspace/gemini_playground/prex/bsp/hal/arm/arch/armv8-m/clock.c):
* Set SysTick priority higher (e.g. `0x40`).

### Step 5.7: Enable Boot Verification in QEMU
Modify the conditional check at line 99 of [verify_all.sh](file:///home/champ/workspace/gemini_playground/prex/verify_all.sh) to include `arm-musca-b1` in boot testing:
```bash
-        if [[ "$TARGET" != "arm-gba" && "$TARGET" != "arm-musca-b1" ]]; then
+        if [[ "$TARGET" != "arm-gba" ]]; then
```

### Step 5.8: Align Configuration Diffs
Update [conf/arm/musca-b1.base](file:///home/champ/workspace/gemini_playground/prex/conf/arm/musca-b1.base) to utilize the corrected boundaries and configure linker options directly without modifying the core build system files:
* `SYSPAGE_BASE` -> `0x30000000` (System SRAM Secure Alias)
* `LOADER_TEXT` -> `0x10000000` (QSPI Flash)
* `BOOTIMG_BASE` -> `0x10002000` (QSPI Flash, immediately following the 8 KB bootloader)
* `KERNEL_TEXT` -> `0x10002044` (QSPI Flash, starts exactly at the kernel ELF in the archive)
* Add `makeoptions LDFLAGS+= -n -z max-page-size=4` to turn off default 64 KB segment page alignment, mapping section virtual addresses directly to physical offsets in the archive.

### Step 5.9: Implement Memory Barrier Operations
Ensure memory barrier synchronization is used when configuring system-critical control registers:
1. **SAU Configuration (`sau_init`):** Add a `dsb` (Data Synchronization Barrier) followed by an `isb` (Instruction Synchronization Barrier) after enabling `SAU_CTRL` to flush the instruction pipeline and guarantee boundaries are immediately active.
2. **VTOR Configuration (`machine_startup` in `machdep.c`):** After updating the vector table pointer `vtor`, invoke `dsb` and `isb` memory barriers to ensure the new handler routing is active before any exception or interrupt occurs:
   ```c
   *vtor = (uint32_t)kernel_start;
   __asm__ volatile("dsb\n\tisb" : : : "memory");
   ```



---

## 6. Verification and Build Steps
To check build and execution correctness:
1. Configure and compile the image:
   ```bash
   ./configure --target=arm-musca-b1 --cross-prefix=arm-none-eabi
   make clean && make && make image
   ```
2. Run automated validation:
   ```bash
   ./verify_all.sh arm-musca-b1 nommu
   ```

---

## 7. Comparison and Alignment with Zephyr's Musca-B1 BSP
Cross-referencing Zephyr's configuration for the Musca-B1 board validates several hardware integrations in our design:

1. **SRAM Partitioning:**
   * In Zephyr's Non-Secure configuration (`v2m_musca_b1_musca_b1_ns.dts`), the Non-Secure SRAM is mapped to `0x20040000` with a size of 256 KB.
   * This aligns exactly with our **Alternative Fallback Plan (1:1 Split)**, which defines the Secure boundary at `0x30000000 - 0x3003FFFF` (256 KB) and the Non-Secure boundary at `0x20040000 - 0x2007FFFF` (256 KB). This matches the standard hardware-enforced TrustZone-M memory split verified by Zephyr.
2. **System Clock Configuration:**
   * Zephyr's system clock configuration (`system-clock` node in `v2m_musca_b1.dts`) defines the system clock for CPU0 at **40 MHz**.
   * We aligned our platform configuration by updating `PL011_CLK=40000000` (40 MHz) in [musca-b1.base](file:///home/champ/workspace/gemini_playground/prex/conf/arm/musca-b1.base). This guarantees accurate PL011 UART baud rate calculations during boots.
3. **QSPI Boot Architecture:**
   * Zephyr's board documentation validates that the base address alias of QSPI Flash starts at `0x00000000` (Non-Secure) / `0x10000000` (Secure). 
   * This aligns with our layout placing `bootldr` at `0x10000000` (Secure alias) and executing `prex+` and user-space tasks directly from QSPI offsets.
