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
#include <cpufunc.h>
#include <locore.h>

#ifdef CONFIG_SMP

struct cpu_control cpu_table[CONFIG_SMP_NCPUS];
char ap_boot_stacks[CONFIG_SMP_NCPUS][KSTACKSZ];
static volatile int ready_count = 0;

/*
 * Initialize SMP support for the current CPU (BSP).
 */
void smp_init(void)
{
    struct cpu_control* cpu = &cpu_table[0];
    extern struct thread idle_thread;
    int i;

    /*
     * Setup the BSP's CPU control structure.
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

    atomic_inc(&ready_count);

    /*
     * Start Application Processors (APs).
     */
    DPRINTF(("Starting %d secondary CPUs...\n", CONFIG_SMP_NCPUS - 1));
    for (i = 1; i < CONFIG_SMP_NCPUS; i++) {
        /*
         * Setup AP's CPU control structure.
         * For now, we reuse global stacks for initial boot,
         * but real SMP will need per-CPU stacks.
         */
        cpu_table[i].nest_count = 0;
        cpu_table[i].spl_level = 15;

        /* Wake up the AP using PSCI */
        int ret = hal_psci_cpu_on(i, (paddr_t)&kernel_start);
        if (ret != 0) {
            DPRINTF(("Failed to start CPU %d, returned %d\n", i, ret));
        }
    }

    /* Wait for all CPUs to be ready */
    while (ready_count < CONFIG_SMP_NCPUS)
        ;

    DPRINTF(("All CPUs are ready.\n"));
}

/*
 * Secondary CPU entry point.
 */
void smp_ap_boot(void)
{
    int cpuid = hal_cpu_id();
    struct cpu_control* cpu = &cpu_table[cpuid];

    /*
     * Load the pointer to the CPU control structure into TPIDRPRW.
     */
    __asm__ volatile("mcr p15, 0, %0, c13, c0, 4" : : "r"(cpu));

    /*
     * Initialize interrupt controller for this CPU.
     */
    interrupt_cpu_init();

    /*
     * Increment ready count to signal that this AP has finished
     * early architecture initialization.
     */
    atomic_inc(&ready_count);

    /*
     * Enter idle loop.
     * In Stage 3, we will create real idle threads for APs.
     */
    for (;;)
        cpu_idle();
}

#endif /* CONFIG_SMP */
