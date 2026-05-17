/*
 * cpufunc.h - RISC-V CPU specific functions
 */

#ifndef _RISCV_CPUFUNC_H
#define _RISCV_CPUFUNC_H

#include <sys/cdefs.h>
#include <sys/types.h>

__BEGIN_DECLS
void splon(void);
void sploff(void);
int get_status(void);
void cpu_idle(void);
void* get_faultaddress(void);
int get_faultstatus(void);
void switch_ttb(paddr_t ttb);
void set_ttb(paddr_t ttb);
paddr_t get_ttb(void);
void flush_tlb(void);
void flush_cache(void);
void cpu_barrier(void);
uint32_t hal_cpu_id(void);
__END_DECLS

#endif /* !_RISCV_CPUFUNC_H */
