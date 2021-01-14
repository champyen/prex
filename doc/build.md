# Prex Build Guide

### Table of Contents

- Getting Source
- Prerequisite Tools
- Compiling Prex on Linux
- Compiling Prex on Windows
- Compiling Prex on FreeBSD
- Compiling Prex on MacOS
- Configuring Prex
- Installing Prex
- Customizing OS Image



## Getting Source

Please get source file with git from this [github repo](https://github.com/champyen/prex)

Currently, there is no any released binaries.

## Prerequisite Tools

The following tools are required to build Prex.

- GCC 4.8 or later (~10.0)
- GNU Binutils 2.14 or later
- GNU Make

Now, PCC or other compilers can be used for build.

## Compiling Prex on Linux

#### Step 1. Prepare Toolchain

Prepare the following packages.

- GCC (for ARM platform, please get a appropriate toolchain from [ARM GNU Toolchain](https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain/) website )
- GNU Binutils (Mostly, it is bundled with toolchain.)
- GNU Make

GCC and Binutils should be built appropriately for your target architecture if you cross-compile Prex.

#### Step 2. Get Sources

Unpack the sources and move to top level directory of the source tree.

```
$ cd /usr/src
$ git clone https://github.com/champyen/prex.git
$ cd prex
```

#### Step 2. Configure

Setup target architecture and platform. The following sample shows the setting for x86-pc target.

```
$ ./configure --target=x86-pc
```

#### Step 3. Make

Run make.

```
$ make
```

#### (Tips)

If you want to run 'make' in the subdirectory, you have to set the SRCDIR as follows:

```
$ export SRCDIR=/usr/src/prex
```

## Compiling Prex on Windows

For Windows platform, it is suggested to use WSL/WSL2 environment.

The procedure is same as linux.

If WSL/WSL2 is not considered, MinGW is suggested for this project.

## Compiling Prex on FreeBSD

You have to specify the name of the GNU make on FreeBSD.
 It can be done by changing Makefile.inc or using symbolic link.

- make -> gmake

The compiling method is same with compling on Linux. Please refer to the above build step for Linux.

## Compiling Prex on MacOS

Under construction

## Configuring Prex

### Configure Script

You can use help option for the configure script.

```
$ configure --help

Usage: configure [options]
Options:
        --help                  print this message
        --target=TARGET         use TARGET for target system
        --profile=PROFILE       use PROFILE for target profile
        --cross-prefix=PREFIX   use PREFIX for compile tools
        --cc=CC                 use CC as C compiler
        --no-debug              disable all debug features

$ _
```

### Build Flavors

There some build switches in the Makefile file named /mk/own.mk.

| Switch   | Description                                         |
| -------- | --------------------------------------------------- |
| _DEBUG_  | All debugging features are enabled by default       |
| _QUICK_  | Sample applications and test tools are not compiled |
| _STRICT_ | Compiler will check code strictly                   |
| _SILENT_ | Output message is reduced during build process.     |

## Installing Prex

The method to install an OS image depends on the target platform. It may be described in the target specific document listed in the [Prex document](index.md).

## Customizing OS Image

### OS Image

If you compile the Prex source with "make" command, the OS boot image is created as "prexos" in the root directory. The file "prexos" must exist in root directory of the Prex disk/ROM. You can test your own Prex image by replacing the "prexos" in the OS boot image. The file "prexos" includes the following files.

- Boot loader
- Kernel module
- Driver module
- Boot task(s)

### Directory Organization

The structure of the Prex source directory is as follows:

```
 /conf			System configuration files

 /mk			Common Makefiles

 /include		Common include files

 /sys			Prex microkernel
	/include	Kernel headers
	/lib		Common kernel library
	/ipc		Inter process communication support
	/kern		Kernel main code
	/mem		Memory management code
	/sync		Synchronize related code

 /bsp			Board support package
	/boot		Boot loader
	/drv		Device driver module
	/hal		Hardware abstraction layer

 /usr			User mode programs
	/arch		Architecture dependent code
	/bin		User command binaries
	/include	Header files
	/lib		User libraries
	/server		System servers
	/sbin		System utilities
	/test		Function test programs
	/sample		Sample programs

 configure ... Configuration script

 Makefile .... Top level makefile
```

### Configuring Build Options

You can change the various options to adjust the image for your target requirement. The configuration file is prepared for the each target platform. You can modify the options described in the following file.

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
# Tunable paramters
#
options         HZ=1000         # Ticks/second of the clock
options         TIME_SLICE=50   # Context switch ratio (msec)
options         OPEN_MAX=16     # Max open files per process
options         BUF_CACHE=32    # Blocks for buffer cache
options         FS_THREADS=4    # Number of file system threads
...
```

### Changing Boot Tasks

The boot task is a special task which is loaded by kernel directly at boot time. You can specify your own boot task(s) in "TASKS" option in the following file.

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

Copyright© 2021 Champ Yen (champ.yen@gmail.com)