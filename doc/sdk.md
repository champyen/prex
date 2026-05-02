# Prex+ SDK Guide

## Overview
The Prex+ SDK provides a standalone environment for developing and building applications for the Prex+ operating system. It supports both cross-compilation on a host machine (GCC) and native on-device compilation using ported BSD `make` and TinyCC (TCC).

## Building the SDK
To generate the SDK, the `SDK` option must be enabled in the platform configuration file (e.g., `conf/arm/qemu-virt.base`).

1.  **Configure for your target:**
    ```bash
    ./configure --target=arm-qemu-virt --cross-prefix=arm-none-eabi --enable-mmu
    ```
2.  **Generate the SDK:**
    ```bash
    make sdk
    ```
    The SDK will be generated in the `./sdk` directory of your project root. The generator automatically inherits the `MMU` setting from your Prex+ build configuration.

## SDK Structure
The generated SDK contains the following directory structure:
- `/bin`: Host or native binaries (including `tcc` and `make` for on-device use).
- `/include`: Prex+ system headers and TCC internal headers.
- `/lib`: Static libraries (`libc.a`), object files (`crt0.o`), and linker scripts (`user.ld`).
- `/share/mk`: System rules (`sys.mk`) for BSD `make`.
- `/examples`: Example source code (e.g., `hello`).
- `config.mk`: Main configuration dispatcher.
- `config.0.mk`: Host-side (GCC) toolchain settings.
- `config.1.mk`: Device-side (TCC) toolchain settings.
- `config.common.mk`: Shared paths and flags.

## Using the SDK with Make
The SDK uses a hierarchy-based configuration system. To build an application, include `config.mk` in your `Makefile`.

### Environment Selection
The ported BSD `make` automatically sets `IS_PREX=1` when running on Prex+. The `config.mk` dispatcher uses this to select the correct toolchain:
- **Host (GCC):** Uses `config.0.mk`.
- **Device (TCC):** Uses `config.1.mk`.

### MMU and NOMMU Layouts
You can switch between MMU (text=0x10000) and NOMMU (text=0x0) memory layouts using the `MMU` flag. This flag is set to the Prex+ build default but can be overridden on the command line:
```bash
make MMU=0  # For NOMMU/GBA targets
make MMU=1  # For MMU/QEMU targets
```

## Using the On-Device SDK (Native Compilation)
The Prex+ SDK includes a ported version of BSD `make` and TinyCC (TCC), allowing you to compile applications directly on a running Prex+ system.

### Deployment
To use the native SDK, copy the contents of the `sdk/` directory to your Prex+ disk image (typically to the `/usr` partition).
```bash
mcopy -s -i disk.img sdk/* ::/
```

### Native Compilation Example
Once deployed to `/usr`, you can build the included examples using `make`:
```bash
cd /usr/examples/hello
/usr/bin/make
/usr/examples/hello/hello
```

## Technical Details & Improvements
- **Nested Variables:** The ported BSD `make` has been patched to correctly handle nested variable expansions like `$(A_$(B))`.
- **FATFS mtime:** The Prex+ FATFS has been updated to support modification timestamps, allowing `make` to correctly identify out-of-date targets.
- **FATFS Case-Sensitivity:** Short filenames (8.3) are now forced to lowercase in the VFS layer to ensure consistent behavior with `make`'s internal directory cache.
- **TCC Workarounds:** Native TCC port uses page-aligned internal buffers for I/O to satisfy VFS requirements. JIT and dynamic loading are not supported.

---
Copyright© 2026 Champ Yen (champ.yen@gmail.com)
