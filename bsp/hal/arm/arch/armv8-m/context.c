/*-
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
 * All rights reserved.
 */

#include <kernel.h>
#include <kmem.h>
#include <cpu.h>
#include <context.h>
#include <locore.h>
#include <trap.h>

void context_set(context_t ctx, int type, register_t val)
{
    struct kern_regs* k;
    struct cpu_regs* u;

    k = &ctx->kregs;

    switch (type) {
    case CTX_KSTACK:
        ctx->uregs = (struct cpu_regs*)((vaddr_t)val - sizeof(struct cpu_regs));
        k->sp = (uint32_t)ctx->uregs;

        u = ctx->uregs;
        u->r0 = 0;
        u->svc_sp = (uint32_t)val;
        u->cpsr = 0x01000000; /* Default xPSR: Thumb bit set */
        break;

    case CTX_KENTRY:
        k->lr = (uint32_t)&kernel_thread_entry;
        k->r4 = (uint32_t)val;
        break;

    case CTX_KARG:
        k->r5 = (uint32_t)val;
        break;

    case CTX_USTACK:
        u = ctx->uregs;
        u->sp = (uint32_t)val;
        break;

    case CTX_UENTRY:
        u = ctx->uregs;
        u->cpsr = 0x01000000; /* Thumb bit */
        u->pc = (uint32_t)val;
        break;

    case CTX_UARG:
        u = ctx->uregs;
        u->r0 = (uint32_t)val;
        break;

    default:
        break;
    }
}

void context_switch(context_t prev, context_t next)
{
    cpu_switch(&prev->kregs, &next->kregs);
}

void context_save(context_t ctx)
{
    struct cpu_regs *cur, *sav;

    cur = ctx->uregs;
    sav = (struct cpu_regs*)(cur->sp - sizeof(struct cpu_regs));
    copyout(cur, sav, sizeof(*sav));

    ctx->saved_regs = sav;
    cur->sp = (uint32_t)sav - 8;
}

void context_restore(context_t ctx)
{
    struct cpu_regs* cur;

    cur = ctx->uregs;
    copyin(ctx->saved_regs, cur, sizeof(*cur));
}

void context_dump(context_t ctx)
{
#ifdef DEBUG
    trap_dump(ctx->uregs);
#endif
}
