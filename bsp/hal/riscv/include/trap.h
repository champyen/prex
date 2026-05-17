/*
 * trap.h - RISC-V trap handling definitions
 */

#ifndef _RISCV_TRAP_H
#define _RISCV_TRAP_H

#ifndef __ASSEMBLY__
#include <sys/cdefs.h>
#include <context.h>

__BEGIN_DECLS
void trap_handler(struct cpu_regs*);
void trap_dump(struct cpu_regs*);
__END_DECLS
#endif

#endif /* !_RISCV_TRAP_H */
