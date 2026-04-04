# ARM Integrator - HOWTO

### Table of Contents

**HOWTO**

- [How to compile Prex+ for ARM Integrator?](#how-to-compile-prex+-for-arm-integrator)
- [How to run Prex+ with QEMU?](#how-to-run-prex+-with-qemu)

## How to compile Prex+ for ARM Integrator?

At first, you have to prepare the toolchain for cross compiling ARM code. For example, on Ubuntu/Debian, you can install the cross-compiler with:
```
$ sudo apt install gcc-arm-none-eabi
```

#### Step 1. Get Sources

Unpack the sources and move to top level directory of the source tree.

```
$ cd /usr/src
$ git clone https://github.com/champyen/prex+.git
$ cd prex+
```

#### Step 2. Configure

Setup target architecture and platform.

To use GCC:
```
$ ./configure --target=arm-integrator --cross-prefix=arm-none-eabi
```

To use Clang:
```
$ ./configure --target=arm-integrator --cc=clang --cross-prefix=arm-none-eabi
```

#### Step 3. Make

Run make. Parallel build is supported.

```
$ make -j4
```

## How to run Prex+ with QEMU?

 You can run Prex+ with QEMU on Linux using the following command:

```
$ qemu-system-arm -M integratorcp -kernel prexos -nographic
```

The `-nographic` option will redirect the serial console to your terminal. To exit QEMU, press `Ctrl-a` then `x`.

On Windows, you can run Prex+ with QEMU by the following command:

```
$ qemu-system-arm.exe  -L . -kernel prexos
```

After the system boot, the black screen will appear in QEMU screen. Then, you have to press Ctrl-Alt-3 to show the serial console. 
*Note: Ctrl-alt-3 opens a terminal, Ctrl-alt-1 shows the guest OS, and Ctrl-alt-2 shows the qemu monitor.*



Copyright© 2005-2009 Kohsuke Ohtani

Copyright© 2021-2026 Champ Yen (champ.yen@gmail.com)
