# Prex Kernel API Reference

### Table of Contents

- Introduction

- General Information
  - Header File
  - Data Types
  - Error Numbers
  - Message Header

- Exception
  - exception_setup
  - exception_return
  - exception_raise
  - exception_wait

- Task
  - task_create
  - task_terminate
  - task_self
  - task_suspend
  - task_resume
  - task_setname
  - task_setcap
  - task_chkcap

- Thread
  - thread_create
  - thread_terminate
  - thread_load
  - thread_self
  - thread_yield
  - thread_suspend
  - thread_resume
  - thread_schedparam

- Virtual Memory
  - vm_allocate
  - vm_free
  - vm_attribute
  - vm_map

- Object
  - object_create
  - object_destroy
  - object_lookup

- Message
  - msg_send
  - msg_receive
  - msg_reply

- Timer
  - timer_sleep
  - timer_alarm
  - timer_periodic
  - timer_waitperiod

- Device
  - device_open
  - device_close
  - device_read
  - device_write
  - device_ioctl

- Mutex
  - mutex_init
  - mutex_destroy
  - mutex_trylock
  - mutex_lock
  - mutex_unlock

- Condition Variable
  - cond_init
  - cond_destroy
  - cond_wait
  - cond_signal
  - cond_broadcast

- Semaphore
  - sem_init
  - sem_destroy
  - sem_wait
  - sem_trywait
  - sem_post
  - sem_getvalue

- System
  - sys_log
  - sys_panic
  - sys_info
  - sys_time
  - sys_debug

## Introduction

The Prex Kernel API Reference defines a programming interface for the Prex applications. This document includes the complete set of kernel services and the detailed description.

## General Information

### Header File

The Prex kernel header file (/include/sys/prex.h) provides external interfaces for the kernel objects. An application must include this header file to use the kernel interface.

```
#include <sys/prex.h>
```

Note: If an application uses POSIX emulation library and does not touch kernel interface, it does not have to include this header.

### Data Types

The following data types are supported by the Prex kernel. Each type represents ID of the kernel element.

| Data type | Description                            |
| --------- | -------------------------------------- |
| object_t  | Used to identify a object.             |
| task_t    | Used to identify a task.               |
| thread_t  | Used to identify a thread.             |
| device_t  | Used to identify a device.             |
| mutex_t   | Used to identify a mutex.              |
| cond_t    | Used to identify a condition variable. |
| sem_t     | Used to identify a semaphore.          |
| cap_t     | Used to represent a task capability.   |

### Error Numbers

The definition of the Prex kernel error is compatible with the POSIX error number. However, unlike POSIX, Prex does not use an errno variable because errno is not MT-safe. So, most functions in kernel API will provide an error number as a return value.

The following error names are used as the possible error number.

- [EPERM]

  Operation not permitted.

- [ENOENT]

  No such file or directory.

- [ESRCH]

  No such process.

- [EINTR]

  Interrupted system call.

- [EIO]

  I/O error.

- [ENXIO]

  No such device or address.

- [EAGAIN]

  Try again.

- [ENOMEM]

  Out of memory.

- [EACCES]

  Permission denied.

- [EFAULT]

  Bad address.

- [EBUSY]

  Device or resource busy.

- [EEXIST]

  File exists.

- [ENODEV]

  No such device.

- [EINVAL]

  Invalid argument.

- [ERANGE]

  Math result not representable.

- [EDEADLK]

  Resource deadlock avoided.

- [ENOSYS]

  Function not implemented.

- [ENAMETOOLONG]

  File name too long.

- [ETIMEDOUT]

  Timed out.

### Message Header

A Prex message consists of a fixed header, followed by a variable amount of data. The format of the message header is as follows:

```
struct msg_header {
        task_t  task;           /* id of send task */
        int     code;           /* message code */
        int     status;         /* return status */
};
```

The ID of send task is automatically filled by the kernel in msg_send() call. So there is no need to set it by the sender task. The receiver task can always trust the task ID in all messages.

## Exception

### NAME

**exception_setup()** -- setup exception handler

### SYNOPSIS

```
int exception_setup(void (*handler)(int));
```

### DESCRIPTION

Setup an exception handler for the current task. NULL can be specified as *handler* to remove current handler. If the handler is removed, all pending exceptions are discarded and all exception_wait() are canceled. Only one exception handler can be set per task. If the previous handler exists in task, exception_setup() just overwrite the handler. 

 The exception handler must have the following arguments.

 void exception_handler(int excno, void *regs);

