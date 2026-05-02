This is a github repo, originally rebased from [Prex+ site](http://prex.sourceforge.net).
Maintained and developed by me (champ.yen@gmail.com).
Feel free to submit pull requests.

## Prex+ 2604 Release

Since the original Prex+ 0.9.0 release, this project has been significantly enhanced and is now released as **Prex+ (2604 release)**. Key developments include:

*   **Expanded ARM Support:** Added support for Raspberry Pi Zero W (ARM1176JZF-S) and improved the Integrator/CP support.
*   **New Hardware Drivers:** Implemented interrupt-driven BCM2835 SD Host (SDHC) and DMA drivers for the Raspberry Pi.
*   **Filesystem & Storage:** Implemented a completely new FATFS file system from scratch, along with a new SDMMC stack driver with support for multi-sector reads.
*   **Build System Modernization:** Unified configuration scripts (`--enable-mmu`) and target configurations. Fixed compilation against modern GCC (GCC 15), resolving stack boundary and strict PIC/PIE issues.
*   **x86-pc Boot Fixes:** Resolved critical `bootldr` size limitations, fixed ELF relocation logic for driver modules (`drv.ko`), and fixed memory overlapping/page fault panics in the `exec` server's ELF loader.
*   **System Capabilities:** Addressed capability denials (`CAP_SYSFILES`) ensuring seamless startup of the shell (`cmdbox`) and `init` scripts.
*   **Console Output:** Ensured reliable diagnostic serial output across targets, especially for running without VGA in QEMU.

## What is Prex+?

Prex+ is an open source, royalty-free, real-time operating system for embedded systems. It is designed and implemented for resource-constrained systems that require predictable timing behavior. The highly portable code of Prex+ is written in 100% ANSI C based on traditional microkernel architecture.

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
-   File Systems: multi-threaded, VFS framework, buffer cache, ramfs, fatfs, arfs, etc.
-   POSIX Emulation: pid, fork, exec, file I/O, signal, pipe, tty, pthread, etc.
-   Libc: C library fully optimized to generate a small executable file
-   CmdBox: a small binary that includes tiny versions of many UNIX utilities.
-   Networking: (plan) TCP/IP stack, BSD socket interface

## Development Plan

1.  Develop BSP for QEMU armv7 virt platform (VirtIO serial, block, input, sound, and net devices).
2.  Add new audio and net servers.
3.  Introduce a USB stack and server.
4.  Add RISC-V and Cortex-M support.
5.  Add exFAT and SDXC support.

