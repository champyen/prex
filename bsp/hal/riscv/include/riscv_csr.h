/*
 * riscv_csr.h - RISC-V CSR abstractions for S-mode/M-mode flexibility
 */

#ifndef _RISCV_CSR_H
#define _RISCV_CSR_H

#include <conf/config.h>

#define __STR(x) #x
#define STR(x) __STR(x)

#ifdef CONFIG_SMODE
#define CSR_STATUS  sstatus
#define CSR_EPC     sepc
#define CSR_CAUSE   scause
#define CSR_TVAL    stval
#define CSR_IE      sie
#define CSR_IP      sip
#define CSR_SCRATCH sscratch
#define CSR_TVEC    stvec
#define CSR_SATP    satp
#else
#define CSR_STATUS  mstatus
#define CSR_EPC     mepc
#define CSR_CAUSE   mcause
#define CSR_TVAL    mtval
#define CSR_IE      mie
#define CSR_IP      mip
#define CSR_SCRATCH mscratch
#define CSR_TVEC    mtvec
/* SATP is not available in M-mode */
#endif

#endif /* !_RISCV_CSR_H */
