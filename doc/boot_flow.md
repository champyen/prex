# Prex+ Boot Flow (x86-pc and ARM targets)

This document describes the complete boot sequence of the Prex+ operating system, detailing how the system transitions from the hardware boot phase (BIOS or ARM firmware) to the interactive shell. It covers memory layout definitions, how the system binaries are combined, and the step-by-step execution flow for both x86-pc and ARM architectures.

## 1. Memory Layout and Configuration

The physical and virtual memory layout for each target is defined in its respective configuration file (e.g., `conf/x86/pc.base` for x86, or `conf/arm/rpi0w.base` for ARM). Key memory addresses typically include:

*   **`RAM_BASE`:** The physical start of RAM (e.g., `0x00000000` for x86-pc and Raspberry Pi Zero W).
*   **`RAM_SIZE`:** For ARM targets, this explicitly defines the total available memory, as dynamic detection isn't always available via BIOS.
*   **`LOADER_TEXT`:** The physical load address of the Prex+ bootloader (`bootldr`). For x86-pc, this is `0x00004000`.
*   **`BOOTIMG_BASE`:** The physical address where the OS archive payload (`tmp.a`) is placed in memory before the bootloader extracts it. For x86-pc, this is `0x00100000`.
*   **`KERNEL_TEXT`:** The physical address where the bootloader relocates and loads the kernel (`prex+`). For x86-pc, this is `0x00200000`.
*   **`SYSPAGE_BASE`:** The virtual address of the system page, which acts as the boundary between user space and kernel space.

## 2. Building the Combined Binary (`prexos`)

Prex+ uses a multi-server microkernel architecture. The final bootable image, `prexos`, is an amalgamation of the architecture-specific bootloader, the kernel, hardware drivers, core servers, and a RAM disk containing essential user-space programs.

The combination process is orchestrated by `Makefile` rules, primarily leveraging `ar` (archiver) and `cat`, and is identical across architectures:

1.  **Boot Disk Archive (`bootdisk.a`):**
    First, a static archive is created containing the essential user-space binaries and configuration files needed for the initial boot phase.
    *   **Contents:** `/boot/init`, `/boot/rc` (boot script), `/boot/fstab`, `/boot/cmdbox` (which acts as the shell and core utilities), and any specified samples/tools.
    *   **Command:** `ar rcS bootdisk.a ...`

2.  **Temporary System Archive (`tmp.a`):**
    Next, another archive is created containing the core system components, including the previously created `bootdisk.a`.
    *   **Contents:** `sys/prex+` (the kernel), `bsp/drv/drv.ko` (the combined driver module), the core servers (`boot`, `proc`, `exec`, `pow`, `fs`), and `bootdisk.a`.
    *   **Command:** `ar rcS tmp.a ...`

3.  **Final Image (`prexos`):**
    Finally, the bootloader executable (`bsp/boot/bootldr`) and the system archive (`tmp.a`) are concatenated into a single binary image.
    *   **Contents:** `bootldr` + `tmp.a`
    *   **Command:** `cat bsp/boot/bootldr tmp.a > prexos`

Because `bootldr` is exactly 8KB (padded by its linker script), the system archive (`tmp.a`) always begins at an offset of exactly 8KB (`0x2000`) into the `prexos` file.

For x86, this `prexos` file is then typically copied to a FAT12 floppy image (`floppy.img`). For ARM, it may be placed onto an SD card (e.g., as `kernel.img` for Raspberry Pi) or loaded via U-Boot.

## 3. The Boot Execution Flow

### Step 1: Hardware Boot and Loading
*   **x86-pc (BIOS and Boot Sector):**
    1.  The BIOS performs POST and loads the first sector (512 bytes) of the active boot device into physical memory at `0x7C00`.
    2.  This boot sector (`bootsect.bin`) parses the FAT12 filesystem, locates the `PREXOS` file, and loads it entirely into conventional memory starting at `0x30000` (192KB).
    3.  It then jumps to `0x30000`, the entry point of the loaded `PREXOS` image (which is the start of `bootldr`).
*   **ARM Targets (Firmware / U-Boot):**
    1.  The platform's primary bootloader (e.g., Broadcom GPU firmware on Raspberry Pi, or U-Boot on other boards) initializes the core hardware.
    2.  It loads the `prexos` binary from the storage medium (like an SD card or over TFTP) into RAM at `LOADER_TEXT`.
    3.  Execution is handed over directly to the Prex+ bootloader.

### Step 2: The Bootloader (`bootldr`)
1.  **Entry and Relocation (`head.S`):** Execution begins in the architecture's `head.S`.
    *   **x86:** Running at `0x30000`, it first copies its own 8KB footprint down to `LOADER_TEXT` (`0x4000`) and jumps there. Then, it copies the rest of the image (the `tmp.a` archive, starting at `0x32000`) up to `BOOTIMG_BASE` (`0x00100000`) in extended memory. This limits the OS image to about 440KB to fit within conventional memory during the initial boot sector read. After relocation, it switches the CPU to 32-bit Protected Mode, and jumps to the C code entry `main()`.
    *   **ARM:** Enters Supervisor (SVC) mode, disables IRQ/FIQ, switches to Thumb mode (if applicable), sets up the stack, and jumps to `main()`.
