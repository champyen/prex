# Goal
Restructure Prex+ build directories and slim down built image size

# Prex+ Architectural Plan: Slim & Tiered Volume Structure

This document defines the reorganization of the Prex source tree and the tiered volume strategy to minimize the boot image and optimize resource usage.
* do this step by step
  - as you move one program, please verify it right away, don't try to migrate all things and expect it work well

## 1. Source Tree Reorganization

The `usr/` directory is restructured based on runtime linkage and system role:

*   **`usr/posix/cmdbox/`**: Source for utilities bundled into the `cmdbox` multi-call binary (formerly `usr/bin`).
    - for commands migrated as standalone tools, not just change makefile, the whole folder should move to `usr/posix/`
*   **`usr/posix/`**: Standalone programs linking against **`libc.a`** using **`mk/prog.mk`**.
*   **`usr/tasks/`**: Native microkernel programs linking against **`libsa.a`** using **`mk/task.mk`**.
*   **`usr/test/`**: Diagnostic and regression test programs.

## 2. Tiered Volume Strategy

### Volume 1: `/boot` (Primary Boot Image: `bootdisk.a`)
*   **Role**: Minimal Startup Core.
*   **Design**: Memory-resident (ARFS).
*   **Components**: `init`, `rc`, `fstab`, `LICENSE`.
*   **Slim `cmdbox`**: `sh`, `ls`, `cat`, `date`, `clear`, `mkdir`, `echo`, `sync`, `rm`, `ps`, `kill`, `dmesg`.

### Volume 2: `/bin` (Read-Only ARFS Block Device: `bin.img`)
*   **Role**: Main Production Suite & Native Tasks.
*   **Design**: Standalone binaries loaded on-demand to save RAM.
*   **Contents**:
    *   **All Native Tasks**: Everything from `usr/tasks/` (e.g., `alarm`, `balls`, `bench`, `cpumon`).
    *   **Core Standalones**: `kilo`, `ping`, `nc`, `ifconfig`, `telnet`.
    *   **System Admin**: `diskutil` (integrated mount/umount), `ktrace`, `pmctrl`, `debug`.
    *   **Dynamic Group**: Advanced POSIX Utils (if `CONFIG_ADVANCED_UTILS_IN_BIN=y`).

### Volume 3: `/usr` (Read-Write FATFS Block Device: `disk.img`)
*   **Role**: Unified Workspace, SDK & Validation.
*   **SDK Components**: `tcc` (TinyCC), `make`, system headers (`/usr/include`), and libraries (`/usr/lib`).
*   **Secondary Components**:
    *   **Tests**: All regression test binaries from `usr/test/`.
    *   **Samples**: `helixmp3`, `playwav`, `tetris`, `balls`, `sqlite`.
    *   **Environment**: The `/tmp` directory.
    *   **Dynamic Group**: Advanced POSIX Utils (if `CONFIG_ADVANCED_UTILS_IN_BIN=n`).

## 3. The Deployment Toggle

The flag **`CONFIG_ADVANCED_UTILS_IN_BIN`** controls the placement of standard utilities (`grep`, `find`, `tar`, etc.):
*   **`y`**: Advanced utils placed in the read-only production volume (`/bin`).
*   **`n` (default)**: Advanced utils placed in the workspace volume (`/usr`) for developer flexibility.

## 4. Build System & Staging

*   **Staging Directories**: `bin_root/` (for `/bin`) and `usr_root/` (for `/usr`).
*   **Manifest Files**: `conf/etc/files.mk` (boot), `conf/etc/bin_vol.mk` (bin), and `conf/etc/usr_vol.mk` (usr).

## 5. Technical Benefits

1.  **RAM Recovery**: Moving `usr/tasks/` and heavy POSIX standalones to disk frees significant physical RAM.
2.  **SDK Integration**: Provides a standard Unix-like environment for on-target development.
3.  **Stability**: Driver-level fixes (0x55AA signature check) ensure reliable multi-volume mounting.

## 6. Verification
* Work and test with "arm-qemu-virt" target.
* Please check built image can boot to cmdbox prompt without issue on all supported targets

