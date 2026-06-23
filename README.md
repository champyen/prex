This is a github repo, originally rebased from [Prex+ site](http://prex.sourceforge.net).
Maintained and developed by me (champ.yen@gmail.com).
Feel free to submit pull requests.

## Prex+ 2606 Release

Since the **Prex+ 2604 release**, this project has undergone a major architectural evolution across ~170 commits. The headline is **dual-track C + Zig with a single-translation-unit kernel**, plus new architecture support (RISC-V, ARMv8-M) and a full multimedia + networking + on-device SDK stack. See [ChangeLog](doc/ChangeLog) for the full record. Key developments:

*   **Zig Kernel (single translation unit):** The microkernel core (`kern/`, `ipc/`, `sync/`, `mem/`) is now compilable end-to-end in Zig. `sys/kern/main.zig` is the single Zig root; all 18 kernel modules are imported as siblings and compiled together for whole-kernel inlining, dead-code elimination, and comptime validation. C and Zig coexist as peer languages — `select_kernel_src` auto-picks the right file. See [Zig Kernel Development Guide](doc/zig_kernel.md).
*   **Zig Drivers & User-Space:** Portable `dki.zig`/`ddi.zig` wrappers with a comptime-generated `DevOps` static-interface jump table. Zig drivers for RAM disk, VirtIO block, and PL011 UART are in-tree. Userspace has `prex.zig` (native RT) and `posix.zig` (POSIX) libraries wrapping `@cImport`. See [Zig Driver Development Guide](doc/zig_driver.md) and [Zig Application Development Guide](doc/zig_app.md).
*   **RISC-V (RV32) Support:** New `riscv-qemu-virt` target with M-Mode bootloader, S-Mode HAL, SBI stubs, MMU and NOMMU profiles, PLIC driver, Google Goldfish RTC, and 4-stage SMP (foundation → multicore boot via SBI HSM → IPI/PLIC → context unification). All 16 target/variant combinations pass `verify_all.sh`.
*   **ARMv8-M (Cortex-M33) Support:** New `arm-musca-b1` target with QSPI XIP BSP, position-independent code, ELF loader with GOT relocations, and full noMMU integration.
*   **SMP Foundation & Deadlock Detection:** Recursive BKL with lock handoff, AP scheduling, SMP timer integration, dedicated SMP design document, and a comprehensive proactive deadlock detector for both SMP and UP builds. Fixed race conditions in scheduler and timer code paths.
*   **Networking Stack:** Machine-independent network driver with VirtIO-Net, lwIP server port, BSD Socket API in libc, DHCP/DNS clients, and new POSIX tools (`ifconfig`, `ping`, `nc`, hostname, FQDN resolution).
*   **Audio Subsystem:** `sndio` server with zero-copy shared-memory IPC, generic machine-independent audio driver stack, VirtIO Sound driver, `beep` utility, and a port of the Helix MP3 decoder as a sample application.
*   **FATFS Hardening:** FAT32 Long File Name (LFN) support, scatter/gather I/O optimization, FAT cache, and Data-Abort fixes on truncation/write.
*   **On-Device SDK & Database:** SQLite 3.53.0 port, TinyCC compiler port, BSD `make` port, automated SDK generation, and FATFS mtime tracking — all running natively on Prex+.
*   **Userland Tooling:** `cmdbox` gained `dd`, `hexdump`, `od`, `kilo` editor with `getline`, plus retrofits of `grep`, `tail`, `sort`, `wc`, `find`, `xargs`, `tar`, `gzip` from retrobsd/litebsd.
*   **POSIX & System Services:** Thread-safe `pthreads` and resource management, full `select(2)`/`poll(2)` with a new VFS `VOP_POLL` and device notification bridge.
*   **Backtrace Infrastructure:** Unified kernel + user-space backtrace with function-name resolution across x86, ARMv4/v6/v7, and NOMMU builds. ARM Thumb-2 (kernel, drivers, modules, USR) and AAPCS-8 compliance.
*   **Build System:** Multi-arch Zig support, automated size reporting, refactored optimization management (`SIZE_OPT` replaces `TINY`), hardened non-debug builds, parallel-build fixes, and `mk/clang.mk` synced with `mk/gcc.mk`.

## What is Prex+?

Prex+ is an open source, royalty-free, real-time operating system for embedded systems. It is designed and implemented for resource-constrained systems that require predictable timing behavior. The highly portable code of Prex+ is written in Zig/C based on traditional microkernel architecture.

The Prex+ microkernel provides only fundamental features for task, thread, memory, IPC, exception, and synchronization. The other basic OS functions - process, file system, application loading, and networking, are provided by the user mode servers. In addition, Prex+ provides a POSIX emulation layer in order to utilize existing *NIX applications. This design allows the system to perform both of the native real-time task and the generic POSIX process simultaneously without degrading real-time performance. It also helps platform designers to construct OS by choosing suitable system servers for their target requisition.
[Learn more »](doc/README.md)

## Project Goals

The project targets the following goals:

-   To provide a small, portable, real-time, secure, and robust operating system.
-   To provide simple and clean source codes for education and an experimental test-bed.
-   To conform to open standards as much as possible.
-   To enjoy our life with kernel hacking. ;-)

