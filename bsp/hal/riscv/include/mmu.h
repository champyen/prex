/*
 * mmu.h - RISC-V MMU definitions
 */

#ifndef _RISCV_MMU_H
#define _RISCV_MMU_H

#include <sys/types.h>

typedef uint32_t* pgd_t;
typedef uint32_t* pte_t;

#define L1TBL_SIZE 0x1000
#define L2TBL_SIZE 0x1000

/*
 * PTE flags (Sv32)
 */
#define PTE_V 0x01
#define PTE_R 0x02
#define PTE_W 0x04
#define PTE_X 0x08
#define PTE_U 0x10
#define PTE_G 0x20
#define PTE_A 0x40
#define PTE_D 0x80

#define PTE_PRESENT   PTE_V
#define PTE_SYSTEM    (PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
#define PTE_USER_RO   (PTE_V | PTE_R | PTE_U | PTE_A)
#define PTE_USER_RW   (PTE_V | PTE_R | PTE_W | PTE_U | PTE_A | PTE_D)

#define PTE_ADDRESS 0xfffffc00

#define PAGE_DIR(virt)   (int)(((vaddr_t)(virt)) >> 22)
#define PAGE_TABLE(virt) (int)((((vaddr_t)(virt)) >> 12) & 0x3ff)

#define NO_PGD ((pgd_t)0)

#endif /* !_RISCV_MMU_H */
