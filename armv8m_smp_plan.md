# Prex+ ARMv8-M SMP Implementation Plan

This document outlines the detailed design and implementation plan for Symmetric Multiprocessing (SMP) support on the ARMv8-M Mainline architecture, specifically targeting the dual-core Cortex-M33 ARM Musca-B1 platform in Prex+.

---

## 1. Architectural Context & Design Philosophy

Prex+ SMP extends the uniprocessor (UP) microkernel using the **Big Kernel Lock (BKL)** design. The kernel execution is serialized using a recursive global lock (`kernel_lock`) while allowing concurrent execution of user tasks on multiple cores.

The ARM Musca-B1 platform features:
1. **Dual Cortex-M33 Cores:** Core 0 (Bootstrap Processor - BSP) and Core 1 (Application Processor - AP).
2. **TrustZone-M:** Kernel executes in Secure Handler/Thread modes, and user tasks run in Non-Secure Thread mode.
3. **No-MMU layout with Execute-in-Place (XIP):** Code resides in read-only QSPI Flash; `.data`, `.bss`, and GOT tables are relocated to SRAM.
4. **Per-Core NVIC & SysTick:** The Nested Vectored Interrupt Controller (NVIC) and the SysTick timer are private/local to each processor core.

---

## 2. Core Identity & Per-CPU Management

To support multi-core execution, core-local state is moved into a per-CPU `struct cpu_control` (defined in `sys/include/cpu_control.h`).

### 2.1 Storage of CPU Control Block Pointer
Zero-latency access to the current CPU's control block is achieved using hardware-backed registers. 
- In the ARMv8-M implementation, the Secure **`psplim`** (Process Stack Pointer Limit) register is repurposed to hold the address of the core's local `struct cpu_control`.
- The HAL functions `hal_get_cpu_control()` and `hal_set_cpu_control()` are already defined in `bsp/hal/arm/include/cpu.h` as:
  ```c
  static inline struct cpu_control* hal_get_cpu_control(void) {
      uint32_t cpu;
      __asm__ volatile("mrs %0, psplim" : "=r"(cpu));
      return (struct cpu_control*)cpu;
  }
  static inline void hal_set_cpu_control(struct cpu_control* cpu) {
      __asm__ volatile("msr psplim, %0" : : "r"(cpu));
  }
  ```

### 2.2 Querying CPU ID at Runtime
Cortex-M33 does not have a standard, architecturally-defined CPU Core ID register in the CPU register space. 
On the SSE-200 subsystem (used in Musca-B1), core identification is done via the memory-mapped **`CPU_IDENTITY`** register block.
- **Base Address (Secure):** `0x5001F000` (Secure privileged access only).
- **CPUID Register (Offset `0x000`):** Reading this address returns the CPU ID:
  - Core 0: returns `0`
  - Core 1: returns `1`
- The `hal_cpu_id()` helper in `bsp/hal/arm/arch/armv8-m/cpufunc.c` will be updated to:
  ```c
  uint32_t hal_cpu_id(void) {
  #ifdef CONFIG_SMP
      return *(volatile uint32_t*)0x5001F000;
  #else
      return 0;
  #endif
  }
  ```

---

## 3. Multicore Boot Sequence (BSP and APs)

The boot sequence consists of three phases:

```mermaid
sequenceDiagram
    participant BSP as Core 0 (BSP)
    participant AP as Core 1 (AP)
    
    Note over BSP: Boots via head.S & main()
    Note over BSP: Initializes SAL & prepares AP idle thread
    BSP->>AP: Configure INITSVTOR1 (0x50021114) to kernel_start
    BSP->>AP: Clear bit 1 in CPUWAIT (0x50021118)
    Note over AP: Wakes up from reset
    Note over AP: Jumps to reset_entry -> ap_reset_entry (locore.S)
    Note over AP: Loads AP-specific stack
    AP->>AP: Jumps to C function smp_ap_boot()
    Note over AP: Set local VTOR & enable local SysTick
    Note over AP: Signal ready (increment ready_count)
    BSP->>BSP: Wait for ready_count == CONFIG_SMP_NCPUS
    BSP->>AP: Set smp_active = 1
    Note over AP: Exit boot barrier & enter scheduler
```