*excno* is an exception number, and *regs* are the machine dependent registers. The exception handler must call the exception_return() function after it processes the exception.

### ERRORS

- [EFAULT]

  The address of *handler* is inaccessible.



------

### NAME

**exception_return()** -- return from exception handler

### SYNOPSIS

```
void exception_return(void);
```

### DESCRIPTION

The exception_return() function is used to return control from the exception handler.

### ERRORS

This function does not return any error. 



------

### NAME

**exception_raise()** -- raise an exception

### SYNOPSIS

```
int exception_raise(task_t task, int excno);
```

### DESCRIPTION

The exception_raise() function raises an exception for the specified task.

### ERRORS

- [ESRCH]

  No task can be found corresponding to that specified by *task*.

- [EINVAL]

  The specified *excno* is not a valid exception, or the specified task does not register an exception handler.

- [EPERM]

  The specified *task* is not a current task, but the caller task does not have CAP_KILL capability.



------

### NAME

**exception_wait()** -- wait an exception

### SYNOPSIS

```
int exception_wait(int *excno);
```

### DESCRIPTION

The exception_wait() function blocks the caller thread until any exception is raised to the thread. 

 This routine returns EINTR on success.

### ERRORS

- [EFAULT]

  The address of *excno* is inaccessible.

- [EINVAL]

  The caller thread does not register an exception handler.



## Task

### NAME

**task_create()** -- create a new task

### SYNOPSIS

```
int task_create(task_t parent, int vm_option, task_t *childp);
```

### DESCRIPTION

The task_create() function create a new task. If *vm_option* option can be one of the following:

- VM_NEW - The new task has clean memory image.
- VM_COPY - The new task will have the duplicated memory image with the parent task.
- VM_SHARE - The new task will share the same memory image with the parent task.

The child task initially contains no threads. So, the caller task must create new thread under the child task to run it. 

*vm_option* flag is supported only with MMU system. The created task has always new memory map with NOMMU system. 

 The function returns the created task ID in *childp*, and child task will receive 0 as *childp*.

### ERRORS

- [ESRCH]

  The specified *parent* is not a valid task ID.

- [EFAULT]

  The address of *child* is inaccessible.

- [ENOMEM]

  The system is unable to allocate resources.

- [EPERM]

  The specified *parent* is not a current task, but the caller task does not have CAP_TASKCTRL capability.

- [EAGAIN]

  The limit on the total number of tasks in a system would be exceeded.



------

### NAME

**task_terminate()** -- terminate a task

### SYNOPSIS

```
int task_terminate(task_t task);
```

### DESCRIPTION

The task_terminate() function terminates a task and deallocates all resource for the task. 

 If the *task* argument point to the current task, this routine never returns.

### ERRORS

- [ESRCH]

  The specified *task* is not a valid task ID.

- [EPERM]

  The specified *task* is not a current task, but the caller task does not have CAP_TASKCTRL capability.



------

### NAME

**task_self()** -- return task ID

### SYNOPSIS

```
task_t task_self(void);
```

### DESCRIPTION

The task_self() function returns ID of the current task.

### RETURN VALUE

Current task ID. 



------

### NAME

**task_suspend()** -- suspend a task

### SYNOPSIS

```
int task_suspend(task_t task);
```

### DESCRIPTION

The task_suspend() function suspends all threads within the specified task.

### ERRORS

- [ESRCH]

  The specified *task* is not a valid task ID.

- [EPERM]

  The specified *task* is not a current task, but the caller task does not have CAP_TASKCTRL capability.



------

### NAME

**task_resume()** -- resume a task

### SYNOPSIS

```
int task_resume(task_t task);
```

### DESCRIPTION

The task_resume() function resumes all threads within the specified task.

### ERRORS

- [ESRCH]

  The specified *task* is not a valid task ID.

- [EINVAL]

  The specified *task* is not suspended now.

- [EPERM]

  The specified *task* is not a current task, but the caller task does not have CAP_TASKCTRL capability.



------

### NAME

**task_setname()** -- set task name

### SYNOPSIS

```
int task_setname(task_t task, const char *name);
```

### DESCRIPTION

The task_setname() function set the name of the specified task. The task name can be changed at any time. 

 This function does not return error even if the same task name already exists in the system.

### ERRORS

- [ESRCH]

  The specified *task* is not a valid task ID.

- [EFAULT]

  The address of *name* is inaccessible.

- [ENAMETOOLONG]

  The length of the *name* argument exceeds MAX_TASKNAME.

- [EPERM]

  The specified *task* is not a current task, but the caller task does not have CAP_TASKCTRL capability.



