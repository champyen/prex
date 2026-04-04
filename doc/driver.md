# Prex+ Driver Development Guide

### Table of Contents
- [Introduction](#introduction)
- [Driver Architecture](#driver-architecture)
  - Driver Object
  - Device Operations
- [Writing a Basic Driver](#writing-a-basic-driver)
  - 1. Include the Driver Header
  - 2. Define Device Operations
  - 3. Define the Driver Object
  - 4. Initialization and Device Creation
  - 5. Implement I/O Methods
- [Using the Kernel Interfaces](#using-the-kernel-interfaces)
- [Building and Integrating](#building-and-integrating)

---

## Introduction

In the Prex+ operating system, device drivers are cleanly separated from the core microkernel logic. Drivers are built into a single, dynamically loadable driver module (`drv.ko`) that is loaded into the kernel's address space by the bootloader.

This guide provides an overview of the data structures and steps required to write a new device driver for Prex+.

## Driver Architecture

A Prex+ device driver essentially acts as a bridge between the kernel's standard device I/O requests and the specific hardware. Every driver is defined by two primary structures: the `struct driver` (which identifies the driver module) and the `struct devops` (which provides the standard file operations).

### Driver Object

Every driver must instantiate a `struct driver` object. This structure registers the driver's name, initialization routines, and points to its associated device operations.

```c
struct driver {
    const char      *name;          /* Name of the device driver */
    struct devops   *devops;        /* Device operations (I/O methods) */
    size_t          devsz;          /* Size of private device data (if any) */
    int             flags;          /* State/behavior flags */
    int (*probe)    (struct driver *self); /* Hardware detection */
    int (*init)     (struct driver *self); /* Driver initialization */
    int (*unload)   (struct driver *self); /* Clean up and unload */
};
```

### Device Operations

The `struct devops` holds function pointers to the standard POSIX-like device operations. If a device does not support a specific operation (e.g., you cannot `read` from a write-only output device), you can use the built-in stub functions like `no_read`, `no_write`, `no_ioctl`, etc.

```c
struct devops {
    int (*open)     (device_t dev, int mode);
    int (*close)    (device_t dev);
    int (*read)     (device_t dev, char *buf, size_t *nbyte, int blkno);
    int (*write)    (device_t dev, char *buf, size_t *nbyte, int blkno);
    int (*ioctl)    (device_t dev, u_long cmd, void *arg);
    int (*devctl)   (device_t dev, u_long cmd, void *arg);
};
```

## Writing a Basic Driver

Let's look at how to implement a basic "null" device driver (a device that discards all written data and returns EOF on reads).

### 1. Include the Driver Header

All drivers should include the central `<driver.h>` header. This automatically brings in the definitions for driver objects, the Driver-Kernel Interface (DKI), and the Device Driver Interface (DDI).

```c
#include <driver.h>
```

### 2. Define Device Operations

Declare the functions you will implement, and map them in a `devops` structure. Unused operations can be assigned kernel-provided stub handlers.

```c
static int null_read(device_t dev, char *buf, size_t *nbyte, int blkno);
static int null_write(device_t dev, char *buf, size_t *nbyte, int blkno);
static int null_init(struct driver *self);

static struct devops null_devops = {
    /* open   */ no_open,
    /* close  */ no_close,
    /* read   */ null_read,
    /* write  */ null_write,
    /* ioctl  */ no_ioctl,
    /* devctl */ no_devctl,
};
```

### 3. Define the Driver Object

Instantiate the `driver` structure. The kernel locates this object during the driver discovery phase on boot.

```c
struct driver null_driver = {
    /* name   */ "null",
    /* devops */ &null_devops,
    /* devsz  */ 0,
    /* flags  */ 0,
    /* probe  */ NULL,
    /* init   */ null_init,
    /* unload */ NULL,
};
```

### 4. Initialization and Device Creation

In the `init` function (called during kernel startup), the driver should allocate hardware resources and register device nodes that user-space applications can open. This is done using `device_create()`.

```c
static int null_init(struct driver *self)
{
    /* Create a character device node named "null" */
    device_create(self, "null", D_CHR);
    return 0;
}
```

### 5. Implement I/O Methods

Finally, implement the actual data handling. Note that the `read` and `write` functions are passed a pointer to `nbyte` which holds the requested size, and you must update it to reflect the actual number of bytes transferred.

```c
/* Always returns 0 bytes to indicate End of File. */
static int null_read(device_t dev, char *buf, size_t *nbyte, int blkno)
{
    *nbyte = 0;
    return 0; /* Success */
}

/* Data written to this device is discarded. */
static int null_write(device_t dev, char *buf, size_t *nbyte, int blkno)
{
    /* *nbyte remains the same, acting as if all data was consumed. */
    return 0; /* Success */
}
```

## Using the Kernel Interfaces

Drivers run in kernel mode and cannot safely call standard C library functions (like `printf` or `malloc`) or system calls directly. Instead, they must rely on the provided kernel APIs:

1.  **DKI (Driver-Kernel Interface):** Provides fundamental kernel integration, such as creating devices, allocating memory pages (`page_alloc`), attaching hardware interrupts (`irq_attach`), and thread sleep/wakeup (`sched_tsleep`). For full details, see the [Driver-Kernel Interface](dki.md) documentation.
2.  **DDI (Device Driver Interface):** Provides utilities specifically designed to help driver logic, such as safe string operations (`strlcpy`, `memcpy`), precise microsecond delays (`delay_usec`), and DMA configuration (`dma_xfer`). For full details, see the [Device Driver Interface](ddi.md) documentation.

## Building and Integrating

Once you have written your driver (e.g., `mydevice.c`), you must integrate it into the build system so it gets compiled into `drv.ko`.

1.  Place your source code in the appropriate subdirectory under `bsp/drv/dev/` (for architecture-independent drivers) or `bsp/drv/<arch>/` (for platform-specific drivers).
2.  Update the corresponding `Makefile` in that directory to include your object file.
3.  Register your driver in the target board's configuration file (e.g., `conf/x86/pc.base` or `conf/arm/rpi0w.base`). Add a line like:
    ```
    device    mydevice      # My Custom Device Driver
    ```
4.  Re-run `./configure` and `make`. The build system will parse the configuration file, locate your `mydevice_driver` object, and link it into `drv.ko`.