### 3.1 Step 1: Bootstrap Processor (BSP) Early Boot
1. CPU0 executes `reset_entry` in `bsp/hal/arm/arch/armv8-m/locore.S`. It reads `0x5001F000` to confirm it is Core 0, clears the BSS, and jumps to `main()`.
2. BSP initializes the system, registers `cpu_table[0]`, and calls `smp_start_aps()` to wake up Core 1.

### 3.2 Step 2: Waking up the Application Processor (AP)
The BSP wakes up CPU1 by programming the SSE-200 System Control Register block (base `0x50021000`):
1. **`INITSVTOR1` (Offset `0x114`):** Holds the initial Secure vector table address for CPU1. The BSP sets this to `kernel_start`.
2. **`CPUWAIT` (Offset `0x118`):** Holds wait bits for cores. The BSP clears bit 1 (`*cpuwait &= ~2`) to release CPU1 from reset.
- Implement this in `bsp/hal/arm/arch/armv8-m/cpufunc.c`:
  ```c
  int hal_cpu_start(uint32_t cpuid, paddr_t entry) {
      if (cpuid == 1) {
          volatile uint32_t *initsvtor1 = (volatile uint32_t *)0x50021114;
          volatile uint32_t *cpuwait = (volatile uint32_t *)0x50021118;
          *initsvtor1 = (uint32_t)entry;
          *cpuwait &= ~2; /* Clear CPU1 wait bit */
          __asm__ volatile("dsb\nisb" : : : "memory");
          return 0;
      }
      return -1;
  }
  ```

### 3.3 Step 3: AP Assembly Entry (`locore.S`)
Update `reset_entry` in `bsp/hal/arm/arch/armv8-m/locore.S` to branch secondary cores to `ap_reset_entry`:
```assembly
ENTRY(reset_entry)
    cpsid   i
    
    /* Check CPU ID */
    ldr     r0, =0x5001F000
    ldr     r0, [r0]
    cmp     r0, #0
    bne     ap_reset_entry
    
    /* BSP continues (setting stack, clearing BSS, jumping to main) */
    ...
```
Implement `ap_reset_entry` in `locore.S` to configure the AP-specific stack:
```assembly
ENTRY(ap_reset_entry)
    /* Read CPU ID */
    ldr     r0, =0x5001F000
    ldr     r0, [r0]
    
    /* sp = &ap_boot_stacks[cpuid][KSTACKSZ] */
    ldr     r1, =ap_boot_stacks
    ldr     r2, =KSTACKSZ
    add     r3, r0, #1
    mul     r4, r3, r2
    add     sp, r1, r4
    
    /* Enforce 8-byte stack alignment (CCR) */
    ldr     r0, =0xE000ED14
    ldr     r1, [r0]
    orr     r1, r1, #8
    str     r1, [r0]
    
    /* Jump to smp_ap_boot() */
    ldr     r0, =smp_ap_boot
    bx      r0
```

---

## 4. Cross-Core Signaling (IPI) & Rescheduling

### 4.1 Message Handling Unit (MHU) for Hardware IPI
On the ARM Musca-B1, inter-processor signaling uses two Message Handling Units (MHU):
- **`MHU0` (CPU0 -> CPU1):** Base `0x52600000`. Writing to `MSG_INT_SET` (offset `0x004`) asserts IRQ 6 on CPU1's NVIC.
- **`MHU1` (CPU1 -> CPU0):** Base `0x52700000`. Writing to `MSG_INT_SET` (offset `0x004`) asserts IRQ 6 on CPU0's NVIC.
- **IPI Interrupt Vector:** We define `IPI_IRQ` as `6` in `bsp/hal/arm/include/cpu.h`.

When sending an IPI, `hal_cpu_send_ipi()` writes to the respective MHU's `MSG_INT_SET` register.

### 4.2 Handling and Clearing the MHU Interrupt
When the MHU interrupt (IRQ 6) fires, the target CPU enters `interrupt_handler()` in `bsp/hal/arm/arch/armv8-m/interrupt.c`. The interrupt must be cleared in the handler by writing to `MSG_INT_CLR` (offset `0x008`):
```c
if (vector == 6) {
    uint32_t cpuid = hal_cpu_id();
    if (cpuid == 0) {
        volatile uint32_t *mhu1_clr = (volatile uint32_t *)0x52700008;
        *mhu1_clr = 0xffffffff; /* Clear MHU1 interrupt on CPU0 */
    } else {
        volatile uint32_t *mhu0_clr = (volatile uint32_t *)0x52600008;
        *mhu0_clr = 0xffffffff; /* Clear MHU0 interrupt on CPU1 */
    }
}
```