------

### NAME

**task_setcap()** -- set a task capability

### SYNOPSIS

```
int task_setcap(task_t task, cap_t cap);
```

### DESCRIPTION

The task_setcap() function set the capability of the specified task.

Available capabilities are defiend int the header file named /include/sys/capability.h.

### ERRORS

- [ESRCH]

  The specified *task* is not a valid task ID.

- [EFAULT]

  The address of *cap* is inaccessible.

- [EPERM]

  The caller task does not have CAP_SETPCAP capability.



------

### NAME

**task_chkcap()** -- check a task capability

### SYNOPSIS

```
int task_chkcap(task_t task, cap_t cap);
```

### DESCRIPTION

The task_chkcap() function checks whether the task has the specified capability.

### ERRORS

- [ESRCH]

  The specified *task* is not a valid task ID.

- [EPERM]

  The specified *task* does not have the *cap* capability.



## Thread

### NAME

**thread_create()** -- create a new thread

### SYNOPSIS

```
int thread_create(task_t task, thread_t *tp);
```

### DESCRIPTION

The thread_create() function creates a new thread within *task*. The new thread will start at the return address of the thread_create() call. 

 Since the created thread is initially set to the suspended state, thread_resume() must be called to start it.

### ERRORS

- [ESRCH]

  The specified *task* is not a valid task ID.

- [EFAULT]

  The address of *tp* is inaccessible.

- [ENOMEM]

  The system is unable to allocate resources.

- [EPERM]

  The specified *task* is not a current task, but the caller task does not have CAP_TASKCTRL capability.

- [EAGAIN]

  The limit on the total number of threads in a task would be exceeded.



------

### NAME

**thread_terminate()** -- terminate a thread

### SYNOPSIS

```
int thread_terminate(thread_t t);
```

### DESCRIPTION

The thread_terminate() function terminates a thread. It will release all resources used by the target thread. 

 If specified *t* is the current thread, this routine never returns.

### ERRORS

- [ESRCH]

  The specified thread *t* is not a valid thread ID.

- [EPERM]

  The caller task is not an owner of the specified *t*, but the caller task does not have CAP_TASKCTRL capability.



------

### NAME

**thread_load()** -- load the thread state

### SYNOPSIS

```
int thread_load(thread_t t, void *entry, void *stack);
```

### DESCRIPTION

The thread_load() function loads the thread state (program counter and stack pointer). 

 The *entry* or *stack* argument can be set to NULL. In this case, the previous state is used.

### ERRORS

- [ESRCH]

  The specified *t* is not a valid thread ID.

- [EINVAL]

  *entry* or *stack* is not a valid address.

- [EPERM]

  The caller task is not an owner of the specified *t*, but the caller task does not have CAP_TASKCTRL capability.



------

### NAME

**thread_self()** -- return thread ID

### SYNOPSIS

```
thread_t thread_self(void);
```

### DESCRIPTION

The thread_self() function returns ID of the current thread.

### RETURN VALUE

Current thread ID. 



------

### NAME

**thread_yield()** -- yield the processor

### SYNOPSIS

```
void thread_yield(void);
```

### DESCRIPTION

The thread_yield() function forces the current thread to release the processor.

### ERRORS

No errors are defined. 



------

### NAME

**thread_suspend()** -- suspend a thread

### SYNOPSIS

```
int thread_suspend(thread_t t);
```

### DESCRIPTION

The thread_suspend() function suspends the specified thread. Although a thread can be suspended any number of times, it does not start to run unless it is resumed by the same number of suspend.

### ERRORS

- [ESRCH]

  The specified *t* is not a valid thread ID.

- [EPERM]

  The caller task is not an owner of the specified *t*, but the caller task does not have CAP_TASKCTRL capability.



------

### NAME

**thread_resume()** -- resume a thread

### SYNOPSIS

```
int thread_resume(thread_t t);
```

### DESCRIPTION

The thread_resume() function resumes the specified thread. A thread does not begin to run, unless both a thread suspend count and a task suspend count are set to 0.

### ERRORS

- [ESRCH]

  The specified *t* is not a valid thread ID.

- [EINVAL]

  The specified *t* is not suspended now.

- [EPERM]

  The caller task is not an owner of the specified *t*, but the caller task does not have CAP_TASKCTRL capability.



------

### NAME

**thread_schedparam()** -- get/set scheduling parameters

### SYNOPSIS

```
int thread_schedparam(thread_t t, int op, int *param);
```

### DESCRIPTION

