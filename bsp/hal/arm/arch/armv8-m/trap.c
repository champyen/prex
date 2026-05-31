/*-
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
 * All rights reserved.
 */

#include <kernel.h>
#include <trap.h>
#include <exception.h>

void trap_handler(struct cpu_regs *regs)
{
    panic("Trap handler not implemented");
}

#ifdef DEBUG
void trap_dump(struct cpu_regs* r)
{
    printf("Trap frame: %p\n", r);
    printf(" r0  %08x r1  %08x r2  %08x r3  %08x\n", r->r0, r->r1, r->r2, r->r3);
    printf(" r4  %08x r5  %08x r6  %08x r7  %08x\n", r->r4, r->r5, r->r6, r->r7);
    printf(" r8  %08x r9  %08x r10 %08x r11 %08x\n", r->r8, r->r9, r->r10, r->r11);
    printf(" r12 %08x sp  %08x lr  %08x pc  %08x\n", r->r12, r->sp, r->lr, r->pc);
    printf(" xPSR %08x\n", r->cpsr);
}
#endif
