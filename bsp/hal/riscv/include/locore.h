/*
 * locore.h - RISC-V low level platform support
 */

#ifndef _RISCV_LOCORE_H
#define _RISCV_LOCORE_H

#include <sys/cdefs.h>
#include <context.h>

__BEGIN_DECLS
void kernel_thread_entry(void);
#include <context.h>

void cpu_switch(struct kern_regs* prev, struct kern_regs* next);
void sploff(void);
void splon(void);
__END_DECLS

#endif /* !_RISCV_LOCORE_H */
