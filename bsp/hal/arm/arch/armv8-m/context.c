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
#include <thread.h>
#include <task.h>

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
        u->svc_lr = 0xFFFFFFF9; /* Default EXC_RETURN: Thread Mode using MSP */
        break;

    case CTX_KENTRY:
        k->lr = (uint32_t)&kernel_thread_entry;
        {
            extern void syscall_ret(void);
            extern void user_thread_entry(void);
            if (val == (uint32_t)&syscall_ret) {
                k->r4 = (uint32_t)&user_thread_entry;
            } else {
                k->r4 = (uint32_t)val;
            }
        }
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
        {
            struct thread *thr = list_entry(ctx, struct thread, ctx);
            if (thr && thr->task) {
                u->r9 = (uint32_t)thr->task->got_base;
            }
        }
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
#ifndef CONFIG_MMU
    if (prev->saved_uregs_valid && prev->kstack_copy_size == 0) {
        uint32_t current_sp;
        __asm__ __volatile__("mov %0, sp" : "=r"(current_sp));
        vaddr_t kstack_top = (vaddr_t)prev->saved_uregs_ptr + sizeof(struct cpu_regs);
        if (kstack_top > current_sp) {
            size_t size = kstack_top - current_sp;
            if (size <= sizeof(prev->kstack_copy)) {
                memcpy(prev->kstack_copy, (void*)current_sp, size);
                prev->kstack_copy_size = size;
                prev->kstack_copy_sp = current_sp;
            } else {
                panic("kstack overflow");
            }
        }
    }

    if (next->kstack_copy_size > 0) {
        memcpy((void*)next->kstack_copy_sp, next->kstack_copy, next->kstack_copy_size);
        next->kstack_copy_size = 0;
    }
    if (next->saved_uregs_valid) {
        copyout(&next->saved_uregs, next->saved_uregs_ptr, sizeof(struct cpu_regs));
        next->uregs = next->saved_uregs_ptr;
        next->saved_uregs_valid = 0;
    }
#endif
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

void debug_dump_regs(struct cpu_regs *u)
{
    printf("debug_dump_regs: uregs=0x%x\n", (unsigned int)u);
    printf("  sp=0x%x, svc_sp=0x%x, pad=0x%x, svc_lr=0x%x\n",
           (unsigned int)u->sp, (unsigned int)u->svc_sp, (unsigned int)u->pad, (unsigned int)u->svc_lr);
    printf("  r4=0x%x, r5=0x%x, r6=0x%x, r7=0x%x\n",
           (unsigned int)u->r4, (unsigned int)u->r5, (unsigned int)u->r6, (unsigned int)u->r7);
    printf("  r8=0x%x, r9=0x%x, r10=0x%x, r11=0x%x\n",
           (unsigned int)u->r8, (unsigned int)u->r9, (unsigned int)u->r10, (unsigned int)u->r11);
    printf("  r0=0x%x, r1=0x%x, r2=0x%x, r3=0x%x\n",
           (unsigned int)u->r0, (unsigned int)u->r1, (unsigned int)u->r2, (unsigned int)u->r3);
    printf("  r12=0x%x, lr=0x%x, pc=0x%x, cpsr=0x%x\n",
           (unsigned int)u->r12, (unsigned int)u->lr, (unsigned int)u->pc, (unsigned int)u->cpsr);
}

void report_hardfault(uint32_t *stack, uint32_t exc_return)
{
    volatile uint32_t *hfsr = (volatile uint32_t *)0xE000ED2C;
    volatile uint32_t *cfsr = (volatile uint32_t *)0xE000ED28;
    volatile uint32_t *mmfar = (volatile uint32_t *)0xE000ED34;
    volatile uint32_t *bfar = (volatile uint32_t *)0xE000ED38;
    volatile uint32_t *sfsr = (volatile uint32_t *)0xE000EDE4;

    uint32_t primask, basepri, faultmask, control;
    __asm__ volatile("mrs %0, primask" : "=r"(primask));
    __asm__ volatile("mrs %0, basepri" : "=r"(basepri));
    __asm__ volatile("mrs %0, faultmask" : "=r"(faultmask));
    __asm__ volatile("mrs %0, control" : "=r"(control));

    printf("\n!!! HARD FAULT !!!\n");
    if (curthread && curthread->task) {
        printf("Current Task: %s (thread=0x%x)\n", curthread->task->name, (unsigned int)curthread);
    }
    printf("EXC_RETURN = 0x%08x\n", (unsigned int)exc_return);
    printf("HFSR = 0x%08x\n", (unsigned int)*hfsr);
    printf("CFSR = 0x%08x\n", (unsigned int)*cfsr);
    printf("SFSR = 0x%08x\n", (unsigned int)*sfsr);
    printf("MMFAR = 0x%08x\n", (unsigned int)*mmfar);
    printf("BFAR = 0x%08x\n", (unsigned int)*bfar);
    printf("PRIMASK = 0x%02x, BASEPRI = 0x%02x, FAULTMASK = 0x%02x, CONTROL = 0x%02x\n",
           (unsigned int)primask, (unsigned int)basepri, (unsigned int)faultmask, (unsigned int)control);
    
    printf("Stacked Frame Address = 0x%08x\n", (unsigned int)stack);
    printf("Stacked Registers:\n");
    printf("  r0  = 0x%08x\n", (unsigned int)stack[0]);
    printf("  r1  = 0x%08x\n", (unsigned int)stack[1]);
    printf("  r2  = 0x%08x\n", (unsigned int)stack[2]);
    printf("  r3  = 0x%08x\n", (unsigned int)stack[3]);
    printf("  r12 = 0x%08x\n", (unsigned int)stack[4]);
    printf("  lr  = 0x%08x\n", (unsigned int)stack[5]);
    printf("  pc  = 0x%08x\n", (unsigned int)stack[6]);
    printf("  xPSR= 0x%08x\n", (unsigned int)stack[7]);
    while (1);
}
