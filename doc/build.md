# Prex+ Build Guide

### Table of Contents

- [Getting Source](#getting-source)
- [Prerequisite Tools](#prerequisite-tools)
- [Compiling Prex+ on Linux](#compiling-prex+-on-linux)
- [Compiling Prex+ on Windows](#compiling-prex+-on-windows)
- [Compiling Prex+ on FreeBSD](#compiling-prex+-on-freebsd)
- [Compiling Prex+ on MacOS](#compiling-prex+-on-macos)
- [Configuring Prex+](#configuring-prex+)
- [Installing Prex+](#installing-prex+)
- [Customizing OS Image](#customizing-os-image)



## Getting Source

Please get source file with git from this [github repo](https://github.com/champyen/prex+)

Currently, there is no any released binaries.

## Prerequisite Tools

The following tools are required to build Prex+.

- GCC 4.8 or later (~10.0)
- GNU Binutils 2.14 or later
- GNU Make

Now, GCC, Clang, or other compilers can be used for the build.

## Compiling Prex+ on Linux

#### Step 1. Prepare Toolchain

Prepare the following packages.

- GCC or Clang (for ARM platform, please get an appropriate toolchain from [ARM GNU Toolchain](https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain/) website or use your system's Clang)
- GNU Binutils (Mostly, it is bundled with the toolchain.)
- GNU Make

To build the x86 target on an x86_64 Linux host, you must install the following multilib packages:
```
$ sudo apt install gcc-multilib g++-multilib libc6-dev-i386
```

GCC/Clang and Binutils should be built appropriately for your target architecture if you cross-compile Prex+.

#### Step 2. Get Sources

Unpack the sources and move to the top level directory of the source tree.

```
$ cd /usr/src
$ git clone https://github.com/champyen/prex+.git
$ cd prex+
```

#### Step 2. Configure

Setup target architecture and platform. The following sample shows the setting for the x86-pc target.

```
$ ./configure --target=x86-pc
```

#### Step 3. Make

Run make. Parallel build is supported (e.g., `make -j4`).

```
$ make -j4
```

#### (Tips)

- If you want to run 'make' in a subdirectory, you have to set the SRCDIR as follows:

```
$ export SRCDIR=/usr/src/prex+
```

- To use Clang for cross-compilation, you can use the `--cc=clang` and `--cross-prefix` options. For example:

```
$ ./configure --target=arm-integrator --cc=clang --cross-prefix=arm-none-eabi
```
In this case, `configure` will automatically pass `--target=arm-none-eabi` to Clang.

## Compiling Prex+ on Windows

For the Windows platform, it is suggested to use a WSL/WSL2 environment.

The procedure is the same as Linux.

If WSL/WSL2 is not considered, MinGW is suggested for this project.

## Compiling Prex+ on FreeBSD

You have to specify the name of GNU make on FreeBSD.
 It can be done by changing Makefile.inc or using a symbolic link.

- make -> gmake

The compiling method is the same as compiling on Linux. Please refer to the above build step for Linux.

## Compiling Prex+ on MacOS

Under construction

## Configuring Prex+

### Configure Script

You can use the help option for the configure script.

```
$ ./configure --help

Usage: configure [options]
Options:
	--help			print this message
	--target=TARGET		use TARGET for target system
	--cross-prefix=PREFIX	use PREFIX for compile tools
	--cc=CC			use CC as C compiler
	--enable-mmu		enable MMU support
	--no-debug		disable all debug features

$ _
```

### Build Flavors

There are some build switches in the Makefile file named /mk/own.mk.

| Switch   | Description                                         |
| -------- | --------------------------------------------------- |
| _DEBUG_  | All debugging features are enabled by default       |
| _QUICK_  | Sample applications and test tools are not compiled |
| _STRICT_ | Compiler will check code strictly                   |
| _SILENT_ | Output message is reduced during the build process.     |

## Installing Prex+

The method to install an OS image depends on the target platform. It may be described in the target specific document listed in the [Prex+ document](README.md).

## Customizing OS Image

### OS Image

If you compile the Prex+ source with the "make" command, the following OS images are created in the root directory:

- **prexos.bin**: The primary boot volume (ARFS). It includes the boot loader, kernel module, driver module, and essential system servers and utilities.
- **prexos_full.bin**: Similar to `prexos.bin` but includes all POSIX utilities and RTOS tasks in its internal RAM disk (bootdisk).
- **bin.img**: The secondary volume (ARFS) mounted at `/bin`. It contains the majority of user-mode POSIX utilities and RTOS tasks.
- **disk.img**: The tertiary volume (FATFS) mounted at `/usr`. It contains large applications (like SQLite, TinyCC) and the Prex+ SDK.

### Directory Organization

The structure of the Prex+ source directory is as follows:

```
 /conf			System configuration files
    /etc        Volume and task configuration (files.mk, bin_vol.mk, usr_vol.mk)

 /mk			Common Makefiles and volume generation logic

 /include		Common include files

 /sys			Prex+ microkernel
	/include	Kernel headers
	/lib		Common kernel library
	/ipc		Inter process communication support
	/kern		Kernel main code
	/mem		Memory management code
	/sync		Synchronization related code

 /bsp			Board support package
	/boot		Boot loader
	/drv		Device driver module
	/hal		Hardware abstraction layer

 /usr			User mode programs
	/arch		Architecture dependent code
	/posix      Standalone POSIX utilities and cmdbox
        /cmdbox Combox multi-call binary and "Slim Core" sources
	/include	Header files
	/lib		User libraries
	/server		System servers
	/task		RTOS/Real-time task programs
	/test		Functional and audio test programs

 /sdk           Generated Prex+ SDK directory (populated during build)

 configure ... Configuration script

 Makefile .... Top level makefile
```

### Configuring Build Options

You can change various options to adjust the image for your target requirement. The configuration file is prepared for each target platform. You can modify the options described in the following file.

- /conf/(arch)/(platform)

```
#
# Make options
#
makeoptions     GCCFLAGS+= -march=i386
makeoptions     GCCFLAGS+= -mpreferred-stack-boundary=2

#
# Memory address
#
memory          LOADER_TEXT     0x00004000      # Start of boot loader
memory          KERNEL_TEXT     0x80010000      # Start of kernel
memory          BOOTIMG_BASE    0x80100000      # Location of boot image
memory          SYSPAGE_BASE    0x80000000      # Location of system page

#
# Tunable parameters
#
options         HZ=1000         # Ticks/second of the clock
options         TIME_SLICE=50   # Context switch ratio (msec)
options         OPEN_MAX=16     # Max open files per process
options         BUF_CACHE=32    # Blocks for buffer cache
options         FS_THREADS=4    # Number of file system threads
options         MAX_ALLOC_SIZE=0x400000   # Max kernel memory allocation size
options         USR_STACKSZ=32768         # Default user stack size
options         MAXMEM=16777216           # Max core per task
...
```

**Note:** You must re-run the `./configure` script after changing any options in the platform configuration file to regenerate the header files and `conf/config.mk`.


### Configuring Volume Contents

Prex+ uses three configuration files in `/conf/etc/` to manage the content of each tiered volume:

- **files.mk**: Defines files included in the primary boot volumes (`prexos.bin` and `prexos_full.bin`). Files listed in the `FILES` variable are packed into the core `bootdisk.a`.
- **bin_vol.mk**: Defines files included in the secondary binary volume (`bin.img`). Files listed in `BIN_FILES` are also included in `prexos_full.bin`.
- **usr_vol.mk**: Defines files included in the tertiary user volume (`disk.img`), such as large applications and the SDK.

### Conditional Command Compilation

Individual commands and utilities can be enabled or disabled via `CONFIG_CMD_XXX` flags in the target platform configuration file (e.g., `conf/arm/qemu-virt.base`).

To add or remove a command:
1.  Add or comment out the `command` entry in your platform's `.base` file:
    ```
    command     ls
    #command    tetris
    ```
2.  Re-run `./configure` to update the build environment.
3.  The build system will automatically include or exclude the corresponding source directories during the `make` process.

### Changing Boot Tasks

The boot task is a special task which is loaded by the kernel directly at boot time. You can specify your own boot task(s) in the "TASKS" option in the following file.

- /conf/etc/tasks.mk

```
#
# Boot tasks
#
TASKS+=     $(SRCDIR)/usr/server/boot/boot
TASKS+=     $(SRCDIR)/usr/server/proc/proc
TASKS+=     $(SRCDIR)/usr/server/exec/exec
TASKS+=     $(SRCDIR)/usr/server/fs/fs
...
```



Copyright© 2005-2009 Kohsuke Ohtani

Copyright© 2021-2026 Champ Yen (champ.yen@gmail.com)
