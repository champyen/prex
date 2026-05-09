/*-
 * Copyright (c) 2026, Gemini CLI
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the author nor the names of any co-contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#ifndef _SMP_H
#define _SMP_H

#include <conf/config.h>
#include <types.h>
#include <atomic.h>
#include <hal.h>
#include <deadlock.h>

#ifdef CONFIG_KD
#include <timer.h>
#endif

/*
 * SAL Spinlock Interface.
 * Currently focused on TAS (Test-And-Set) implementation.
 */

#ifdef CONFIG_SMP

typedef volatile int spinlock_t;
#define SPINLOCK_INITIALIZER 0

#define smp_processor_id() (hal_get_cpu_control()->cpu_id)

extern struct cpu_control cpu_table[];

static inline void spinlock_init(spinlock_t* lock)
{
    *lock = 0;
}

static inline void spinlock_lock(spinlock_t* lock)
{
#ifdef CONFIG_KD
    uint32_t start = (uint32_t)timer_ticks();
    uint32_t iters = 0;
#endif
    while (__sync_lock_test_and_set(lock, 1)) {
#ifdef CONFIG_KD
        deadlock_check_spin((void*)lock, start, &iters);
#endif
        while (*lock)
            ; /* Spin */
    }
    deadlock_record_lock((void*)lock, LOCK_TYPE_SPIN);
}

static inline void spinlock_unlock(spinlock_t* lock)
{
    deadlock_record_unlock((void*)lock);
    __sync_lock_release(lock);
}

static inline void spinlock_lock_irq(spinlock_t* lock, int* s)
{
    *s = splhigh();
    spinlock_lock(lock);
}

static inline void spinlock_unlock_irq(spinlock_t* lock, int s)
{
    spinlock_unlock(lock);
    splx(s);
}

#else /* !CONFIG_SMP */

typedef int spinlock_t;
#define SPINLOCK_INITIALIZER 0

#define smp_processor_id() 0

#define spinlock_init(lock) (void)0
#define spinlock_lock(lock) (void)0
#define spinlock_unlock(lock) (void)0
#define spinlock_lock_irq(lock, s) (*(s) = splhigh())
#define spinlock_unlock_irq(lock, s) splx(s)

#endif /* CONFIG_SMP */

#endif /* !_SMP_H */
