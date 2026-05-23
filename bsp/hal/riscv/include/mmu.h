/*
 * mmu.h - RISC-V MMU definitions
 */

#ifndef _RISCV_MMU_H
#define _RISCV_MMU_H

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
#define PTE_SYSTEM    (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)
#define PTE_USER_RO   (PTE_V | PTE_R | PTE_X | PTE_U | PTE_A)
#define PTE_USER_RW   (PTE_V | PTE_R | PTE_W | PTE_U | PTE_A | PTE_D)

#define PTE_ADDRESS 0xfffffc00

#ifndef __ASSEMBLY__
#include <sys/types.h>
#include <riscv_csr.h>

typedef uint32_t* pgd_t;
typedef uint32_t* pte_t;

#define PAGE_DIR(virt)   (int)(((vaddr_t)(virt)) >> 22)
#define PAGE_TABLE(virt) (int)((((vaddr_t)(virt)) >> 12) & 0x3ff)

#define pte_present(pgd, virt) ((pgd[PAGE_DIR(virt)] & PTE_PRESENT) && !(pgd[PAGE_DIR(virt)] & (PTE_R | PTE_W | PTE_X)))
#define vtopte(pgd, virt) (pte_t) ptokv((((uint32_t*)pgd)[PAGE_DIR(virt)] & PTE_ADDRESS) << 2)
#define page_present(pte, virt) (pte[PAGE_TABLE(virt)] & PTE_PRESENT)
#define ptetopg(pte, virt) (paddr_t)(((pte)[PAGE_TABLE(virt)] & PTE_ADDRESS) << 2)

#define NO_PGD ((pgd_t)0)

static inline void mmu_invalidate_tlbs(void)
{
    __asm__ __volatile__("sfence.vma x0, x0" : : : "memory");
}

static inline void mmu_invalidate_tlb_by_vaddr(vaddr_t va)
{
    __asm__ __volatile__("sfence.vma %0, x0" : : "r"(va) : "memory");
}

static inline void set_satp(uint32_t satp)
{
#ifdef CONFIG_SMODE
    __asm__ __volatile__(
        "csrw " STR(CSR_SATP) ", %0\n"
        "sfence.vma x0, x0\n"
        "fence rw, rw\n"
        "fence.i\n"
        :
        : "r" (satp)
        : "memory"
    );
#endif
}
#endif /* !__ASSEMBLY__ */

#endif /* !_RISCV_MMU_H */
