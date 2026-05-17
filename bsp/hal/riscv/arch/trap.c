/*-
 * Copyright (c) 2005-2009, Kohsuke Ohtani
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
 * trap.c - exception handling for RISC-V (Supervisor Mode)
 */

#include <kernel.h>
#include <hal.h>
#include <exception.h>
#include <cpu.h>
#include <trap.h>
#include <context.h>

#ifdef DEBUG
static char* const trap_name[] = {
    "Instruction address misaligned",
    "Instruction access fault",
    "Illegal instruction",
    "Breakpoint",
    "Load address misaligned",
    "Load access fault",
    "Store/AMO address misaligned",
    "Store/AMO access fault",
    "Environment call from U-mode",
    "Environment call from S-mode",
    "Reserved",
    "Environment call from M-mode",
    "Instruction page fault",
    "Load page fault",
    "Reserved",
    "Store/AMO page fault",
};
#define MAXTRAP (sizeof(trap_name) / sizeof(void*))
#endif

/*
 * Trap handler
 */
void trap_handler(struct cpu_regs* regs)
{
    uint32_t cause = regs->cause;

    if (cause & 0x80000000) {
        /* Interrupt */
        extern void riscv_irq_handler(uint32_t cause);
        riscv_irq_handler(cause & 0x7fffffff);
    } else {
        if (cause == 8 || cause == 9) {
            if (cause == 8) printf("U%d ", regs->a7);
            /* System call (ECALL from U-mode or S-mode) */
            extern register_t syscall_handler(register_t, register_t, register_t, register_t, register_t);
            /* Skip ecall instruction (4 bytes) */
            regs->epc += 4;
            regs->a0 = syscall_handler(regs->a0, regs->a1, regs->a2, regs->a3, regs->a7);
        } else {
            /* Hardware exception */
#ifdef DEBUG
            printf("TRAP: %s at %08x\n", (cause < MAXTRAP) ? trap_name[cause] : "Unknown", regs->epc);
            if (cause == 2) {
                printf("Code at pc: %08x\n", *(uint32_t*)regs->epc);
            }
            trap_dump(regs);
#endif
            exception_mark(cause);
            exception_deliver();
        }
    }
}

/*
 * trap_dump - show register context
 */
#ifdef DEBUG
void trap_dump(struct cpu_regs* r)
{
    printf("Trap frame %08x\n", (uint32_t)r);
    printf(" ra  %08x sp  %08x gp  %08x tp  %08x\n", r->ra, r->sp, r->gp, r->tp);
    printf(" t0  %08x t1  %08x t2  %08x s0  %08x\n", r->t0, r->t1, r->t2, r->s0);
    printf(" s1  %08x a0  %08x a1  %08x a2  %08x\n", r->s1, r->a0, r->a1, r->a2);
    printf(" a3  %08x a4  %08x a5  %08x a6  %08x\n", r->a3, r->a4, r->a5, r->a6);
    printf(" a7  %08x s2  %08x s3  %08x s4  %08x\n", r->a7, r->s2, r->s3, r->s4);
    printf(" pc  %08x status %08x cause %08x badaddr %08x\n", r->epc, r->status, r->cause, r->badaddr);
}
#endif
