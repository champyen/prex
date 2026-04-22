# Prex+ Source Tree and Volume Strategy

Prex+ uses a tiered volume strategy to balance system boot time, image size, and functionality. The source tree is organized to support this multi-volume layout.

## Source Tree Overview

```
.
├── bsp/                # Board Support Package (Bootloader, Drivers, HAL)
├── conf/               # System and Volume configurations
│   └── etc/            # Volume manifests (files.mk, bin_vol.mk, usr_vol.mk)
├── doc/                # Documentation
├── include/            # System-wide headers
├── mk/                 # Build system rules and volume imaging logic
├── sdk/                # Generated SDK (Populated during build)
├── sys/                # Microkernel source (Kern, Mem, Sync, IPC)
└── usr/                # User-mode source
    ├── posix/          # Standalone POSIX tools and cmdbox sources
    │   └── cmdbox/     # "Slim Core" essential utilities (sh, ls, cat, etc.)
    ├── server/         # System servers (fs, proc, exec, network, etc.)
    ├── task/           # RTOS/Real-time tasks
    ├── test/           # Test programs and audio samples
    ├── lib/            # User libraries (libc, libsa, etc.)
    └── arch/           # User-mode architecture specific code
```

## Tiered Volume Strategy

The build system generates three distinct volume images that are intended to be mounted at boot time.

### 1. Primary Boot Volume (`prexos.bin` / `prexos_full.bin`)
- **Format:** ARFS (Archive File System)
- **Mount Point:** `/boot` (and root `/`)
- **Configuration:** `conf/etc/files.mk` (for slim), plus `conf/etc/bin_vol.mk` (for full)
- **Content:**
    - Microkernel and Drivers
    - System Servers (Boot, Proc, Exec, FS, Network)
    - **Slim Core**: Essential utilities required for emergency shell and system recovery (located in `usr/posix/cmdbox`).
    - `init` process and system configuration files (`/etc/rc`, `/etc/fstab`).
    - **Full Image**: `prexos_full.bin` additionally includes all utilities from the binary volume.
- **Goal:** Provide a small kernel image (~500KB) for fast loading, and a full standalone image for convenience.

### 2. Binary Volume (`bin.img`)
- **Format:** ARFS
- **Mount Point:** `/bin`
- **Configuration:** `conf/etc/bin_vol.mk`
- **Content:**
    - The full set of standalone POSIX utilities (migrated from `usr/bin` and `cmdbox`).
    - RTOS tasks and real-time utilities.
- **Goal:** Provide a rich set of command-line tools without bloating the primary boot image.

### 3. User Volume (`disk.img`)
- **Format:** FATFS
- **Mount Point:** `/usr`
- **Configuration:** `conf/etc/usr_vol.mk`
- **Content:**
    - Large applications (e.g., SQLite3, TinyCC, HelixMP3).
    - The Prex+ SDK (Headers, Libraries, and examples for on-device development).
- **Goal:** Support high-capacity storage for applications and developer tools.

## Key Relocations

As part of the Prex+ restructuring:
- **usr/sample** was decommissioned. RTOS tasks moved to `usr/task`, POSIX tools to `usr/posix`, and tests to `usr/test`.
- **usr/sbin** was decommissioned. All system utilities moved to `usr/posix` as standalone tools.
- **cmdbox** was decoupled. Tools that were previously part of the `cmdbox` multi-call binary now exist as standalone programs in `usr/posix`, while a "Slim Core" remains in `usr/bin` for the boot volume.
