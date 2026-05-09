# Proactive Deadlock Detector for Prex+

## Overview

The Prex+ Deadlock Detector is a modular, multi-tier diagnostic framework designed to identify and debug complex synchronization issues in both Symmetric Multiprocessing (SMP) and Uniprocessor (UP) configurations. It is specifically optimized to catch non-deterministic race conditions, such as "Lost Wakeups" and "Hard Stalls," which are common during high-load I/O operations like MP3 playback.

## Methodology

The detector employs a two-tier strategy to monitor system health:

1.  **Reactive Monitoring (Hard Stall Detection)**:
    *   Uses loop-iteration watchdogs inside critical kernel paths (BKL acquisition, scheduler queues, timer expiration).
    *   If a loop exceeds a predefined threshold (`SPIN_TIMEOUT_ITER`), a stall is declared.
    *   Works even when the system timer is blocked by using a differential check against the tick count.

2.  **Proactive Monitoring (Resource Stall Detection)**:
    *   Periodically scans a global registry of waiting threads.
    *   If a thread remains in a sleep state on a specific resource (Mutex, Semaphore, Condition Variable) for longer than a configured timeout (default: 1 second), it identifies a "Lost Wakeup" and triggers a diagnostic panic.

---

## Core Design

### 1. Proactive Sleep Monitor
The detector maintains a `wait_records` array that tracks every thread entering a wait state.
*   **Hooks**: `deadlock_sleep()` is called before `sched_swtch()`, and `deadlock_stop_sleep()` is called immediately upon wakeup.
*   **Analysis**: The `deadlock_proactive_check()` function (driven by the CPU0 timer interrupt) scans this array. It calculates the duration of each wait and panics if the timeout is exceeded.

### 2. Differential Loop Watchdog
To detect hangs where interrupts are disabled (and thus `lbolt` is frozen), the detector uses a "Differential" approach:
*   It tracks a local iteration counter.
*   It resets the counter only when it observes the system tick count (`lbolt`) advancing.
*   If the counter reaches the limit while `lbolt` is stuck, it confirms that the CPU is spinning in an infinite loop rather than performing legitimate work.

### 3. Lock Ownership Tracking
The detector maintains a per-CPU stack (`struct lock_record`) of held synchronization objects.
*   **Tracking**: It records the address, type (BKL or Mutex), and acquisition time of every lock.
*   **Dumping**: During a panic, the detector provides a full "Lock Status" and "Wait Status" report, showing exactly which thread holds which lock and who is waiting for what.

### 4. Logging Deadlock Bypass
A common failure in deadlock detectors is "Recursive Deadlocking," where the detector hangs while trying to print its findings because it cannot acquire the logging spinlock.
*   **Solution**: Before any reporting, the detector forcefully resets the global `log_lock` to zero, ensuring that console output (`printf`) is guaranteed even during a total system hang.

---

## Instrumented Infrastructure

The following core kernel files are instrumented with detector hooks:

| Component | File | Hook Purpose |
| :--- | :--- | :--- |
| **Scheduler** | `sys/kern/sched.c` | BKL acquisition/release, context switches, sleep/wakeup state tracking. |
| **Timer** | `sys/kern/timer.c` | Heartbeat pulse, proactive checking, loop monitoring in timer thread. |
| **Mutexes** | `sys/sync/mutex.c` | Ownership tracking, recursive lock support, and priority inheritance loops. |
| **Semaphores** | `sys/sync/sem.c` | Wait-state tracking for counting semaphores. |
| **CVs** | `sys/sync/cond.c` | Wait-state tracking for condition variables. |
| **Debug** | `sys/kern/debug.c` | Global export of `log_lock` for bypass capability. |

---

## How to Enable and Use

### Enabling the Detector
The detector is gated by both `DEBUG` and `CONFIG_KD` to ensure zero performance impact in production builds.

1.  **Configure the Kernel**:
    Ensure the `KD` (Kernel Debugger) option is enabled in your platform base file (e.g., `conf/arm/qemu-virt.base`):
    ```text
    options    KD    # Kernel debugger
    ```
2.  **Build with Debug**:
    Run the standard build command. The detector is automatically included if `DEBUG` is defined.

### Interpreting Output
When a deadlock is detected, the system will output a report similar to the following:

```text
*** DEADLOCK DETECTED: Lost Wakeup / Resource Stall ***
Thread 80160ce4 has been waiting on dpc 801088c0 for 101 ticks!

Lock Status:
CPU Depth Thread   Type  Lock Address
--- ----- -------- ----- ------------
  0     0 80160ce4 BKL   80108920

Wait Status:
Thread 80160ce4 waiting on dpc 801088c0 (start 5420)
panic: Sleep Deadlock
```

*   **Type**: Identifies if the hang was a Hard Stall (Spinlock) or a Sleep Deadlock (Lost Wakeup).
*   **Resource**: Identifies the specific Mutex, Event, or Object causing the block.
*   **Lock Address**: Provides the physical address of the lock, which can be cross-referenced with the kernel symbol table or `drv.dis`.