The thread_schedparam() function gets/sets the various scheduling parameter. *op* argument is an operation ID which is one of the following value.

- OP_GETPRIO - get the scheduling priority
- OP_SETPRIO - set the scheduling priority
- OP_GETPOLICY - get the scheduling policy
- OP_SETPOLICY - set the scheduling policy

The kernel supports the following scheduling policy.

- SCHED_FIFO - First-in First-out
- SCHED_RR   - Round Robin

### ERRORS

- [ESRCH]

  The specified *t* is not a valid thread ID.

- [EFAULT]

  The address of *param* is inaccessible.

- [EINVAL]

  The kernel does not support the specified policy.

- [EPERM]

  The caller task is not an owner of the specified *t*, or the caller task does not have CAP_NICE capability to change the parameter.



## Virtual Memory

### NAME

**vm_allocate()** -- allocate memory

### SYNOPSIS

```
int vm_allocate(task_t task, void **addr, size_t size, int anywhere);
```

### DESCRIPTION

The vm_allocate() function allocates a zero-filled memory in the *task*'s memory space. If the *anywhere* option is false, the kernel try to allocate the memory to the address specified by *addr*. If *addr* is not aligned to the page boundary, it will be automatically round down to one. *size* argument is an allocation size in byte. It will also be adjusted to the page boundary.

### ERRORS

- [ESRCH]

  The specified *task* is not a valid task ID.

- [EACCES]

  The task is not allowed to allocate the memory to the specified address.

- [EFAULT]

  The address of *addr* is inaccessible.

- [ENOMEM]

  Not enough space.

- [EINVAL]

  The specified location is already allocated.

- [EPERM]

  The specified *task* is not a current task, but the caller task does not have CAP_EXTMEM capability.

------

### NAME

**vm_free()** -- free memory

### SYNOPSIS

```
int vm_free(task_t task, void *addr);
```

### DESCRIPTION

The vm_free() function deallocates the memory region. The *addr* argument must point to the memory region previously allocated by vm_allocate() or vm_map().

### ERRORS

- [ESRCH]

  The specified *task* is not a valid task ID.

- [EFAULT]

  The address of *addr* is inaccessible.

- [EINVAL]

  The specified location is not allocated.

- [EPERM]

  The specified *task* is not a current task, but the caller task does not have CAP_EXTMEM capability.

------

### NAME

**vm_attribute()** -- change memory attribute

### SYNOPSIS

```
int vm_attribute(task_t task, void *addr, int prot);
```

### DESCRIPTION

The vm_attribute() function changes the memory attribute. The *addr* argument must point to the memory region previously allocated by vm_allocate() or vm_map(). The attribute type can be chosen a combination of PROT_READ, PROT_WRITE. Note: PROT_EXEC is not supported, yet.

### ERRORS

- [ESRCH]

  The specified *task* is not a valid task ID.

- [EFAULT]

  The address of *addr* is inaccessible.

- [EINVAL]

  The specified location is not allocated. Or, the kernel does not support the specified attribute.

- [EPERM]

  The specified *task* is not a current task, but the caller task does not have CAP_EXTMEM capability.

------

### NAME

**vm_map()** -- map memory

### SYNOPSIS

```
int vm_map(task_t target, void  *addr, size_t size, void **alloc);
```

### DESCRIPTION

The vm_map() function maps another task's memory to the current task. The *target* argument is the memory owner to map. The memory is automatically mapped to the free area of current task. The mapped address is stored in *alloc* on success.

### ERRORS

- [ESRCH]

  The specified *target* is not a valid task ID.

- [EFAULT]

  The address of *addr* or *alloc* is inaccessible.

- [EINVAL]

  The specified location is not allocated.

- [ENOMEM]

  Not enough space.

- [EPERM]

  The specified *target* is not a current task, but the caller task does not have CAP_EXTMEM capability.



## Object

### NAME

**object_create()** -- create a new object

### SYNOPSIS

```
int object_create(const char *name, object_t *objp);
```

### DESCRIPTION

The object_create() function creates a new object. The ID of the new object is stored in *objp* on success. 

 The name of the object must be unique in the system. Or, the object can be created without name by setting NULL as *name* argument. This object can be used as a private object which can be accessed only by threads in the same task.

### ERRORS

- [EFAULT]

  The address of *name* or *objp* is inaccessible.

- [ENAMETOOLONG]

  The length of the *name* argument exceeds MAX_OBJNAME.

- [EPERM]

  The caller task does not have CAP_PROTSERV capability to make a protected object.

