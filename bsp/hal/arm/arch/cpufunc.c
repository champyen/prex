/*-
 * Copyright (c) 2005-2008, Kohsuke Ohtani
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
 * cpufunc.c - CPU specific functions for ARMv4~v6
 */

#include <sys/types.h>
#include <cpufunc.h>

__attribute__((naked)) void cpu_idle(void)
{
    __asm__ volatile(
#if defined(CONFIG_ARMV6)
        "wfi\n"
#endif
        "bx lr");
}

__attribute__((naked)) int get_faultstatus(void)
{
    __asm__ volatile(
        "mrc p15, 0, r0, c5, c0, 0\n"
        "bx  lr");
}

__attribute__((naked)) void* get_faultaddress(void)
{
    __asm__ volatile(
        "mrc p15, 0, r0, c6, c0, 0\n"
        "bx  lr");
}

__attribute__((naked)) paddr_t get_ttb(void)
{
    __asm__ volatile(
        "mrc p15, 0, r0, c2, c0, 0\n"
        "bx  lr");
}

__attribute__((naked)) void set_ttb(paddr_t ttb)
{
    __asm__ volatile(
        "mcr p15, 0, r0, c2, c0, 0\n"
        "mov r0, #0\n"
        "mcr p15, 0, r0, c8, c7, 0\n" /* invalidate I+D TLBs */
        "bx  lr");
}

__attribute__((naked)) void switch_ttb(paddr_t ttb)
{
    __asm__ volatile(
        "mov r1, #0\n"
        "mcr p15, 0, r1, c7, c5, 0\n"  /* flush I cache */
        "mcr p15, 0, r1, c7, c6, 0\n"  /* flush D cache */
        "mcr p15, 0, r1, c7, c10, 4\n" /* drain the write buffer */
        "mcr p15, 0, r0, c2, c0, 0\n"  /* load new TTB */
        "mcr p15, 0, r1, c8, c7, 0\n"  /* invalidate I+D TLBs */
        "bx  lr");
}

__attribute__((naked)) void flush_tlb(void)
{
    __asm__ volatile(
        "mov r0, #0\n"
        "mcr p15, 0, r0, c8, c7, 0\n"
        "bx  lr");
}

__attribute__((naked)) void flush_cache(void)
{
    __asm__ volatile(
        "mov r0, #0\n"
        "mcr p15, 0, r0, c7, c5, 0\n"  /* flush I cache */
        "mcr p15, 0, r0, c7, c6, 0\n"  /* flush D cache */
        "mcr p15, 0, r0, c7, c10, 4\n" /* drain write buffer */
        "bx  lr");
}

__attribute__((naked)) void cpu_barrier(void)
{
    __asm__ volatile(
        "mov r0, #0\n"
        "mcr p15, 0, r0, c7, c10, 4\n" /* Drain write buffer */
        "mcr p15, 0, r0, c7, c5, 4\n"  /* Prefetch flush */
        "bx  lr");
}

__attribute__((naked)) uint32_t hal_cpu_id(void)
{
    __asm__ volatile(
#if defined(CONFIG_ARMV6)
        "mrc p15, 0, r0, c0, c0, 5\n"
        "and r0, r0, #0xff\n"
#else
        "mov r0, #0\n"
#endif
        "bx  lr");
}

/* Not supported on ARMv4~v6 */
void set_vbar(vaddr_t vbar) {}
uint32_t get_cntfrq(void) { return 0; }
void set_cntp_tval_reg(uint32_t val) {}
void set_cntp_ctl_reg(uint32_t val) {}
uint32_t get_cntp_ctl_reg(void) { return 0; }
int hal_cpu_start(uint32_t cpuid, paddr_t entry) { return -1; }
