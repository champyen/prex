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

#ifndef _ATOMIC_H
#define _ATOMIC_H

#include <sys/cdefs.h>

#ifdef __arm__
#if defined(CONFIG_ARMV7A)
#define memory_barrier() __asm__ volatile("dmb ish" : : : "memory")
#elif defined(CONFIG_ARMV6)
#define memory_barrier() __asm__ volatile("mcr p15, 0, %0, c7, c10, 5" : : "r"(0) : "memory")
#else
#define memory_barrier() __asm__ volatile("mcr p15, 0, %0, c7, c10, 4" : : "r"(0) : "memory")
#endif
#else
#define memory_barrier() __sync_synchronize()
#endif

static inline int atomic_cas(volatile int* ptr, int oldval, int newval)
{
    return __sync_bool_compare_and_swap(ptr, oldval, newval);
}

static inline int atomic_add(volatile int* ptr, int val)
{
    return __sync_add_and_fetch(ptr, val);
}

static inline int atomic_sub(volatile int* ptr, int val)
{
    return __sync_sub_and_fetch(ptr, val);
}

static inline int atomic_inc(volatile int* ptr)
{
    return __sync_add_and_fetch(ptr, 1);
}

static inline int atomic_dec(volatile int* ptr)
{
    return __sync_sub_and_fetch(ptr, 1);
}

static inline int atomic_read(volatile int* ptr)
{
    int val = *ptr;
    memory_barrier();
    return val;
}

static inline void atomic_set(volatile int* ptr, int val)
{
    memory_barrier();
    *ptr = val;
    memory_barrier();
}

#endif /* !_ATOMIC_H */
