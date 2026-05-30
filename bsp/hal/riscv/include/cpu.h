/*
 * cpu.h - RISC-V CPU definitions
 */

#ifndef _RISCV_CPU_H
#define _RISCV_CPU_H

#define IPI_IRQ 1

#ifndef __ASSEMBLY__
#include <sys/types.h>
#include <sys/cdefs.h>
#include <riscv_csr.h>
#include <cpu_control.h>

struct riscv_cpu {
    void* kernel_sp;
    void* user_sp;
    struct cpu_control* cpu_control;
    uint32_t temp_t0;
};

#ifdef CONFIG_SMP
#define RISCV_NCPUS CONFIG_SMP_NCPUS
#else
#define RISCV_NCPUS 1
#endif

extern struct riscv_cpu riscv_cpus[RISCV_NCPUS];

__BEGIN_DECLS
void cpu_init(void);

static inline struct cpu_control* hal_get_cpu_control(void)
{
    struct cpu_control* cpu;
    __asm__ volatile("mv %0, tp" : "=r"(cpu));
    return cpu;
}

static inline void hal_set_cpu_control(struct cpu_control* cpu)
{
    __asm__ volatile("mv tp, %0" : : "r"(cpu));
    if (cpu) {
        riscv_cpus[cpu->cpu_id].cpu_control = cpu;
    }
}

__END_DECLS
#endif


#endif /* !_RISCV_CPU_H */
