# Prex SDK Guide

## Overview
The Prex SDK provides a standalone environment for developing and building applications for the Prex operating system. It supports both cross-compilation on a host machine and native on-device compilation using TinyCC (TCC).

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
    The SDK will be generated in the `./sdk` directory of your project root.

## SDK Structure
The generated SDK contains the following directory structure:
- `/bin`: Host or native binaries (including `tcc` for on-device use).
- `/include`: Prex system headers and TCC internal headers.
- `/lib`: Static libraries (`libc.a`), object files (`crt0.o`), and linker scripts (`user.ld`).
- `/src`: Example source code for testing.
- `build_hello.sh`: A reference build script for on-device compilation.

## Using the Host SDK (Cross-Compilation)
You can use the files in the `sdk/` directory to build Prex applications without the full source tree.

1.  **Compile an object file:**
    ```bash
    arm-none-eabi-gcc -mcpu=cortex-a7 -mno-unaligned-access -nostdinc \
      -Iinclude -Iinclude/ipc -Iinclude/machine \
      -o main.o -c main.c
    ```
2.  **Link the executable:**
    ```bash
    arm-none-eabi-ld -static -nostdlib -Llib -T lib/user.ld \
      -o hello lib/crt0.o main.o lib/libc.a -lgcc
    ```

## Using the On-Device SDK (Native Compilation)
The Prex SDK includes a ported version of TinyCC (TCC), allowing you to compile applications directly on a running Prex system.

### Deployment
To use the native SDK, copy the contents of the `sdk/` directory to your Prex disk image (typically to the `/usr` partition).

### Native Compilation Example
Once the SDK files are deployed on the device (e.g., in `/usr/bin`, `/usr/lib`, `/usr/include`), you can compile a source file like this:

1.  **Compile to an object file:**
    ```bash
    /usr/bin/tcc -B/usr/lib/tcc -c /usr/src/main.c -o /tmp/main.o \
      -I/usr/include -I/usr/include/ipc -I/usr/include/machine -nostdinc
    ```
2.  **Link the executable:**
    ```bash
    /usr/bin/tcc -B/usr/lib/tcc -static -nostdlib -L/usr/lib \
      -Wl,-Ttext=0x10000 -o /usr/bin/hello \
      /usr/lib/crt0.o /tmp/main.o /usr/lib/libc.a /usr/lib/tcc/libtcc1.a
    ```
3.  **Run the result:**
    ```bash
    /usr/bin/hello
    ```

### Technical Details & Limitations
- **Workarounds:** Due to Prex VFS memory mapping limitations, the native TCC port uses a 4KB page-aligned internal buffer for all file I/O operations to avoid `EINVAL` errors.
- **Dynamic Loading:** The current TCC port for Prex does not support JIT execution (`-run`) or dynamic loading (`dlopen`).
- **Memory:** Large ELF header structures have been moved to static storage to reduce stack pressure in Prex's small-stack environment.

---
Copyright© 2026 Champ Yen (champ.yen@gmail.com)
