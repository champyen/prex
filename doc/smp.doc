# Prex+ Symmetric Multiprocessing (SMP) Architectural Design

## 1. Introduction and Design Philosophy
Prex+ SMP extends the original uniprocessor microkernel to support Symmetric Multiprocessing while maintaining a "minimum modification" philosophy. The core of the design is a **Modular Big Kernel Lock (BKL)**, which serializes kernel execution across multiple CPUs while allowing concurrent execution of user-mode tasks. This approach minimizes changes to the complex scheduler and IPC logic, isolating multiprocessor synchronization within an elegant SMP Abstraction Layer (SAL).

## 2. Per-CPU Identity and Management

### 2.1 The CPU Control Block (`struct cpu_control`)
To support multiple cores, kernel state that was previously global has been moved into a per-CPU structure.
- **`active_thread`**: The thread currently running on the core.
- **`idle_thread`**: A core-pinned idle thread.
- **`nest_count`**: Interrupt nesting level.
- **`spl_level`**: Local Interrupt Priority Level (IPL).
- **`int_stack`**: Private kernel stack for interrupt handling.

### 2.2 Hardware-Backed Thread Pointers
Accessing the local `cpu_control` block must be extremely low latency. Prex+ utilizes architecture-specific registers to store the pointer to the current CPU's control block:
- **ARMv7-A/R**: Uses `TPIDRPRW` (PL1-only Thread ID Register).
- **ARMv8-M**: Uses `PSPLIM` or a reserved core register for zero-latency state access.
- **RISC-V**: Uses the `tp` (thread pointer) or `sscratch` register.
- **x86**: Uses the `GS` segment register.

**Implementation Example (ARMv7-A)**:
`hal_get_cpu_control()` executes `mrc p15, 0, r0, c13, c0, 4`.

**Abstraction**: Macros like `curthread` are redefined to `(hal_get_cpu_control()->active_thread)`, ensuring that kernel code remains architecture-neutral and performs no table lookups for core-local state.

## 3. The Big Kernel Lock (BKL) Mechanics

### 3.1 Recursive Locking Logic
Prex+ leverages the existing `curthread->locks` counter to implement a recursive BKL.
- **Acquisition**: In `sched_lock()`, if `locks` is 0, the CPU acquires the global TAS (Test-And-Set) `kernel_lock`.
- **Release**: In `sched_unlock()`, when `locks` returns to 0, the CPU releases `kernel_lock`.
- **Interrupt Safety**: CPUs must drop the BKL and IPL while spinning (`splx(s)`) to avoid "Interrupt Blackout" deadlocks, allowing IPIs and hardware IRQs to be serviced.

### 3.2 Lock Handoff and New Thread Entry
When `sched_swtch()` performs a context switch, the BKL is held by the outgoing thread and inherited by the incoming thread.
- **New Threads**: Threads created with `locks == 0` must release the inherited BKL before starting user execution.
- **C-Trampoline**: All new threads enter via `kernel_thread_entry`, which calls `bl sched_bkl_unlock` (the C-trampoline) to release the BKL and drop IPL to 0.

## 4. SMP Boot Sequence (BSP and APs)

### 4.1 Phase 1: Bootstrap Processor (BSP)
1.  **locore.S**: BSP initializes its `TPIDRPRW` to `&cpu_table[0]` using a virtual address.
2.  **smp_init**: BSP initializes the SAL and prepares idle threads for all secondary CPUs.

### 4.2 Phase 2: Application Processor (AP) Wakeup
1.  **hal_cpu_start**: BSP uses PSCI `CPU_ON` (HVC 0x84000003) to awaken APs.
2.  **Physical to Virtual Transition**: APs start in `reset_entry` (physical address). They must:
    - Load the BSP's boot page table (`BOOT_PGD_PHYS`).
    - Enable the MMU and caches.
    - Perform a `long jump` to the virtual address `ap_reload_pc`.
3.  **smp_ap_boot**: Once in virtual space, APs initialize their local GIC interfaces and timers.

### 4.3 Phase 3: Synchronization Barrier
- **`ready_count`**: An atomic counter ensures the BSP waits until all successfully started APs have reached the kernel before proceeding.
- **`smp_active`**: A final signal from the BSP that triggers secondary cores to enter the idle loop and begin scheduling.

## 5. Cross-Core Signaling (IPI)

### 5.1 Inter-Processor Interrupts
IPIs are implemented using GIC Software Generated Interrupts (SGI).
- **SGI 0**: Reserved for `IPI_RESCHED`.
- **Rescheduling**: When a higher priority thread becomes ready for a core currently running a lower priority thread, an IPI is sent to trigger `sched_swtch()` on the target CPU.

## 6. Interrupt Management in SMP

### 6.1 Per-CPU IPL
Interrupt Priority Levels are now per-core. Prex+ uses the GIC **Priority Mask Register (GICC_PMR)** to enforce hardware-assisted masking based on the local `curspl`.

### 6.2 Level-Sensitive IRQs
On multi-core virtual platforms, VirtIO and other shared peripherals must be configured as **Level-Sensitive** (`shared=1` in `irq_attach`). This prevents missed completion signals that can occur with edge-triggered interrupts under concurrent load.

## 7. Driver Synchronization Requirements
Drivers in an SMP environment must adhere to strict synchronization rules:
1.  **Memory Barriers**: Use `__sync_synchronize()` (DMB ISH) before notifying hardware or after reading status rings to ensure cross-core data consistency.
2.  **Hybrid Wait Loops**: Use short-duration polling before falling back to `sched_sleep` to mitigate race conditions between device checks and interrupt-driven wakeups.
3.  **Buffer Isolation**: Avoid global shared buffers for in-flight requests. Implement per-request data slots (e.g., indexed by VirtQueue heads) to prevent cross-CPU data corruption.

## 8. HAL Interface for Porting
New architectures must implement the following `sys/include/hal.h` extensions:
- `hal_get_cpu_control` / `hal_set_cpu_control`: Per-CPU state management.
- `hal_cpu_start(cpuid, entry)`: Awakening secondary cores.
- `hal_cpu_send_ipi(mask, vector)`: Cross-core signaling.
- `clock_ap_init()`: Secondary timer setup.
- `interrupt_cpu_init()`: Local interrupt interface setup.

## 9. Development History
The Prex+ SMP implementation was completed across the following core commits:
- `be8744011565e5db955cf17cdd2cfa5d66ccdc33`: Stage 1 SMP Foundation and CPU Identity
- `ab2528f8f6a2612370e350146c530de7f4b53d20`: Stage 2 Multicore Booting and AP Synchronization
- `2b905ea3ec51b170584bae2c8d4aa5aff44872c3`: Stage 3 Recursive BKL and Lock Handoff
- `5b19e1d91f88dc1b6fc96713f4e2d19f04ba0ff1`: Stage 4 SMP Timer Integration and AP Scheduling
- `232f27c038e94f2573275e582d73821122051c4b`: Modularize SMP CPU control and fix MMU boot
- `a7c33029fde212db258d57ef195f1fcfb8c54bd6`: Implement hardware coherency and BKL refinement
