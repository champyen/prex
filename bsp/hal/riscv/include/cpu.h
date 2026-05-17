/*
 * cpu.h - RISC-V CPU definitions
 */

#ifndef _RISCV_CPU_H
#define _RISCV_CPU_H

#ifndef __ASSEMBLY__
#include <sys/types.h>
#include <sys/cdefs.h>

__BEGIN_DECLS
void cpu_init(void);

static inline struct cpu_control* hal_get_cpu_control(void)
{
    struct cpu_control* cpu;
    __asm__ volatile("csrr %0, mscratch" : "=r"(cpu));
    return cpu;
}

static inline void hal_set_cpu_control(struct cpu_control* cpu)
{
    __asm__ volatile("csrw mscratch, %0" : : "r"(cpu));
}

__END_DECLS
#endif

#endif /* !_RISCV_CPU_H */