- [EEXIST]

  The named object already exists.

- [ENOMEM]

  The system is unable to allocate resources.

- [EAGAIN]

  The limit on the total number of objects in a task would be exceeded.



------

### NAME

**object_destroy()** -- destroy an object

### SYNOPSIS

```
int object_destroy(object_t obj);
```

### DESCRIPTION

The object_destroy() function deletes the object specified by *obj*. 

 A thread can delete the object only when the target object is created by the thread of the same task. All pending messages related to the deleted object are automatically canceled.

### ERRORS

- [EINVAL]

  The specified *obj* is not a valid object ID.

- [EACCES]

  The thread is not allowed to delete the object.



------

### NAME

**object_lookup()** -- lookup an object

### SYNOPSIS

```
int object_lookup(const char *name, object_t *objp);
```

### DESCRIPTION

The object_lookup() function searches an object in the object name space. The *name* argument is the null-terminated string. The object ID is returned in *objp* on success.

### ERRORS

- [EFAULT]

  The address of *name* or *objp* is inaccessible.

- [ENAMETOOLONG]

  The length of the *name* argument exceeds MAX_OBJNAME.

- [ENOENT]

  The specified object does not exist.



## Message

### NAME

**msg_send()** -- send a message

### SYNOPSIS

```
int msg_send(object_t obj, void *msg, size_t size);
```

### DESCRIPTION

The msg_send() function sends a message to an object. The caller thread will be blocked until any other thread receives the message and calls msg_reply() for this object. A thread can send a message to any object if it knows the object ID. 

 The *size* argument specifies the size of the message buffer to send. 

 The message is the binary data block which includes a message header. The kernel does not touch the message body, and it is necessary to recognize the predefined message format between sender and receiver.

### ERRORS

- [EINVAL]

  The specified *obj* is not a valid object ID. Or *size* value is smaller than the size of a message header.

- [EFAULT]

  The buffer of *msg* is inaccessible.

- [EDEADLK]

  *obj* is the object that the caller thread is receiving from now.

- [EAGAIN]

  The receiver thread has been terminated.

- [EINTR]

  The function was interrupted by an exception.



------

### NAME

**msg_receive()** -- receive a message

### SYNOPSIS

```
int msg_receive(object_t obj, void *msg, size_t size);
```

### DESCRIPTION

The msg_receive() function receives a message from an object. A thread can receive a message from the object which was created by the thread in the same task. If the message has not arrived, the caller thread blocks until any message comes in. 

 The *size* argument specifies the "maximum" size of the message buffer to receive. If the sent message is larger than this size, the kernel will automatically clip the message to the receive buffer size. 

 A thread can not receive the multiple messages at once.

### ERRORS

- [EINVAL]

  The specified *obj* is not a valid object ID.

- [EACCES]

  The caller task is not the owner of the target object.

- [EBUSY]

  The caller thread does not finish the previous receive operation.

- [EFAULT]

  The buffer of *msg* is inaccessible.

- [EINTR]

  The function was interrupted by an exception.



------

### NAME

**msg_reply()** -- reply to an object

### SYNOPSIS

```
int msg_reply(object_t obj, void *msg, size_t size);
```

### DESCRIPTION

The msg_reply() function sends a reply message to the object. A thread must reply to the correct object that the thread preciously received from. Otherwise, this function will be failed. 

 The *size* argument specifies the size of the message buffer to reply.

### ERRORS

- [EINVAL]

  The specified *obj* is not a valid object ID. Or, the sender thread has been terminated.

- [EFAULT]

  The buffer of *msg* is inaccessible.



## Timer

### NAME

**timer_sleep()** -- sleep for a while

### SYNOPSIS

```
int timer_sleep(u_long msec, u_long *remain);
```

### DESCRIPTION

The timer_sleep() function stops execution of the current thread until specified time passed. The *msec* argument is the delay time in milli second. If this function is canceled by some reason, the remaining time is stored in *remain*.

### ERRORS

- [EFAULT]

  The address of *remain* is inaccessible.

- [EINTR]

  The function was interrupted by an exception.



------

### NAME

**timer_alarm()** -- schedule an alarm exception

### SYNOPSIS

```
int timer_alarm(u_long msec, u_long *remain);
```

### DESCRIPTION

The timer_alarm() function sends EXC_ALRM exception to the caller task after the specified *msec* milli seconds is passed. If *msec* is 0, it stops the alarm timer. When the previous alarm timer is already working, the remaining time is stored in *remain*.

### ERRORS

- [EFAULT]

  The address of *remain* is inaccessible.



