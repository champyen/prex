/*
 * Copyright 2018 Phoenix Systems
 * Copyright (c) 2026, Champ Yen (champ.yen@gmail.com)
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

#include "lwip/opt.h"
#include "lwip/sys.h"
#include "arch/sys_arch.h"
#include <stdlib.h>
#include <string.h>

static mutex_t global_lock;
static mutex_t thread_boot_lock;

void sys_init(void) {
    mutex_init(&global_lock);
    mutex_init(&thread_boot_lock);
}

void sys_arch_global_lock(void) {
    mutex_lock(&global_lock);
}

void sys_arch_global_unlock(void) {
    mutex_unlock(&global_lock);
}

/* Mailboxes */
err_t sys_mbox_new(sys_mbox_t *mbox, int size) {
    mbox->ring = malloc(sizeof(void *) * size);
    if (!mbox->ring) return ERR_MEM;
    
    mbox->sz = size;
    mbox->head = mbox->tail = 0;
    mutex_init(&mbox->lock);
    cond_init(&mbox->push_cond);
    cond_init(&mbox->pop_cond);
    return ERR_OK;
}

void sys_mbox_free(sys_mbox_t *mbox) {
    free(mbox->ring);
    mbox->ring = NULL;
}

void sys_mbox_post(sys_mbox_t *mbox, void *msg) {
    mutex_lock(&mbox->lock);
    while (((mbox->tail + 1) % mbox->sz) == mbox->head)
        cond_wait(&mbox->push_cond, &mbox->lock);
    
    mbox->ring[mbox->tail] = msg;
    mbox->tail = (mbox->tail + 1) % mbox->sz;
    cond_signal(&mbox->pop_cond);
    mutex_unlock(&mbox->lock);
}

err_t sys_mbox_trypost(sys_mbox_t *mbox, void *msg) {
    mutex_lock(&mbox->lock);
    if (((mbox->tail + 1) % mbox->sz) == mbox->head) {
        mutex_unlock(&mbox->lock);
        return ERR_MEM;
    }
    mbox->ring[mbox->tail] = msg;
    mbox->tail = (mbox->tail + 1) % mbox->sz;
    cond_signal(&mbox->pop_cond);
    mutex_unlock(&mbox->lock);
    return ERR_OK;
}

u32_t sys_arch_mbox_fetch(sys_mbox_t *mbox, void **msg, u32_t timeout) {
    u32_t start = sys_now();
    mutex_lock(&mbox->lock);
    while (mbox->head == mbox->tail) {
        if (timeout != 0) {
            if (cond_wait(&mbox->pop_cond, &mbox->lock) != 0) {
                mutex_unlock(&mbox->lock);
                return SYS_ARCH_TIMEOUT;
            }
        } else {
            cond_wait(&mbox->pop_cond, &mbox->lock);
        }
    }
    if (msg) *msg = mbox->ring[mbox->head];
    mbox->head = (mbox->head + 1) % mbox->sz;
    cond_signal(&mbox->push_cond);
    mutex_unlock(&mbox->lock);
    return sys_now() - start;
}

/* Semaphores */
err_t sys_sem_new(sys_sem_t *sem, u8_t count) {
    sem_init(sem, count);
    return ERR_OK;
}

void sys_sem_free(sys_sem_t *sem) {
    *sem = 0;
}

void sys_sem_signal(sys_sem_t *sem) {
    sem_post(sem);
}

u32_t sys_arch_sem_wait(sys_sem_t *sem, u32_t timeout) {
    u32_t start = sys_now();
    if (timeout == 0) {
        sem_wait(sem, 0);
    } else {
        if (sem_wait(sem, timeout) != 0)
            return SYS_ARCH_TIMEOUT;
    }
    return sys_now() - start;
}

/* Mutexes */
err_t sys_mutex_new(sys_mutex_t *mutex) {
    mutex_init(mutex);
    return ERR_OK;
}

void sys_mutex_free(sys_mutex_t *mutex) {
    *mutex = 0;
}

void sys_mutex_lock(sys_mutex_t *mutex) {
    mutex_lock(mutex);
}

void sys_mutex_unlock(sys_mutex_t *mutex) {
    mutex_unlock(mutex);
}

/* Threads */
static lwip_thread_fn current_thread_entry;
static void *current_thread_arg;

static void thread_trampoline(void) {
    lwip_thread_fn entry = current_thread_entry;
    void *arg = current_thread_arg;
    mutex_unlock(&thread_boot_lock);
    
    entry(arg);
    
    thread_terminate(thread_self());
}

sys_thread_t sys_thread_new(const char *name, lwip_thread_fn thread, void *arg, int stacksize, int prio) {
    thread_t tid;
    void *stack;
    
    /* Align stack size to page boundary, assuming 4096 */
    stacksize = (stacksize + 4095) & ~4095;
    
    if (vm_allocate(task_self(), &stack, stacksize, 1) != 0)
        return 0;
        
    void *sp = (void *)((u_long)stack + stacksize - sizeof(u_long) * 3);

    if (thread_create(task_self(), &tid) != 0) {
        vm_free(task_self(), stack);
        return 0;
    }

    mutex_lock(&thread_boot_lock);
    current_thread_entry = thread;
    current_thread_arg = arg;

    thread_load(tid, thread_trampoline, sp);
    thread_resume(tid);

    /* Wait for the trampoline to consume the arguments */
    mutex_lock(&thread_boot_lock);
    mutex_unlock(&thread_boot_lock);

    return tid;
}

int sys_thread_join(sys_thread_t id) { return 0; }

u32_t sys_arch_mbox_tryfetch(sys_mbox_t *mbox, void **msg) {
    mutex_lock(&mbox->lock);
    if (mbox->head == mbox->tail) {
        mutex_unlock(&mbox->lock);
        return SYS_MBOX_EMPTY;
    }
    if (msg) *msg = mbox->ring[mbox->head];
    mbox->head = (mbox->head + 1) % mbox->sz;
    cond_signal(&mbox->push_cond);
    mutex_unlock(&mbox->lock);
    return 0;
}

err_t sys_mbox_trypost_fromisr(sys_mbox_t *mbox, void *msg) {
    return sys_mbox_trypost(mbox, msg);
}

