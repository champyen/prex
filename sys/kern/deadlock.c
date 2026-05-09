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

/*
 * deadlock.c - Proactive SMP/UP Deadlock Detector (Verified Turn 85 Version)
 */

#include <kernel.h>
#include <thread.h>
#include <sched.h>
#include <timer.h>
#include <hal.h>
#include <smp.h>
#include <sync.h>
#include <deadlock.h>

#if defined(DEBUG) && defined(CONFIG_KD)

static struct deadlock_state cpu_states[DEADLOCK_MAX_CPUS];
static uint32_t global_timer_ticks = 0;
extern spinlock_t log_lock;

#define MAX_WAITERS 64
struct wait_record {
    thread_t thread;
    void *resource;     /* Mutex or Event */
    const char *name;
    uint32_t start_tick;
    int active;
};
static struct wait_record wait_records[MAX_WAITERS];

void deadlock_init(void)
{
    int i;
    printf("Deadlock Detector: Active (1s timeout)\n");
    for (i = 0; i < DEADLOCK_MAX_CPUS; i++) {
        cpu_states[i].depth = 0;
        cpu_states[i].in_check = 0;
        cpu_states[i].last_tick = (uint32_t)timer_ticks();
        cpu_states[i].loop_cnt = 0;
    }
    for (i = 0; i < MAX_WAITERS; i++) {
        wait_records[i].active = 0;
    }
}

/*
 * Record a lock acquisition
 */
void deadlock_record_lock(void *lock, int type)
{
    int cpuid = smp_processor_id();
    struct deadlock_state *ds = &cpu_states[cpuid];

    if (ds->in_check) return;
    ds->in_check = 1;

    if (ds->depth < MAX_LOCK_STACK) {
        struct lock_record *lr = &ds->stack[ds->depth];
        lr->lock_addr = lock;
        lr->type = type;
        lr->holder = curthread;
        lr->cpu_id = cpuid;
        lr->acquire_time = (uint32_t)timer_ticks();
        ds->depth++;
    }

    ds->in_check = 0;
}

/*
 * Record a lock release
 */
void deadlock_record_unlock(void *lock)
{
    int cpuid = smp_processor_id();
    struct deadlock_state *ds = &cpu_states[cpuid];
    int i;

    if (ds->in_check) return;
    ds->in_check = 1;

    /* Search from top of stack */
    for (i = ds->depth - 1; i >= 0; i--) {
        if (ds->stack[i].lock_addr == lock) {
            if (i < ds->depth - 1) {
                int k;
                for (k = i; k < ds->depth - 1; k++) {
                    ds->stack[k] = ds->stack[k + 1];
                }
            }
            ds->depth--;
            break;
        }
    }

    ds->in_check = 0;
}

/*
 * Check for spinlock timeout (Differential Watchdog)
 */
void deadlock_check_spin(void *lock, uint32_t start_tick, uint32_t *iters)
{
    uint32_t now = (uint32_t)timer_ticks();

    if (now != global_timer_ticks) {
        *iters = 0;
        global_timer_ticks = now;
        return;
    }

    (*iters)++;

    if (*iters > SPIN_TIMEOUT_ITER) {
        log_lock = 0;
        printf("\n*** HARD STALL DETECTED: CPU %d spinning with blocked timer ***\n", 
               smp_processor_id());
        printf("Lock: %p, Iters: %u\n", lock, *iters);
        deadlock_dump();
        panic("Deadlock");
    }
}

/*
 * Generic loop watchdog
 */
void deadlock_check_loop(const char *func, uint32_t *iters)
{
    uint32_t now = (uint32_t)timer_ticks();

    if (now != global_timer_ticks) {
        *iters = 0;
        global_timer_ticks = now;
        return;
    }

    (*iters)++;
    if (*iters > SPIN_TIMEOUT_ITER) {
        log_lock = 0;
        printf("\n*** STALL DETECTED: Infinite loop in %s ***\n", func);
        deadlock_dump();
        panic("Loop Stall");
    }
}

