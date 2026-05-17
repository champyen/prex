/*
 * mmu.c - memory management unit support routines for RISC-V
 */

#include <machine/syspage.h>
#include <kernel.h>
#include <page.h>
#include <mmu.h>
#include <cpu.h>
#include <cpufunc.h>

static pgd_t boot_pgd = (pgd_t)BOOT_PGD;

int mmu_map(pgd_t pgd, paddr_t pa, vaddr_t va, size_t size, int type)
{
    return 0;
}

pgd_t mmu_newmap(void)
{
    return NO_PGD;
}

void mmu_terminate(pgd_t pgd)
{
}

void mmu_switch(pgd_t pgd)
{
}

paddr_t mmu_extract(pgd_t pgd, vaddr_t virt, size_t size)
{
    return 0;
}

void mmu_premap(paddr_t phys, vaddr_t virt)
{
}

void mmu_init(struct mmumap* mmumap_table)
{
}