------

### NAME

**timer_periodic()** -- set a periodic timer

### SYNOPSIS

```
int timer_periodic(thread_t t, u_long start, u_long period);
```

### DESCRIPTION

The specified thread will be woken up in specified time interval. The *start* argument is the first wakeup time. If *start* is 0, current periodic timer is stopped. *period* is the time interval to wakeup. The unit of *start*/*period* is milli seconds.

### ERRORS

- [ESRCH]

  The specified thread *t* is not a valid thread ID.

- [EINVAL]

  *start* is 0 even when the timer is not started.

- [ENOMEM]

  The system is unable to allocate resources.

- [EPERM]

  The specified thread *t* is not in the current task.



------

### NAME

**timer_waitperiod()** -- wait timer period

### SYNOPSIS

```
int timer_waitperiod(void);
```

### DESCRIPTION

The timer_waitperiod() function waits the next period of the current running periodic timer. 

 Since this routine returns by any exception, the control may return at non-period time. So, the caller must retry immediately if the error status is EINTR.

### ERRORS

- [EINVAL]

  The periodic timer is not started for current thread.

- [EINTR]

  The function was interrupted by an exception.



## Device

### NAME

**device_open()** -- open a device

### SYNOPSIS

```
int device_open(const char *name, int mode, device_t *dev);
```

### DESCRIPTION

The device_open() function opens the specified device. *mode* is one of the following open mode.

- O_RDONLY - Read only
- O_WRONLY - Write only
- O_RDWR - Read & Write

The ID of the opened device is stored in *dev* on success.

### ERRORS

- [EFAULT]

  The address of *name* is inaccessible.

- [ENAMETOOLONG]

  The length of the *name* argument exceeds MAX_DEVNAME.

- [ENOENT]

  The length of the *name* argument is 0.

- [ENXIO]

  The device was not found.

- [EPERM]

  The caller task does not have CAP_DEVIO capability.

Other device specific error may be returned. 



------

### NAME

**device_close()** -- close a device

### SYNOPSIS

```
int device_close(device_t dev);
```

### DESCRIPTION

The device_close() function close the specified device.

### ERRORS

- [ENODEV]

  The specified device is not valid device.

- [EBADF]

  The specified device is not a valid device opened.

- [EPERM]

  The caller task does not have CAP_DEVIO capability.

Other device specific error may be returned. 



------

### NAME

**device_read()** -- read from a device

### SYNOPSIS

```
int device_read(device_t dev, void *buf, size_t *nbyte, int blkno);
```

### DESCRIPTION

The device_read() function reads data from the specified device. *nbyte* is a read size in byte, and *blkno* is a start block of the target device. The unit of *blkno* is device specific.

### ERRORS

- [ENODEV]

  The specified device is not valid device.

- [EBADF]

  The specified device is not a valid device opened for read.

- [EFAULT]

  The specified buffer is inaccessible, or not writable.

- [EPERM]

  The caller task does not have CAP_DEVIO capability.

Other device specific error may be returned. 



------

### NAME

**device_write()** -- write to a device

### SYNOPSIS

```
int device_write(device_t dev, void *buf, size_t *nbyte, int blkno);
```

### DESCRIPTION

The device_read() function writes data to the specified device. *nbytes* is a write size in byte, and *blkno* is a start block of the target device. The unit of *blkno* is device specific.

### ERRORS

- [ENODEV]

  The specified device is not valid device.

- [EBADF]

  The specified device is not a valid device opened for write.

- [EFAULT]

  The specified buffer is inaccessible

- [EPERM]

  The caller task does not have CAP_DEVIO capability.

Other device specific error may be returned. 



------

### NAME

**device_ioctl()** -- control a device

### SYNOPSIS

```
int device_ioctl(device_t dev, u_long cmd, void *arg);
```

### DESCRIPTION

The device_ioctl() function sends a command to the specified device. *cmd* and *arg* are device dependent.

### ERRORS

- [ENODEV]

  The specified device is not valid device.

- [EBADF]

  The specified device is not a valid device opened for ioctl.

- [EPERM]

  The caller task does not have CAP_DEVIO capability.



## Mutex

### NAME

**mutex_init()** -- initialize a mutex

### SYNOPSIS

```
int mutex_init(mutex_t *mu);
```

### DESCRIPTION

The mutex_init() function creates a new mutex and initializes it. The ID of the new mutex is stored in *mu* on success. 

 If an initialized mutex is reinitialized, undefined behavior results.

### ERRORS

- [ENOMEM]

  The system is unable to allocate resources.

- [EFAULT]

  The address of *mu* is inaccessible.



------

### NAME

**mutex_destroy()** -- destroy a mutex

### SYNOPSIS

```
int mutex_destroy(mutex_t *mu);
```

### DESCRIPTION

The mutex_destroy() function destroys the specified mutex. The mutex must be unlock state, otherwise it fails with EBUSY.

### ERRORS

- [EINVAL]

  The specified mutex is not a valid mutex.

- [EBUSY]

  The mutex is still locked by some thread.



------

### NAME

**mutex_trylock()** -- try to lock a mutex

### SYNOPSIS

```
int mutex_trylock(mutex_t *mu);
```

### DESCRIPTION

The mutex_trylock() tries to lock a mutex without blocking.

### ERRORS

- [EINVAL]

  The specified mutex is not a valid mutex.

- [EBUSY]

  The mutex is already locked.



------

### NAME

**mutex_lock()** -- lock a mutex

### SYNOPSIS

```
int mutex_lock(mutex_t *mu);
```

### DESCRIPTION

The mutex_lock() locks the specified mutex. The caller thread is blocked if the mutex has already been locked. If the caller thread receives any exception while waiting a mutex, this routine returns with EINTR. The mutex is "recursive". It means a thread can lock the same mutex any number of times.

### ERRORS

- [EINVAL]

  The specified mutex is not a valid mutex.

- [EINTR]

  The function was interrupted by an exception.



------

### NAME

**mutex_unlock()** -- unlock a mutex

### SYNOPSIS

```
int mutex_unlock(mutex_t *mu);
```

### DESCRIPTION

The mutex_unlock() function unlocks the specified mutex. The caller thread must be the current mutex owner.

### ERRORS

- [EINVAL]

  The specified mutex is not a valid mutex.

- [EPERM]

  The caller thread is not the mutex owner.



## Condition Variable

### NAME

**cond_init()** -- initialize a condition variable

### SYNOPSIS

```
int cond_init(cond_t *cond);
```

### DESCRIPTION

The cond_init() function creates a new condition variable and initializes it. 

 If an initialized condition variable is reinitialized, undefined behavior results.

### ERRORS

- [EFAULT]

  The address of *cond* is inaccessible.

- [ENOMEM]

  The system is unable to allocate resources.



------

### NAME

**cond_destroy()** -- destroy a condition variable

### SYNOPSIS

```
int cond_destroy(cond_t *cond);
```

### DESCRIPTION

The cond_destroy() function destroys the specified condition variable. If there are any blocked thread waiting for the specified CV, it returns EBUSY.

### ERRORS

- [EINVAL]

  The specified condition variable is not valid.

- [EBUSY]

  The condition variable is still locked by some thread.



------

### NAME

**cond_wait()** -- wait on a condition

### SYNOPSIS

```
int cond_wait(cond_t *cond, mutex_t *mu);
```

### DESCRIPTION

The cond_wait() function waits on the specified condition. If the caller thread receives any exception, this routine returns with EINTR.

### ERRORS

- [EINVAL]

  The specified condition variable is not valid.

- [EINTR]

  The function was interrupted by an exception.



------

### NAME

**cond_signal()** -- signal condition

### SYNOPSIS

```
int cond_signal(cond_t *cond);
```

### DESCRIPTION

The cond_signal() function unblocks the thread that is waiting on the specified condition variable.

### ERRORS

- [EINVAL]

  The specified condition variable is not valid.



------

### NAME

**cond_broadcast()** -- broadcast a condition

### SYNOPSIS

```
int cond_broadcast(cond_t *cond);
```

### DESCRIPTION

The cond_broadcast() function unblocks all threads that are blocked on the specified condition variable.

### ERRORS

- [EINVAL]

  The specified condition variable is not valid.



## Semaphore

### NAME

**sem_init()** -- initialize a semaphore

### SYNOPSIS

```
int sem_init(sem_t *sem, u_int value);
```

### DESCRIPTION

The sem_init() function initializes a semaphore. It will create a new semaphore if the specified *sem* does not exist. If the specified semaphore *sem* already exists, it is re-initialized only if nobody is waiting for it. The initial semaphore value is set to *value* value. The ID of the new semaphore is stored in *sem* on success.

### ERRORS

- [EINVAL]

  *value* value is larger than SEM_MAX.

- [ENOSPC]

  The system is unable to allocate resources.

- [EFAULT]

  The address of *sem* is inaccessible.

- [EBUSY]

  There are currently threads blocked on the semaphore.



------

### NAME

**sem_destroy()** -- destroy a semaphore

### SYNOPSIS

```
int sem_destroy(sem_t *sem);
```

### DESCRIPTION

The sem_destroy() function destroys the specified semaphore. If some thread is waiting for the specified semaphore, this routine fails with EBUSY.

### ERRORS

- [EINVAL]

  The specified semaphore is not a valid semaphore.

- [EBUSY]

  There are currently threads blocked on the semaphore.



------

### NAME

**sem_wait()** -- lock a semaphore

### SYNOPSIS

```
int sem_wait(sem_t *sem, u_long timeout);
```

### DESCRIPTION

The sem_wait() function locks the semaphore referred by *sem* only if the semaphore value is currently positive. The thread will sleep while the semaphore value is zero. It decrements the semaphore value in return. If *timeout* value is set if it is not 0.

### ERRORS

- [EINVAL]

  The specified semaphore is not a valid semaphore.

- [ETIMEDOUT]

  Time out.

- [EINTR]

  The function was interrupted by an exception.



------

### NAME

**sem_trywait()** -- try to lock a semaphore

### SYNOPSIS

```
int sem_trywait(sem_t *sem);
```

### DESCRIPTION

The sem_trylock() tries to lock a semaphore without blocking.

### ERRORS

- [EINVAL]

  The specified semaphore is not a valid semaphore.

- [EAGAIN]

  The semaphore is already locked.



------

### NAME

**sem_post()** -- unlock a semaphore

### SYNOPSIS

```
int sem_post(sem_t *sem);
```

### DESCRIPTION

The sem_post() function unlock the specified semaphore. It increments the semaphore value. If the semaphore value becomes positive, one of the threads waiting to lock will be unblocked. The caller thread is not blocked by this function.

### ERRORS

- [EINVAL]

  The specified semaphore is not a valid semaphore.

- [ERANGE]

  The semaphore value exceeds SEM_MAX.



------

### NAME

**sem_getvalue()** -- get the value of a semaphore

### SYNOPSIS

```
int sem_getvalue(sem_t *sem, u_int *value);
```

### DESCRIPTION

The sem_getvalue() function returns the current value of the specified semaphore.

### ERRORS

- [EINVAL]

  The specified semaphore is not a valid semaphore.

- [EFAULT]

  The address of *sem* is inaccessible.

- [EPERM]

  The caller task is not an owner of the *sem*, but it does not have CAP_SEMAPHORE capability.



## System

### NAME

**sys_log()** -- log a message

### SYNOPSIS

```
void sys_log(const char *msg);
```

### DESCRIPTION

The sys_log() function puts the specified text message to the predefined device. This function is available only when the kernel is built with debug flag.

### ERRORS

- [EINVAL]

  The message is too long.

- [EFAULT]

  The address of *msg* is inaccessible.



------

### NAME

**sys_panic()** -- fatal error

### SYNOPSIS

```
void sys_panic(const char *msg);
```

### DESCRIPTION

The sys_panic() function shows the panic message and stops the system. The application should use this call only when it detects the unrecoverable error.

### ERRORS

No errors are defined. 



------

### NAME

**sys_info()** -- return system information

### SYNOPSIS

```
int sys_info(int type, void *buf);
```

### DESCRIPTION

The sys_info() function returns the specified system information. The kernel supports the following system infomation.

- INFO_KERNEL - Get kernel information
- INFO_MEMORY - Get memory information
- INFO_SCHED - Get scheduling information
- INFO_THREAD - Get thread information
- INFO_DEVICE - Get device information

### ERRORS

- [EINVAL]

  *type* is not a valid type.

- [EFAULT]

  The address of *buf* is inaccessible.



------

### NAME

**sys_time()** -- return system ticks

### SYNOPSIS

```
int sys_time(u_long *ticks);
```

### DESCRIPTION

The sys_time() function returns the current system ticks.

### ERRORS

- [EFAULT]

  The address of *ticks* is inaccessible.



------

### NAME

**sys_debug()** -- kernel debugging interface

### SYNOPSIS

```
int sys_debug(int cmd, void *data);
```

### DESCRIPTION

The sys_debug() controls the kernel built-in debug functions. The kernel supports the following commands.

- DCMD_LOGSIZE - Return the size of kernel log buffer.
- DCMD_GETLOG  - Return kernel log data.

### ERRORS

- [EINVAL]

  *cmd* is not a valid command.

- [ENOSYS]

  The function is not supported.


Copyright© 2005-2009 Kohsuke Ohtani