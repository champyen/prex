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

#ifndef _DEADLOCK_H
#define _DEADLOCK_H

#include <types.h>

/*
 * Lock types for tracking
 */
#define LOCK_TYPE_SPIN  1
#define LOCK_TYPE_MUTEX 2
#define LOCK_TYPE_BKL   3

#define MAX_LOCK_STACK   8
#define SPIN_TIMEOUT_MS  1000
#define SPIN_TIMEOUT_ITER 1000000 /* Verified limit from successful run */

/*
 * Record of a held lock
 */
struct lock_record {
    void        *lock_addr;     /* Address of the lock object */
    int         type;           /* LOCK_TYPE_* */
    thread_t    holder;         /* Thread holding the lock */
    int         cpu_id;         /* CPU holding the lock */
    uint32_t    acquire_time;   /* Tick count at acquisition */
};

/*
 * Per-CPU deadlock detection state
 */
struct deadlock_state {
    struct lock_record  stack[MAX_LOCK_STACK];
    int                 depth;
    int                 in_check;   /* Re-entrancy guard */
    uint32_t            last_tick;  /* Last heartbeat tick */
    uint32_t            loop_cnt;   /* Running loop counter for stall detection */
};

#ifdef CONFIG_SMP
#define DEADLOCK_MAX_CPUS CONFIG_SMP_NCPUS
#else
#define DEADLOCK_MAX_CPUS 1
#endif

#if defined(DEBUG) && defined(CONFIG_KD)

void deadlock_init(void);
void deadlock_check_spin(void *lock, uint32_t start_tick, uint32_t *iters);
void deadlock_record_lock(void *lock, int type);
void deadlock_record_unlock(void *lock);
void deadlock_dump(void);

/* Activity hooks */
void deadlock_check_loop(const char *func, uint32_t *iters);
void deadlock_heartbeat(void);
void deadlock_proactive_check(void);

/* Sleep tracking (Mutexes, Semaphores, Events) */
void deadlock_sleep(void *resource, const char *name);
void deadlock_stop_sleep(void);

/* Mutex-specific wrappers */
void deadlock_mutex_wait(mutex_t m, thread_t waiter);
void deadlock_mutex_stop_wait(thread_t waiter);

#else

#define deadlock_init()             ((void)0)
#define deadlock_check_spin(l, t, i) ((void)0)
#define deadlock_check_loop(f, i)    ((void)0)
#define deadlock_record_lock(l, t)   ((void)0)
#define deadlock_record_unlock(l)    ((void)0)
#define deadlock_dump()             ((void)0)
#define deadlock_heartbeat()         ((void)0)
#define deadlock_proactive_check()   ((void)0)
#define deadlock_sleep(r, n)         ((void)0)
#define deadlock_stop_sleep()        ((void)0)
#define deadlock_mutex_wait(m, w)    ((void)0)
#define deadlock_mutex_stop_wait(w)  ((void)0)

#endif /* DEBUG && CONFIG_KD */

#endif /* !_DEADLOCK_H */
