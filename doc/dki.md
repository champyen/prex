# Prex Driver-Kernel Interface

### Table of Contents

- Introduction

- General Information
  - Header File
  - Data Types
  - Calls from ISR

- Driver Data Structure
  - Boot Information
  - Device Operations
  - Driver Object

- Device Object
  - device_create
  - device_destroy
  - device_lookup
  - device_control
  - device_broadcast
  - device_private

- Kernel Memory
  - kmem_alloc
  - kmem_free
  - kmem_map

- User Memory
  - copyin
  - copyout
  - copyinstr

- Physical Page
  - page_alloc
  - page_free
  - page_reserve

- Interrupt
  - irq_attach
  - irq_detach

- Spl
  - spl0
  - splhigh
  - splx

- Scheduler
  - sched_lock
  - sched_unlock
  - sched_tsleep
  - sched_wakeup
  - sched_dpc

- Timer
  - timer_callout
  - timer_stop
  - timer_delay
  - timer_ticks

- Miscellaneous
  - task_capable
  - exception_post
  - machine_bootinfo
  - machine_powerdown
  - sysinfo
  - panic
  - printf
  - dbgctl



## Introduction

The Prex kernel provides the minimum service for the device drivers. Since the driver module is separated from the kernel module, the drivers can not access other kernel functions beyond this interface. This mechanism helps to isolate the kernel from the driver codes.

This document describes the Driver-Kernel Interface (DKI) that can be used by device drivers.

## General Information

### Header File

The Prex driver header file provides common driver services in the kernel. A device driver must include this header file to use the driver-kernel interface.

```
#include <driver.h>
```

### Data Types

The following data types are defined by kernel.

| Data type | Description                            |
| --------- | -------------------------------------- |
| device_t  | Used to identify the device object.    |
| irq_t     | Used to identify the interrupt object. |
| task_t    | Used to identify the task.             |
| thread_t  | Used to identify the thread.           |

### Calls from ISR

The driver-kernel service is limited at interrupt level because the kernel does not synchronize all data accesses for interrupt level access. So, the device driver can use only the following functions from the interrupt service routine.

- spl0()
- splhigh()
- splx()
- sched_wakeup()
- sched_stat()
- timer_callout()
- timer_stop()
- timer_ticks()
- sched_lock()
- sched_unlock()
- sched_tsleep()
- sched_wakeup()
- sched_dpc()
- exception_post()
- printf()
- panic()
- machine_reset()

## Driver Data Structure

### Boot Information

The boot infomation keeps various system informations and they are filled by the boot loader.

 The format of the boot information is as follows:

```
struct bootinfo
{
        struct vidinfo  video;
        struct physmem  ram[NMEMS];     /* physical ram table */
        int             nr_rams;        /* number of ram blocks */
        struct physmem  bootdisk;       /* boot disk in memory */
        int             nr_tasks;       /* number of boot tasks */
        struct module   kernel;         /* kernel image */
        struct module   driver;         /* driver image */
        struct module   tasks[1];       /* boot tasks image */
};
```

### Device Operations

Each device instance has its associated device operations defined by devops structure.

The definition of device operations is as follows:

```
struct devops {
        int (*open)     (device_t dev, int mode);
        int (*close)    (device_t dev);
        int (*read)     (device_t dev, char *buf, size_t *nbyte, int blkno);
        int (*write)    (device_t dev, char *buf, size_t *nbyte, int blkno);
        int (*ioctl)    (device_t dev, u_long cmd, void *arg);
        int (*devctl)   (device_t dev, u_long cmd, void *arg);
};
```

### Driver Object

Each driver must define its own driver object to identify it.

The definition of drver object is as follows:

```
struct driver {
        const char      *name;          /* name of device driver */
        struct devops   *devops;        /* device operations */
        size_t          devsz;          /* size of private data */
        int             flags;          /* state of driver */
        int (*probe)    (struct driver *self);
        int (*init)     (struct driver *self);
        int (*unload)   (struct driver *self);
};
```

## Device Object

