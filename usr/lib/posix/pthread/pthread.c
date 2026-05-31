/*-
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
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

#include <sys/prex.h>
#include <sys/param.h>
#include <pthread.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>

/*
 * Internal thread control block
 */
struct __pthread
{
    thread_t kthread;              /* Prex kernel thread handle */
    void* (*start_routine)(void*); /* User function */
    void* arg;                     /* Argument */
    void* retval;                  /* Return value */
    void* stack_base;              /* Stack base address */
    size_t stack_size;             /* Stack size */
    int detached;                  /* Detached state */
    int terminated;                /* Termination state */
    sem_t join_sem;                /* Semaphore for pthread_join */
    struct __pthread* next;        /* List link */
};

static struct __pthread* pthread_list = NULL;
static struct __pthread* pthread_reap_list = NULL;
static mutex_t pthread_list_lock = MUTEX_INITIALIZER;
static int pthread_initialized = 0;

/*
 * Reaper for detached threads
 */
static void pthread_reap_garbage(void)
{
    struct __pthread* p;
    struct __pthread* next;

    mutex_lock(&pthread_list_lock);
    p = pthread_reap_list;
    pthread_reap_list = NULL;
    mutex_unlock(&pthread_list_lock);

    while (p != NULL) {
        next = p->next;
        if (p->stack_base != NULL) {
            vm_free(task_self(), p->stack_base);
        }
        sem_destroy(&p->join_sem);
        free(p);
        p = next;
    }
}

/*
 * Trampoline for new threads
 */
static void pthread_trampoline(void)
{
    pthread_t self = pthread_self();
    if (self == NULL) {
        sys_panic("pthread: trampoline failed to find self");
    }

    self->retval = self->start_routine(self->arg);
    pthread_exit(self->retval);
}

/*
 * Initialize pthread system
 */
void __pthread_init(void)
{
    struct __pthread* main_thread;

    if (pthread_initialized)
        return;

    /* Create TCB for main thread */
    main_thread = malloc(sizeof(struct __pthread));
    if (main_thread == NULL)
        sys_panic("pthread: failed to allocate main TCB");

    memset(main_thread, 0, sizeof(struct __pthread));
    main_thread->kthread = thread_self();
    main_thread->detached = 0;
    main_thread->terminated = 0;
    sem_init(&main_thread->join_sem, 0);

    main_thread->next = pthread_list;
    pthread_list = main_thread;

    pthread_initialized = 1;
}

pthread_t pthread_self(void)
{
    thread_t kt = thread_self();
    struct __pthread* p;

    if (!pthread_initialized)
        __pthread_init();

    mutex_lock(&pthread_list_lock);
    for (p = pthread_list; p != NULL; p = p->next) {
        if (p->kthread == kt) {
            mutex_unlock(&pthread_list_lock);
            return p;
        }
    }
    mutex_unlock(&pthread_list_lock);
    return NULL;
}

int pthread_create(pthread_t* thread, const pthread_attr_t* attr, void* (*start_routine)(void*), void* arg)
{
    struct __pthread* p;
    size_t stack_size = 32768; /* Default 32KB */
    void* stack_base;
    thread_t kt;
    int error;

    /* Reap any terminated detached threads safely from the caller context */
    pthread_reap_garbage();

    if (!pthread_initialized)
        __pthread_init();

    if (attr != NULL) {
        if (attr->stacksize > 0)
            stack_size = attr->stacksize;
    }

    p = malloc(sizeof(struct __pthread));
    if (p == NULL)
        return ENOMEM;

    memset(p, 0, sizeof(struct __pthread));

    /* Allocate stack */
    if (vm_allocate(task_self(), &stack_base, stack_size, 1) != 0) {
        free(p);
        return ENOMEM;
    }

    p->stack_base = stack_base;
    p->stack_size = stack_size;
    p->start_routine = start_routine;
    p->arg = arg;
    p->detached = (attr && attr->detachstate == PTHREAD_CREATE_DETACHED);
    p->terminated = 0;
    sem_init(&p->join_sem, 0);

    /* Create kernel thread */
    if ((error = thread_create(task_self(), &kt)) != 0) {
        vm_free(task_self(), stack_base);
        free(p);
        return error;
    }
    p->kthread = kt;

    /* Load thread */
    if ((error = thread_load(kt, pthread_trampoline, (void*)((u_long)stack_base + stack_size))) != 0) {
        thread_terminate(kt);
        vm_free(task_self(), stack_base);
        free(p);
        return error;
    }

    /* Add to list */
    mutex_lock(&pthread_list_lock);
    p->next = pthread_list;
    pthread_list = p;
    mutex_unlock(&pthread_list_lock);

    if (thread != NULL)
        *thread = p;

    /* Start execution */
    thread_resume(kt);

    return 0;
}