2.  **Initialization (`startup.c`, `main.c`):** The bootloader initializes the serial console for debugging, detects available physical memory, and initializes the `bootinfo` structure.
    *   **x86:** Memory is detected dynamically using BIOS interrupt 0x15 (e820).
    *   **ARM:** Memory is typically hardcoded using `CONFIG_RAM_BASE` and `CONFIG_RAM_SIZE` defined in the board's `.base` config file.
3.  **Archive Extraction (`load.c`):** The bootloader locates the `tmp.a` archive in memory. On x86, it expects to find it exactly at `BOOTIMG_BASE` (`0x00100000`) where `head.S` moved it. It verifies the archive magic string (`!<arch>\n`) and begins scanning the ELF payloads.
4.  **ELF Loading (`elf.c`):** For each ELF binary found in the archive (kernel, drivers, servers), the bootloader parses the ELF headers:
    *   It allocates physical memory for the binary.
    *   It copies the `PT_LOAD` segments (Text, Data) into the allocated memory.
    *   It zero-fills the BSS sections.
    *   It performs ELF relocations (resolving undefined symbols, primarily for the driver module `drv.ko` which is linked against the kernel).
    *   The kernel (`prex+`) is specifically loaded at `KERNEL_TEXT` (`0x00200000` on x86).
5.  **Bootinfo Population:** As it loads each module, it records its physical address, size, and entry point in the `bootinfo` structure. The `bootdisk.a` archive itself is also registered in `bootinfo` as a memory region of type `BOOTDISK`.
6.  **Hand-off:** Finally, the bootloader jumps to the kernel's entry point, passing the physical address of the `bootinfo` structure.

### Step 3: The Kernel (`sys/prex+`)
1.  **Entry (`locore.S`):** The kernel entry point (`bsp/hal/x86/arch/locore.S` or `bsp/hal/arm/arch/locore.S`) sets up the initial page tables, enables the MMU (Memory Management Unit), and maps the kernel and loaded modules into the high virtual address space (above `SYSPAGE_BASE`). It then jumps to `main()`.
2.  **Kernel Initialization (`main.c`):**
    *   Initializes the memory manager (kmem, page allocator, VM).
    *   Initializes the scheduler, threads, and IPC mechanisms.
    *   Initializes the device I/O subsystem.
3.  **Driver Initialization:** The kernel calls the initialization routines of the dynamically loaded driver module (`drv.ko`).
4.  **Task Bootstrap (`task.c`):** The kernel reads the `bootinfo` structure to find the pre-loaded core servers (`boot`, `proc`, `exec`, `pow`, `fs`). It creates a user-space task and thread for each of these servers, mapping their memory segments according to their ELF headers.
5.  **Start Scheduling:** The kernel enables interrupts and starts the thread scheduler, allowing the core servers to run.

### Step 4: Core Servers Initialization
The core servers start running in user space. They initialize themselves and register with each other using IPC.
1.  **`boot` server:** Mounts the initial filesystems (like `ramfs` at `/`, `devfs` at `/dev`). Crucially, it mounts the `arfs` (Archive File System) at `/boot`. The `arfs` driver reads the `BOOTDISK` memory region specified in `bootinfo` (which contains `bootdisk.a`) and presents its contents as files in the `/boot` directory.
2.  **`fs` server:** Manages the VFS (Virtual File System) layer and enforces security capabilities.
3.  **`exec` server:** Handles loading and executing new programs.

### Step 5: User Space Initialization (`init`)
1.  The `boot` server, after mounting filesystems, requests the `exec` server to execute `/boot/init`.
2.  **`init` process:** This is the first standard user-space program. Its primary job is to execute the system boot script.
3.  `init` calls `execl()` to run `/boot/cmdbox` (which is configured to act as `sh` via hardlinks or behavior checking), passing `/boot/rc` as the script to execute.

### Step 6: The Boot Script (`/boot/rc`)
1.  The `cmdbox` (running as `sh`) opens and reads the `/boot/rc` file.
2.  The script typically contains commands to set up the environment, mount additional filesystems (by reading `/boot/fstab`), and start background daemons.
3.  The last command in `conf/etc/rc` is usually `exec sh`, which replaces the script-executing shell with an interactive shell instance.

### Step 7: The Interactive Shell
1.  The `cmdbox` process (now running as an interactive `sh`) displays the `[prex+:/]#` prompt.
2.  It waits for user input via the console device (`/dev/console`).
3.  The system is now fully booted and ready for interaction.