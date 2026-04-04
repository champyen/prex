# Prex+ Device Driver Interface

### Table of Contents

- [Introduction](#introduction)
- [General Information](#general-information)
  - Header File
- [Driver Operations](#driver-operations)
  - driver_shutdown
  - enodev
  - nullop
- [Delay & Calibration](#delay--calibration)
  - calibrate_delay
  - delay_usec
- [DMA Transfers](#dma-transfers)
  - dma_attach
  - dma_detach
  - dma_xfer
  - dma_stop
  - dma_wait
  - dma_alloc
- [String and Memory](#string-and-memory)
  - atol
  - strncpy
  - strncmp
  - strlcpy
  - strnlen
  - memcpy
  - memset
  - strtoul
- [Character Types](#character-types)
  - isalnum, isalpha, isblank, isupper, islower, isspace, isdigit, isxdigit, isprint
- [Debugging](#debugging)
  - assert

## Introduction

The Prex+ kernel provides a Device Driver Interface (DDI) to facilitate device driver development. The DDI supplements the Driver-Kernel Interface (DKI) by providing standard utilities for memory manipulation, string operations, delays, and DMA transfers, helping to keep driver code clean and portable.

## General Information

### Header File

A device driver can include the following header file to use the Device Driver Interface.

```c
#include <ddi.h>
```

## Driver Operations

```c
void driver_shutdown(void);
int  enodev(void);
int  nullop(void);
```

- driver_shutdown()
  Invoked to safely shut down and clean up device drivers.

- enodev()
  A stub function that always returns `ENODEV`. Can be used in `devops` structures for unsupported operations.

- nullop()
  A stub function that simply returns 0. Useful for `devops` structures where an operation is supported but requires no action.

## Delay & Calibration

```c
void calibrate_delay(void);
void delay_usec(u_long usec);
```

- calibrate_delay()
  Calibrates the delay loop for the current processor to ensure accurate microsecond delays.

- delay_usec()
  Blocks the execution for the specified number of microseconds (`usec`) via a busy-wait loop.

## DMA Transfers

The DDI provides a comprehensive set of APIs for configuring and handling Direct Memory Access (DMA) transfers.

```c
dma_t dma_attach(int chan);
void  dma_detach(dma_t handle);
void  dma_xfer(dma_t handle, struct dma_xfer_req *req);
void  dma_stop(dma_t handle);
void  dma_wait(dma_t handle, int32_t timeout_ms);
void *dma_alloc(size_t size);
```

- dma_attach()
  Attaches to the specified DMA channel (`chan`). Returns a handle for subsequent DMA operations.

- dma_detach()
  Detaches from the DMA channel specified by `handle`.

- dma_xfer()
  Starts a DMA transfer using the specified handle and request parameters. The `dma_xfer_req` structure specifies the memory address, device address, size, transfer direction, and DREQ line.

- dma_stop()
  Halts an ongoing DMA transfer for the specified handle.

- dma_wait()
  Waits for a DMA transfer to complete on the specified handle, with an optional timeout in milliseconds.

- dma_alloc()
  Allocates DMA-safe memory of the requested `size`.

### DMA Transfer Request Structure

```c
struct dma_xfer_req
{
    void    *addr;       /* memory address */
    paddr_t  dev_addr;   /* device address */
    u_long   size;       /* transfer size */
    int      dir;        /* direction */
    int      dreq;       /* dreq line */
};
```
Transfer directions can be one of:
- `DMA_READ`: device -> memory
- `DMA_WRITE`: memory -> device
- `DMA_COPY`: memory -> memory

## String and Memory

Standard C library equivalents for string and memory operations available in the kernel space.

```c
long   atol(const char *str);
char  *strncpy(char *dest, const char *src, size_t count);
int    strncmp(const char *src, const char *tgt, size_t count);
size_t strlcpy(char *dest, const char *src, size_t count);
size_t strnlen(const char *str, size_t max);
void  *memcpy(void *dest, const void *src, size_t count);
void  *memset(void *dest, int ch, size_t count);
u_long strtoul(const char *nptr, char **endptr, int base);
```

## Character Types

Standard macros/functions to classify characters.

```c
int isalnum(int c);
int isalpha(int c);
int isblank(int c);
int isupper(int c);
int islower(int c);
int isspace(int c);
int isdigit(int c);
int isxdigit(int c);
int isprint(int c);
```

## Debugging

```c
void assert(const char *file, int line, const char *exp);
```

- assert()
  Kernel assertion handler, typically invoked via the `ASSERT(exp)` macro. It halts the system if the expression evaluates to false, providing the file, line number, and expression that failed. Only active in debugging builds.