void pthread_exit(void* retval)
{
    pthread_t self = pthread_self();

    if (self == NULL)
        thread_terminate(thread_self());

    self->retval = retval;
    self->terminated = 1;

    if (self->detached) {
        /* Remove from active list and prepend to reap list */
        struct __pthread *p, *prev;
        mutex_lock(&pthread_list_lock);
        prev = NULL;
        for (p = pthread_list; p != NULL; prev = p, p = p->next) {
            if (p == self) {
                if (prev == NULL)
                    pthread_list = p->next;
                else
                    prev->next = p->next;
                break;
            }
        }
        self->next = pthread_reap_list;
        pthread_reap_list = self;
        mutex_unlock(&pthread_list_lock);
    } else {
        /* Signal joiners */
        sem_post(&self->join_sem);
    }

    thread_terminate(self->kthread);
    /* NOTREACHED */
}

int pthread_join(pthread_t thread, void** retval)
{
    struct __pthread *p, *prev;

    if (thread == NULL || thread->detached)
        return EINVAL;

    /* Wait for termination */
    sem_wait(&thread->join_sem, 0);

    if (retval != NULL)
        *retval = thread->retval;

    /* Remove from active list */
    mutex_lock(&pthread_list_lock);
    prev = NULL;
    for (p = pthread_list; p != NULL; prev = p, p = p->next) {
        if (p == thread) {
            if (prev == NULL)
                pthread_list = p->next;
            else
                prev->next = p->next;
            break;
        }
    }
    mutex_unlock(&pthread_list_lock);

    /* Free resources */
    if (thread->stack_base != NULL) {
        vm_free(task_self(), thread->stack_base);
    }
    sem_destroy(&thread->join_sem);
    free(thread);

    return 0;
}

int pthread_detach(pthread_t thread)
{
    if (thread == NULL)
        return EINVAL;
    thread->detached = 1;
    return 0;
}

int pthread_yield(void)
{
    thread_yield();
    return 0;
}

/*
 * Mutex implementation
 */
int pthread_mutex_init(pthread_mutex_t* mutex, const pthread_mutexattr_t* attr)
{
    if (mutex == NULL)
        return EINVAL;
    mutex_init(&mutex->lock);
    mutex->is_initialized = 1;
    return 0;
}

int pthread_mutex_destroy(pthread_mutex_t* mutex)
{
    if (mutex == NULL || !mutex->is_initialized)
        return EINVAL;
    mutex_destroy(&mutex->lock);
    mutex->is_initialized = 0;
    return 0;
}

int pthread_mutex_lock(pthread_mutex_t* mutex)
{
    if (mutex == NULL)
        return EINVAL;
    if (!mutex->is_initialized)
        pthread_mutex_init(mutex, NULL);
    return mutex_lock(&mutex->lock);
}

int pthread_mutex_trylock(pthread_mutex_t* mutex)
{
    if (mutex == NULL)
        return EINVAL;
    if (!mutex->is_initialized)
        pthread_mutex_init(mutex, NULL);
    return mutex_trylock(&mutex->lock);
}

int pthread_mutex_unlock(pthread_mutex_t* mutex)
{
    if (mutex == NULL || !mutex->is_initialized)
        return EINVAL;
    return mutex_unlock(&mutex->lock);
}

/*
 * Condition variable implementation
 */
int pthread_cond_init(pthread_cond_t* cond, const pthread_condattr_t* attr)
{
    if (cond == NULL)
        return EINVAL;
    cond_init(&cond->cond);
    cond->is_initialized = 1;
    return 0;
}

int pthread_cond_destroy(pthread_cond_t* cond)
{
    if (cond == NULL || !cond->is_initialized)
        return EINVAL;
    cond_destroy(&cond->cond);
    cond->is_initialized = 0;
    return 0;
}

int pthread_cond_wait(pthread_cond_t* cond, pthread_mutex_t* mutex)
{
    if (cond == NULL || mutex == NULL)
        return EINVAL;
    if (!cond->is_initialized)
        pthread_cond_init(cond, NULL);
    return cond_wait(&cond->cond, &mutex->lock);
}

int pthread_cond_signal(pthread_cond_t* cond)
{
    if (cond == NULL || !cond->is_initialized)
        return EINVAL;
    return cond_signal(&cond->cond);
}

int pthread_cond_broadcast(pthread_cond_t* cond)
{
    if (cond == NULL || !cond->is_initialized)
        return EINVAL;
    return cond_broadcast(&cond->cond);
}
