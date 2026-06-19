#ifndef _ZIG_KERNEL_H
#define _ZIG_KERNEL_H

#include <conf/config.h>

/*
 * Rename problematic macros/inline functions that Zig cannot translate
 */

#define curthread __broken_curthread
#define list_init __broken_list_init
#define queue_init __broken_queue_init
#define EXC_DFL __broken_EXC_DFL
#define deadlock_record_lock __broken_deadlock_record_lock
#define deadlock_record_unlock __broken_deadlock_record_unlock
#define deadlock_sleep __broken_deadlock_sleep
#define deadlock_stop_sleep __broken_deadlock_stop_sleep
#define deadlock_mutex_wait __broken_deadlock_mutex_wait
#define deadlock_mutex_stop_wait __broken_deadlock_mutex_stop_wait
#define spinlock_lock __broken_spinlock_lock
#define spinlock_unlock __broken_spinlock_unlock
#define spinlock_lock_irq __broken_spinlock_lock_irq
#define spinlock_unlock_irq __broken_spinlock_unlock_irq
#define event_init __broken_event_init

/*
 * Include base types first
 */
#include <sys/types.h>
#include <sys/list.h>
#include <sys/queue.h>
#include <event.h>

/*
 * Include standard kernel headers
 */
#include <kernel.h>
#include <sched.h>
#include <kmem.h>
#include <vm.h>
#include <irq.h>
#include <page.h>
#include <ipc.h>
#include <sync.h>
#include <device.h>
#include <system.h>
#include <hal.h>
#include <cpufunc.h>
#include <smp.h>
#include <deadlock.h>
#include <exception.h>
#include <sys/dbgctl.h>
#include <mmu.h>

/*
 * Restore renamed symbols as extern functions for Zig to link against
 */
#undef curthread
#undef list_init
#undef queue_init
#undef EXC_DFL
#undef deadlock_record_lock
#undef deadlock_record_unlock
#undef deadlock_sleep
#undef deadlock_stop_sleep
#undef deadlock_mutex_wait
#undef deadlock_mutex_stop_wait
#undef spinlock_lock
#undef spinlock_unlock
#undef spinlock_lock_irq
#undef spinlock_unlock_irq
#undef event_init

/*
 * Memory barrier wrapper for Zig
 */
#include <atomic.h>

void zig_memory_barrier(void);

#endif /* !_ZIG_KERNEL_H */
