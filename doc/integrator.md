# ARM Integrator - HOWTO

### Table of Contents

**HOWTO**

- How to compile Prex for ARM Integrator?
- How to run Prex with QEMU?

## How to compile Prex for ARM Integrator?

At first, you have to prepare the toolchain for cross compiling ARM code. And then, the shell variables must be set for the arm-integrator target.

#### Step 1. Get Sources

Unpack the sources and move to top level directory of the source tree.

```
$ cd /usr/src
$ git clone https://github.com/champyen/prex.git
$ cd prex
```

Step 2. Configure

Setup target architecture and platform.

```
$ ./configure --target=arm-integrator --cross-compile=arm-elf-
```

#### Step 3. Make

Run make.

```
$ make
```

## How to run Prex with QEMU?

 You can run Prex with QEMU by the following command.

```
$ qemu-system-arm.exe  -L . -kernel prexos
```

After the system boot, the black screen will appear in QEMU screen. Then, you have to press Ctrl-Alt-3 to show the serial console. 
*Note: Ctrl-alt-3 opens a terminal, Ctrl-alt-1 shows the geust OS, and Ctrl-alt-2 shows the qemu monitor.*



Copyright© 2005-2009 Kohsuke Ohtani

Copyright© 2021 Champ Yen (champ.yen@gmail.com)