[See current development status »](doc/devel.md)

## License

Prex+ is royalty-free software released under Revised BSD License.
[See License Information »](doc/LICENSE)

## Features

Prex+ has the following features:

-   Task & Thread Control: preemptive priority scheduling with 256 priority levels
-   Memory Management: memory protection, virtual address mapping, shared memory, MMU or MMU-less configuration
-   IPC: object name space, synchronous message passing between threads
-   Exception: fault trapping, framework for POSIX signal emulation
-   Synchronization: semaphores, condition variables, and mutexes with priority inheritance
-   Timers: sleep timers, one-shot or periodic timers
-   Interrupt: nested interrupt service routines, and prioritized interrupt service threads
-   Device I/O: minimum synchronous I/O interface, DPC (Deferred Procedure Call)
-   Security: task capability, pathname-based access control, I/O access permission.
-   Real-time: low interrupt latency, high resolution timers and scheduling priority control
-   Power Management: power policy, idle thread, DVS (Dynamic Voltage Scaling)
-   Debugging Facility: event logging, kernel dump, GDB remote debug
-   File Systems: multi-threaded, VFS framework, buffer cache, ramfs, fatfs (with LFN), arfs, etc.
-   POSIX Emulation: pid, fork, exec, file I/O, signal, pipe, tty, pthread, select/poll, etc.
-   Libc: C library fully optimized to generate a small executable file
-   CmdBox: a small binary that includes tiny versions of many UNIX utilities.
-   Networking: lwIP TCP/IP stack, BSD socket interface, DHCP/DNS, VirtIO-Net
-   Multimedia: sndio audio server (zero-copy IPC), Helix MP3 decoder
-   On-Device SDK: SQLite 3, TinyCC, BSD make — running natively on Prex+
-   Multi-architecture: ARMv4/v5/v6/v7/v7-A, x86, RV32, ARMv8-M (Cortex-M33)
-   Multi-language: kernel core, drivers, and user-space apps all support Zig

## Development Plan

1.  Port Bootloader to Zig
2.  Introduce a USB stack and server.
3.  Add exFAT and SDXC support.
4.  Migrate the remaining kernel core to Zig (memory, sync, ipc, task, thread, sched, irq, exception, device, system, sysent). The C files stay as a fallback (`select_kernel_src`).
5.  Expand Zig user-space tooling (Kilo-style editor in Zig, Zig ports of common utilities).
6.  Tickless kernel idle (dynamic-tick) for power efficiency on Cortex-M33 / RP2350.
7.  Zero-copy network ring buffer between the LwIP server and the VirtIO-Net driver.
8. POSIX message queues (`mq_*`) and shared memory (`shm_open` + `mmap`).
9. On-device Neural Network runtime (TensorFlow Lite Micro / TinyMaix) for edge ML.

## Current Ports

Prex+ 2606 supports the following targets. All are validated by the `verify_all.sh` script (16 target/variant combinations).

| Name              | Arch        | Platform             | MMU Profiles   | SMP   | Emulator          | Toolchain     |
| ----------------- | ----------- | -------------------- | -------------- | ----- | ----------------- | ------------- |
| `arm-qemu-virt`   | ARMv7-A     | QEMU `virt`          | mmu / nommu    | yes   | QEMU              | GCC / Zig     |
| `arm-raspi0`      | ARM1176JZF-S| Raspberry Pi Zero W  | mmu / nommu    | no    | QEMU              | GCC / Zig     |
| `arm-integrator`  | ARMv5/v6    | ARM Integrator/CP    | mmu / nommu    | no    | QEMU              | GCC / Zig     |
| `arm-gba`         | ARM7TDMI    | Game Boy Advance     | nommu          | no    | VisualBoyAdvance  | GCC / Zig     |
| `arm-musca-b1`    | Cortex-M33  | ARM Musca-B1 (QSPI XIP) | nommu        | no    | (on-target)       | GCC / Zig     |
| `riscv-qemu-virt` | RV32        | QEMU `virt`          | mmu / nommu    | yes   | QEMU              | GCC / Zig     |
| `x86-pc`          | IA32        | PC                   | mmu / nommu    | no    | QEMU / Bochs      | GCC / Zig     |

C and Zig are peer languages throughout — the build system auto-selects `.zig` or `.c` per source via `select_kernel_src` / `select_usr_src`.

## Copyright

Copyright © 2005-2009 Kohsuke Ohtani
Copyright © 2021–present Champ Yen (champ.yen@gmail.com)