The device object is created by the driver to communicate to the application. Usually, the driver creates a device object for an existing physical device. And, it can also be used to handle logical or virtual devices.

```
device_t device_create(struct driver *drv, const char *name, int flags);
int      device_destroy(device_t dev);
device_t device_lookup(const char *name);
int      device_control(device_t dev, u_long cmd, void *arg);
int      device_broadcast(u_long event, void *arg, int force);
void    *device_private(device_t dev);
```

- device_create()

  Creates device object with the specified name in *name*. The *drv* argument points to the driver object. This function returns the ID of the created device object on success, or 0 on failure. The *flags* argument is the combination of the following device flags. `#define D_CHR           0x00000001      /* character device */ #define D_BLK           0x00000002      /* block device */ #define D_REM           0x00000004      /* removable device */ #define D_PROT          0x00000008      /* protected device */ #define D_TTY           0x00000010      /* tty device */ `

- device_destroy()

  Deletes the device object specified in *dev*. This function returns ENODEV if the specified device object does not exist.

- device_lookup()

  Look up the device object by the device name. This function returns the device object, or NULL if the specified device object does not exist.

- device_control()

  Control method to the device object.

- device_broadcast()

  Broadcasts the message specified by *event* to all device objects. If *force* is true, a kernel will ignore the value returned by each driver, and continue event notification. If *force* is false and any driver returns any error for the event, a kernel stops the event notification. In this case, this function returns an error code which is returned by that driver.

- device_private()

  Get the private buffer of the specified device object.

## Kernel Memory

The kernel provides the following memory allocation services for drivers. Please note that it can not allocate lager buffer than one page. If the driver needs larger buffer, it should use page_alloc() instead of kmem_alloc().

```
void *kmem_alloc(size_t size);
void  kmem_free(void *ptr);
void *kmem_map(void *addr, size_t size);
```

- kmem_alloc()

  Allocates the kernel buffer for the specified *size* bytes. It returns the pointer to the allocated buffer on success, or NULL on failure.

- kmem_free()

  Frees the allocated kernel buffer pointed by *ptr*.

- kmem_map()

  Maps the specified virtual address *addr* to the kernel address. It returns the pointer mapped in the kernel memory on success, or NULL if there is no mapped memory.

## User Memory

Since an access to user memory may cause a page fault, the user buffer manipulation is handled by the kernel core code. The driver should not access the user buffer directly. Instead,  it should use the following kernel services.

```
int copyin(const void *uaddr, void *kaddr, size_t len);
int copyout(const void *kaddr, void *uaddr, size_t len);
int copyinstr(const char *uaddr, void *kaddr, size_t len);
```

- copyin()

  Copies the data from the user buffer to the kernel area. Returns 0 on success, or EFAULT on failure.

- copyout()

  Copies the data from the kernel buffer to the user area. Returns 0 on success, or EFAULT on failure.

- copyinstr()

  Copies the string data from the user buffer to the kernel area. Returns 0 on success, or EFAULT on page fault, or ENAMETOOLONG.

## Physical Page

```
paddr_t page_alloc(psize_t size);
void    page_free(paddr_t addr, psize_t size);
int     page_reserve(paddr_t addr, psize_t size);
```

- page_alloc()

  Allocates continuous pages for the specified *size* bytes. This function returns the physical address of the allocated pages, or returns NULL on failure. The kernel does not zero-fill this new page. The requested size is automatically round up to the page boundary.

- page_free()

  Frees allocated page block. The caller must provide the size information in *size* argument that was specified for page_alloc().

- page_reserve()

  Reserves pages in the specified address. This function returns 0 on success, or -1 on failure.

## Spl

The spl() function familly controls the interrupt priority level of CPU.

```
int  splhigh(void);
int  spl0(void);
void splx(int level);
```

- splhigh()

  Block all interrupt. Returns previous interrupt state.

- spl0()

  Unblock all interrupts. Returns previous interrupt state.

- splx()

  Restore the interrupt state.

## Interrupt

```
irq_t irq_attach(int irqno, int prio, int shared, int (*isr)(void *), void (*ist)(void *), void *data);
void  irq_detach(irq_t handle);
```