/*
 * Wait tracking
 */
void deadlock_sleep(void *resource, const char *name)
{
    int i;
    for (i = 0; i < MAX_WAITERS; i++) {
        if (!wait_records[i].active) {
            wait_records[i].thread = curthread;
            wait_records[i].resource = resource;
            wait_records[i].name = name;
            wait_records[i].start_tick = (uint32_t)timer_ticks();
            wait_records[i].active = 1;
            break;
        }
    }
}

void deadlock_stop_sleep(void)
{
    int i;
    for (i = 0; i < MAX_WAITERS; i++) {
        if (wait_records[i].active && wait_records[i].thread == curthread) {
            wait_records[i].active = 0;
            break;
        }
    }
}

/*
 * Mutex dependency tracking (Proactive Monitor)
 */
void deadlock_mutex_wait(mutex_t m, thread_t waiter)
{
    deadlock_sleep(m, "mutex");
}

void deadlock_mutex_stop_wait(thread_t waiter)
{
    deadlock_stop_sleep();
}

/*
 * Heartbeat: Called by each CPU on every timer tick.
 */
void deadlock_heartbeat(void)
{
    int cpuid = smp_processor_id();
    cpu_states[cpuid].last_tick = (uint32_t)timer_ticks();
    cpu_states[cpuid].loop_cnt++;
    global_timer_ticks = cpu_states[cpuid].last_tick;
}

/*
 * Proactive check: Scans all CPUs for stalls.
 */
void deadlock_proactive_check(void)
{
    static uint32_t last_check = 0;
    static uint32_t timer_stuck_cnt = 0;
    uint32_t now = (uint32_t)timer_ticks();
    int i;

    if (now == last_check && now != 0) {
        if (++timer_stuck_cnt > 100) {
            log_lock = 0;
            printf("\n*** HARD STALL DETECTED: System timer (lbolt) has stopped! ***\n");
            deadlock_dump();
            panic("Timer Stall");
        }
    } else {
        timer_stuck_cnt = 0;
        last_check = now;
    }

    /* Check for lost wakeups / orphaned resources (1 second timeout) */
    for (i = 0; i < MAX_WAITERS; i++) {
        if (wait_records[i].active) {
            if (now - wait_records[i].start_tick > CONFIG_HZ) {
                log_lock = 0;
                printf("\n*** DEADLOCK DETECTED: Lost Wakeup / Resource Stall ***\n");
                printf("Thread %p has been waiting on %s %p for %u ticks!\n", 
                       wait_records[i].thread, wait_records[i].name, 
                       wait_records[i].resource, now - wait_records[i].start_tick);
                deadlock_dump();
                panic("Sleep Deadlock");
            }
        }
    }
}

/*
 * Dump state
 */
void deadlock_dump(void)
{
    int i, j;
    const char *types[] = {"NONE", "SPIN", "MUTEX", "BKL"};

    printf("\nLock Status:\n");
    printf("CPU Depth Thread   Type  Lock Address\n");
    printf("--- ----- -------- ----- ------------\n");

    for (i = 0; i < DEADLOCK_MAX_CPUS; i++) {
        struct deadlock_state *ds = &cpu_states[i];
        if (ds->depth == 0) continue;
        for (j = 0; j < ds->depth; j++) {
            struct lock_record *lr = &ds->stack[j];
            printf("%3d %5d %08lx %-5s %p\n", 
                   i, j, (long)lr->holder, types[lr->type], lr->lock_addr);
        }
    }

    printf("\nWait Status:\n");
    for (i = 0; i < MAX_WAITERS; i++) {
        if (wait_records[i].active) {
            printf("Thread %p waiting on %s %p (start %u)\n", 
                   wait_records[i].thread, wait_records[i].name, 
                   wait_records[i].resource, wait_records[i].start_tick);
        }
    }
}

#endif /* DEBUG && CONFIG_KD */
