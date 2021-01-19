# Development

### Table of Contents

- [Roadmap](#roadmap)
- [Current Ports](#current-ports)
- [Project Status](#project-status)

## Roadmap

The prex development phase is divided into the following 3 stages:

### 1) Version 0.1 - 0.4

Focus: Kernel Quality

- Port kernel to some different h/w platforms
- Freeze primal kernel API
- Increase kernel stability
- Build driver framework

### 2) Version 0.5 - 1.0

Focus: Application Availability

- Develop standard system servers (boot, proc, fs, and exec)
- Build POSIX application framework
- Port shell or some valuable UNIX applications  
- Improve OS security

### 3) Version 1.1 - 2.0

Focus: Network Connectivity

- Develop networking server (net)
- Port various protocol stacks
- Support more h/w platforms



## Current Ports

Prex currently supports the following platforms.

| Name           | Arch     | Platform         | Emulator                        | Toolchain          |
| -------------- | -------- | ---------------- | ------------------------------- | ------------------ |
| x86-pc         | IA32     | PC               | Bochs, QEMU, VMware, Virtual PC | GCC                |
| x86-pc         | IA32     | PC (MMU-less)    | Bochs, QEMU, VMware, Virtual PC | GCC                |
| arm-gba        | ARM7TDMI | Game Boy Advance | VisualBoyAdvance                | GCC                |
| arm-integrator | ARM9     | Integrator/CP    | QEMU                            | GCC                |
| arm-beagle     | ARMv7    | BeagleBoard Rev.B| QEMU                            | GCC                |
| ppc-prep       | PowerPC  | PReP (MMU-less)  | QEMU                            | GCC                |



## Project Status

### Work Completed

|                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| - Task/thread control<br>- Round Robin & FIFO scheduler<br>- Kernel thread<br>- Idle thread<br>- Physical page allocator<br>- Kernel memory allocator<br>- Virtual memory allocator<br>- Memory protection (MMU)<br>- Shared memory<br>- MMU-less system support<br>- Object name space<br>- IPC messaging mechanism<br>- Nested interrupt service routine<br>- Prioritized interrupt service thread<br>- Dedicated interrupt stack<br>- Mutex with priority inheritance<br>- Deadlock detection for mutex<br>- Condition variables<br>- Counting semaphores<br>- Alarm timer<br>- Sleep timer<br>- Periodic timer<br>- Device I/O interface<br>- Event logging interface<br>- Fault trapping<br>- System call library<br>- Dynamic voltage scaling<br>- CPU voltage monitor<br>- Power policy<br>- System suspend timer<br>- LCD off timer<br>- ELF relocation by task loader | - Recursive mutex locking<br>- Getting system information<br>- Kernel monitoring utility<br>- DPC (Deferred Procedure Call)<br>- dmesg - diagnostic message<br>- 'configure' script for build<br>- File system server<br>- Embedded VFS<br>- devfs - device file system<br>- ramfs - RAM file system<br>- arfs - archive file system<br>- fatfs - FAT file system<br>- fifofs - FIFO file system<br>- UNIX pipe<br>- Boot server<br>- Process server<br>- Exec server<br>- Init process<br>- Power server<br>- multi-threaded file system<br>- Signal emulation<br>- POSIX system call emulation<br>- CmdBox - embedded UNIX utils<br>- TTY<br>- libc embedded<br>- ANSI-C comliant source code<br>- Capability based security<br>- Resource limit<br>- Tiny shell<br>- Pathname-based access control<br>- fstab - file system table<br>- Shell script loader |

### Recent Development Plan

|                                                              |      |
| ------------------------------------------------------------ | ---- |
| - Embedded TCP/IP<br>- Network server<br>- USB support<br>- Tick-less kernel<br>- switch to musl libc | - Shared interrupt<br>- C++ support<br>- Emgo driver model<br>- direct mapped kernel functions interface    |

### Plan for the Future

|                                                              |                                                              |
| ------------------------------------------------------------ | ------------------------------------------------------------ |
| - Shared interrupt<br>- High resolution timer<br>- Device object filtering<br>- FPU support<br>- pthread library (subset)<br>- Directory name cache in fs<br>- OS image de-compression by boot loader<br>- Disk management utility | - Raw I/O permission in user space<br>- romfs - ROM file system<br>- isofs - CD file system<br>- ffs - flash file system<br>- Kernel debugger<br>- System call trace<br>- New driver framework |



Copyright© 2005-2009 Kohsuke Ohtani

Copyright© 2021 Champ Yen (champ.yen@gmail.com)