- irq_attach()

  Attaches to the *ISR* (interrupt service request) and *ist* (interrupt service thread) to the interrupt vector specified in *irqno*. The argument *prio* is the logical interrupt priority level. If *shared* argument is true, the kernel allows the other irq owner to attach to the same irq vector.

- irq_detach()

  Detaches the interrupt from the IRQ specified by *handle*.

The following table shows the logical interrupt priority level for various device types. The priority value 0 is lowest priority for interrupt processing.

| Priority | Name        | Device Class       |
| -------- | ----------- | ------------------ |
| 0        | IPL_NONE    | Nothing (lowest)   |
| 1        | IPL_COMM    | Serial, parallel   |
| 2        | IPL_BLOCK   | FDD, IDE           |
| 3        | IPL_NET     | Network            |
| 4        | IPL_DISPLAY | Screen             |
| 5        | IPL_INPUT   | Keyboard, mouse    |
| 6        | IPL_AUDIO   | Audio              |
| 7        | IPL_BUS     | USB, PcCard        |
| 8        | IPL_RTC     | RTC alarm          |
| 9        | IPL_PROFILE | Profiling timer    |
| 10       | IPL_CLOCK   | System clock timer |
| 11       | IPL_HIGH    | Everything         |

## Scheduler

The thread can sleep/wakeup for the specific event. The event works as the queue of the sleeping threads.

```
void sched_lock(void);
void sched_unlock(void);
int  sched_tsleep(struct event *evt, u_long timeout);
void sched_wakeup(struct event *evt);
void sched_dpc(struct dpc *dpc, void (*func)(void *), void *arg);
```

- sched_lock()

  Disables the thread switch, and increments the scheduling lock count. This is used to synchronize the thread execution to protect  global resources. Since the scheduling lock count can be nested,  the caller must call the sched_unlock() routine the same number of lock count.

- sched_unlock()

  Decrements the scheduling lock count. If the scheduling lock count becomes 0,  the thread switch is enabled again.

- sched_tsleep()

  Sleep the current thread until specified event occurs. The caller can specify *timeout* value in msec. If the *timeout* value is 0, the timeout timer does not work. The definition of the event for sleep/wakeup is as follows: `struct event {        struct queue    sleepq;         /* Queue for waiting thread */        char            *name;          /* Event name */ }; `

- sched_wakeup()

  Wakes up all threads that are waiting for the specified event.

- sched_dpc()

  Programs DPC (Deferred Procedure Call). The definition of the DPC object is as follows: `struct dpc {        void    *_data[5]; }; `

## Timer

```
void   timer_callout(timer_t *tmr, void (*func)(u_long), u_long arg, u_long msec);
void   timer_stop(timer_t *tmr);
u_long timer_delay(u_long msec);
u_long timer_ticks(void);
```

- timer_callout()

  Requests a call out timer. The specified *func* routine will be called with *arg* argument after *msec*. The caller must allocate the memory for the timer structure for *tmr*.

- timer_stop()

  Stops a running timer.

- timer_delay()

  Delays thread execution.

- timer_ticks()

  Returns current timer count (ticks since bootup).

## Miscellaneous

```
int   task_capable(cap_t cap);
int   exception_post(task_t task, int excno);
void  machine_bootinfo(struct bootinfo **pbi);
void  machine_powerdown(int state);
void  sysinfo(int type, void *buf);
void  panic(const char *fmt, ...);
void  printf(const char *fmt, ...);
void  dbgctl(int cmd, void *data);
```

- task_capable()

  Check if the current task has the specified capability.

- exception_post()

  Posts an exception for the specific task.

- machine_bootinfo()

  Returns the pointer to the system boot infomation structure.

- machine_powerdown()

  Set the system power.

- sysinfo()

  Attaches to the external output routine for the printf().

- panic()

  Stops the system for the fatal error.

- printf()

  Prints the driver message to the output device. The message is enabled only with debugging kernel.

- dbgctl()

  Control kernel debug featrure.


Copyright© 2005-2009 Kohsuke Ohtani