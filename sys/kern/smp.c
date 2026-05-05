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
 * smp.c - Symmetric Multiprocessing support.
 */

#include <kernel.h>
#include <thread.h>
#include <smp.h>
#include <machine/syspage.h>

#ifdef CONFIG_SMP

struct cpu_control cpu_table[CONFIG_SMP_NCPUS];

/*
 * Initialize SMP support for the current CPU (BSP).
 */
void smp_init(void)
{
    struct cpu_control* cpu = &cpu_table[0];
    extern struct thread idle_thread;

    /*
     * Setup the BSP's CPU control structure.
     * Use the global idle_thread as the initial boot thread.
     */
    cpu->active_thread = &idle_thread;
    cpu->idle_thread = &idle_thread;
    cpu->nest_count = 0;
    cpu->spl_level = 15;
    cpu->int_stack = (void*)(INTSTKTOP - 0x100);

    /*
     * Load the pointer to the CPU control structure into TPIDRPRW.
     */
    __asm__ volatile("mcr p15, 0, %0, c13, c0, 4" : : "r"(cpu));
}

#endif /* CONFIG_SMP */
