/*-
 * Copyright (c) 2008, Kohsuke Ohtani
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

/*
 * cpufunc.c - CPU specific functions for PowerPC
 */

#include <sys/types.h>
#include <cpufunc.h>

uint32_t get_decr(void)
{
    uint32_t val;
    __asm__ volatile("mfdec %0" : "=r"(val));
    return val;
}

void set_decr(uint32_t val)
{
    __asm__ volatile("mtdec %0" : : "r"(val));
}

void cpu_idle(void)
{
    /* Enable interrupts and set low power mode */
    uint32_t msr;
    __asm__ volatile("mfmsr %0\n"
                     "ori %0, %0, 0x8000\n" /* MSR_EE */
                     "mtmsr %0\n"
                     "isync\n"
                     "sync\n"
                     "mfmsr %0\n"
                     "oris %0, %0, 0x0040\n" /* MSR_POW */
                     "mtmsr %0\n"
                     "isync"
                     : "=&r"(msr));
}
