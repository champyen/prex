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

#ifndef _SYS_ARCH_H_
#define _SYS_ARCH_H_

#include <sys/types.h>
#include <ipc/ipc.h>
#include <sys/prex.h>

struct sys_mbox_s {
    mutex_t lock;
    cond_t  push_cond;
    cond_t  pop_cond;
    size_t  sz, head, tail;
    void    **ring;
};

typedef thread_t sys_thread_t;
typedef mutex_t  sys_mutex_t;
typedef sem_t    sys_sem_t;
typedef struct sys_mbox_s sys_mbox_t;

#define sys_mutex_valid(m) (*(m) != 0)
#define sys_mutex_set_invalid(m) do *(m) = 0; while (0)

#define sys_sem_valid(m) (*(m) != 0)
#define sys_sem_set_invalid(m) do *(m) = 0; while (0)

#define sys_mbox_valid(m) ((m)->ring != NULL)
#define sys_mbox_set_invalid(m) do (m)->ring = NULL; while (0)

#define sys_msleep(m) timer_sleep((m), 0)

void sys_arch_global_lock(void);
void sys_arch_global_unlock(void);

typedef void (*lwip_thread_fn)(void *arg);
sys_thread_t sys_thread_new(const char *name, lwip_thread_fn thread, void *arg, int stacksize, int prio);
int sys_thread_join(sys_thread_t id);

#define SYS_ARCH_DECL_PROTECT(lev)
#define SYS_ARCH_PROTECT(lev)	sys_arch_global_lock();
#define SYS_ARCH_UNPROTECT(lev)	sys_arch_global_unlock();

#endif /* _SYS_ARCH_H_ */
