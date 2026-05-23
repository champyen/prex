/*
 * context.c - context management routines for RISC-V
 */

#include <kernel.h>
#include <kmem.h>
#include <cpu.h>
#include <context.h>
#include <locore.h>
#include <trap.h>
#include <libkern.h>

void context_set(context_t ctx, int type, register_t val)
{
    struct kern_regs* k = &ctx->kregs;
    struct cpu_regs* u;

    switch (type) {
    case CTX_KSTACK:
        /* Set kernel mode stack pointer */
        ctx->uregs = (struct cpu_regs*)((vaddr_t)val - sizeof(struct cpu_regs));
        k->sp = (uint32_t)ctx->uregs;
        
        /* Reset minimum user mode registers */
        u = ctx->uregs;
        memset(u, 0, sizeof(*u));
        /* Initial status for Supervisor Mode (SPP=1, SPIE=1, SUM=1) */
        u->status = 0x00040120; /* SPP=1 (Bit 8), SPIE=1 (Bit 5), SUM=1 (Bit 18) */
        break;

    case CTX_KENTRY:
        /* Kernel mode program counter */
        k->ra = (uint32_t)&kernel_thread_entry;
        k->s0 = (uint32_t)val; /* Entry point */
        break;

    case CTX_KARG:
        /* Kernel mode argument */
        k->s1 = (uint32_t)val;
        break;

    case CTX_UENTRY:
        /* User mode program counter */
        u = ctx->uregs;
        u->epc = (uint32_t)val;
        u->ra = 0;
        /* Status for User Mode (SPP=0, SPIE=1, SUM=1) */
        u->status = 0x00040020;
        break;

    case CTX_USTACK:
        /* User mode stack pointer */
        u = ctx->uregs;
        /* RISC-V ABI: 16-byte alignment and argc=1 setup for NOMMU */
        u->sp = (uint32_t)val & ~15;
#ifndef CONFIG_MMU
        *(int*)(u->sp) = 1;
#endif
        break;

    case CTX_UARG:
        /* User mode argument */
        u = ctx->uregs;
        u->a0 = (uint32_t)val;
        break;
    }
}

void context_save(context_t ctx)
{
    struct cpu_regs *cur, *sav;

    /* Copy current register context into user mode stack */
    cur = ctx->uregs;
    sav = (struct cpu_regs*)((vaddr_t)cur->sp - sizeof(struct cpu_regs));
    copyout(cur, sav, sizeof(struct cpu_regs));

    ctx->saved_regs = sav;

    /* Adjust user stack pointer to protect the saved context */
    cur->sp = (uint32_t)sav;
}

void context_restore(context_t ctx)
{
    struct cpu_regs* cur;

    /* Restore user mode context from user mode stack */
    cur = ctx->uregs;
    copyin(ctx->saved_regs, cur, sizeof(struct cpu_regs));
}

void context_switch(context_t prev, context_t next)
{
    cpu_switch(&prev->kregs, &next->kregs);
}

void context_dump(context_t ctx)
{
#ifdef DEBUG
    trap_dump(ctx->uregs);
#endif
}