### 4.3 QEMU Emulation Fallback (Timer-Based Polling)
In QEMU, the board model `musca-b1` maps `mhu0` and `mhu1` as unimplemented stubs. Consequently, guest writes to these registers are ignored and do not trigger hardware interrupts on the peer CPU.

To ensure scheduler correctness in the QEMU simulator, we implement a **software-polling check** inside the SysTick timer handler:
1. Define a global array of pending IPIs:
   ```c
   volatile int ipi_pending[CONFIG_SMP_NCPUS];
   ```
2. When sending an IPI via `hal_cpu_send_ipi()`, set `ipi_pending[target_cpu] = 1`.
3. In `interrupt_handler()` for the SysTick Timer (vector `-1`):
   ```c
   if (vector == -1) { /* SysTick Timer */
       ...
       /* QEMU Fallback Check */
       uint32_t cpuid = hal_cpu_id();
       if (ipi_pending[cpuid]) {
           ipi_pending[cpuid] = 0;
           irq_handler(IPI_IRQ); /* Dispatch IPI manually */
       }
       timer_handler();
       ...
   }
   ```
This allows rescheduling to be deferred to the next SysTick tick (at most 10ms latency) in QEMU, while preserving hardware-accurate MHU code path execution.

---

## 5. Local Interrupt and Timer Configuration

Since the NVIC and SysTick are core-local, they must be initialized on the secondary core (AP) during `smp_ap_boot()`.

1. **`interrupt_cpu_init()`** in `bsp/hal/arm/arch/armv8-m/interrupt.c`:
   - Set the AP's Vector Table Offset Register (VTOR) at `0xE000ED08` to `kernel_start`.
   - Set basepri to `0` (allow all interrupts).
   - Unmask/enable SysTick and the MHU IPI interrupt (IRQ 6) in the AP's NVIC.
2. **`clock_ap_init()`** in `bsp/hal/arm/arch/armv8-m/clock.c`:
   - Configures the local SysTick timer registers (`SYST_CSR`, `SYST_RVR`, `SYST_CVR`) and starts the timer.

---

## 6. Implementation Roadmap

### Phase 1: Configuration & Identity Setup
- Modify `conf/arm/musca-b1.base` to uncomment/add `options SMP_NCPUS=2`.
- Update `hal_cpu_id()` in `bsp/hal/arm/arch/armv8-m/cpufunc.c` to read the `CPU_IDENTITY` register block.
- Define `IPI_IRQ` as 6 in `bsp/hal/arm/include/cpu.h`.

### Phase 2: Multicore Boot & Assembly Setup
- Update `bsp/hal/arm/arch/armv8-m/locore.S` to check the CPU ID in `reset_entry` and branch CPU1 to `ap_reset_entry`.
- Implement `ap_reset_entry` to calculate the stack offset using `ap_boot_stacks` and jump to `smp_ap_boot()`.
- Implement `hal_cpu_start()` in `bsp/hal/arm/arch/armv8-m/cpufunc.c` to write `INITSVTOR1` and clear the `CPUWAIT` bit.

### Phase 3: Interrupt & Timer Initialization
- Implement `interrupt_cpu_init()` in `bsp/hal/arm/arch/armv8-m/interrupt.c` to load VTOR and configure local NVIC registers.
- Ensure `clock_ap_init()` is compiled and runs SysTick for CPU1.

### Phase 4: IPI Integration & Simulation Verification
- Implement `hal_cpu_send_ipi()` in `bsp/hal/arm/arch/armv8-m/cpufunc.c` (or a new `smp.c` in `bsp/hal/arm/arch/armv8-m/`) writing to the MHU set registers.
- Update `interrupt_handler()` in `interrupt.c` to check for and clear MHU interrupts, and implement the `ipi_pending` QEMU timer-polling fallback.
- Run `verify_all.sh` to compile and boot Prex+ with SMP enabled on the `musca-b1` target.
