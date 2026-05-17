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
    "Store/AMO page fault"
};
#endif

void trap_handler(struct cpu_regs* regs)
{
    uint32_t cause = regs->cause;

    if (cause & 0x80000000) {
        /* Interrupt */
        extern void riscv_irq_handler(uint32_t cause);
        riscv_irq_handler(cause & 0x7fffffff);
    } else {
        if (cause == 8 || cause == 9) {
            /* System call (ECALL from U-mode or S-mode) */
            extern register_t syscall_handler(register_t, register_t, register_t, register_t, register_t);
            /* Skip ecall instruction (4 bytes) */
            regs->pc += 4;
            regs->a0 = syscall_handler(regs->a0, regs->a1, regs->a2, regs->a3, regs->a7);
            
            /* Check for pending exceptions */
            exception_deliver();
        } else {
            /* Hardware exception */
#ifdef DEBUG
            printf("TRAP: %s\n", (cause < 16) ? trap_name[cause] : "Unknown");
            trap_dump(regs);
#endif
            panic("Kernel exception");
        }
    }
}

#ifdef DEBUG
void trap_dump(struct cpu_regs* r)
{
    printf("Trap frame %x\n", r);
    printf(" ra  %08x sp  %08x gp  %08x tp  %08x\n", r->ra, r->sp, r->gp, r->tp);
    printf(" t0  %08x t1  %08x t2  %08x s0  %08x\n", r->t0, r->t1, r->t2, r->s0);
    printf(" s1  %08x a0  %08x a1  %08x a2  %08x\n", r->s1, r->a0, r->a1, r->a2);
    printf(" a3  %08x a4  %08x a5  %08x a6  %08x\n", r->a3, r->a4, r->a5, r->a6);
    printf(" a7  %08x s2  %08x s3  %08x s4  %08x\n", r->a7, r->s2, r->s3, r->s4);
    printf(" pc  %08x status %08x cause %08x badaddr %08x\n", r->pc, r->status, r->cause, r->badaddr);
}
#endif
