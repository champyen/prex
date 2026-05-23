/*
 * mmu.c - memory management unit support routines for RISC-V
 */

#include <machine/syspage.h>
#include <kernel.h>
#include <page.h>
#include <mmu.h>
#include <cpu.h>
#include <cpufunc.h>
#include <riscv_csr.h>

static pgd_t boot_pgd = (pgd_t)BOOT_PGD;

/*
 * Map physical memory range into virtual address
 *
 * Returns 0 on success, or ENOMEM on failure.
 */
int mmu_map(pgd_t pgd, paddr_t pa, vaddr_t va, size_t size, int type)
{
    uint32_t pte_flag = 0;
    uint32_t pde_flag = 0;
    pte_t pte;
    paddr_t pg;

    pa = round_page(pa);
    va = round_page(va);
    size = trunc_page(size);

    /*
     * Set page flag
     */
    switch (type) {
    case PG_UNMAP:
        pte_flag = 0;
        pde_flag = (uint32_t)PTE_V;
        break;
    case PG_READ:
        pte_flag = (uint32_t)PTE_USER_RO;
        pde_flag = (uint32_t)PTE_V;
        break;
    case PG_WRITE:
        pte_flag = (uint32_t)PTE_USER_RW;
        pde_flag = (uint32_t)PTE_V;
        break;
    case PG_SYSTEM:
        pte_flag = (uint32_t)PTE_SYSTEM;
        pde_flag = (uint32_t)PTE_V;
        break;
    case PG_IOMEM:
        pte_flag = (uint32_t)PTE_SYSTEM; // RISC-V Sv32 doesn't have cache bits in standard PTE
        pde_flag = (uint32_t)PTE_V;
        break;
    default:
        panic("mmu_map");
    }

    /*
     * Map all pages
     */
    while (size > 0) {
        if (pte_present(pgd, va)) {
            /* Page table already exists for the address */
            pte = vtopte(pgd, va);
        } else {
            ASSERT(pte_flag != 0);
            if ((pg = page_alloc(PAGE_SIZE)) == 0) {
                DPRINTF(("Error: MMU mapping failed\n"));
                return ENOMEM;
            }
            // Store physical address in PDE.
            // Physical address pg must be shifted right by 2 (PPN format).
            pgd[PAGE_DIR(va)] = (uint32_t)(pg >> 2) | pde_flag;
            pte = (pte_t)ptokv(pg);
            memset(pte, 0, PAGE_SIZE);
        }
        /* Set new entry into page table */
        // Store physical address in PTE.
        // Physical address pa must be shifted right by 2 (PPN format).
        pte[PAGE_TABLE(va)] = (uint32_t)(pa >> 2) | pte_flag;

        /* Process next page */
        pa += PAGE_SIZE;
        va += PAGE_SIZE;
        size -= PAGE_SIZE;
    }
    mmu_invalidate_tlbs();
    return 0;
}

/*
 * Create new page map.
 */
pgd_t mmu_newmap(void)
{
    paddr_t pg;
    pgd_t pgd;
    int i;

    /* Allocate page directory */
    if ((pg = page_alloc(PAGE_SIZE)) == 0)
        return NO_PGD;
    pgd = (pgd_t)ptokv(pg);
    memset(pgd, 0, PAGE_SIZE);

    /* Copy kernel page tables (above KERNBASE) */
    i = PAGE_DIR(KERNBASE);
    memcpy(&pgd[i], &boot_pgd[i], (size_t)(1024 - i) * sizeof(uint32_t));

    /* Copy system I/O mappings (any non-zero entry below KERNBASE) */
    for (i = 0; i < PAGE_DIR(KERNBASE); i++) {
        if (boot_pgd[i] != 0) {
            pgd[i] = boot_pgd[i];
        }
    }
    return pgd;
}

/*
 * Terminate all page mapping.
 */
void mmu_terminate(pgd_t pgd)
{
    int i;
    paddr_t pte_phys;

    mmu_invalidate_tlbs();

    /* Release all user page table */
    for (i = 0; i < PAGE_DIR(KERNBASE); i++) {
        if (pgd[i] != 0 && pgd[i] != boot_pgd[i]) {
            // Extract physical address of L2 page table from PDE
            pte_phys = (paddr_t)((pgd[i] & PTE_ADDRESS) << 2);
            page_free(pte_phys, PAGE_SIZE);
        }
    }
    /* Release page directory */
    page_free(kvtop(pgd), PAGE_SIZE);
}

/*
 * Switch to new page directory
 */
void mmu_switch(pgd_t pgd)
{
    paddr_t phys = kvtop(pgd);
    uint32_t satp = (1U << 31) | (phys >> 12); // Sv32 mode
    uint32_t current_satp;

#ifdef CONFIG_SMODE
    __asm__ __volatile__("csrr %0, " STR(CSR_SATP) : "=r"(current_satp));

    if (satp != current_satp) {
        __asm__ __volatile__("csrw " STR(CSR_SATP) ", %0" : : "r"(satp));
        __asm__ __volatile__("sfence.vma");
    }
#endif
}

/*
 * Returns the physical address for the specified virtual address.
 */
paddr_t mmu_extract(pgd_t pgd, vaddr_t va, size_t size)
{
    pte_t pte;
    vaddr_t start, end, pg;
    paddr_t pa;

    start = trunc_page(va);
    end = trunc_page(va + size - 1);

    /* Check all pages exist */
    for (pg = start; pg <= end; pg += PAGE_SIZE) {
        if (!pte_present(pgd, pg))
            return 0;
        pte = vtopte(pgd, pg);
        if (!page_present(pte, pg))
            return 0;
    }

    /* Get physical address */
    pte = vtopte(pgd, start);
    pa = (paddr_t)ptetopg(pte, start);
    return pa + (paddr_t)(va - start);
}

/*
 * Map I/O memory for diagnostic device at very early stage.
 */
void mmu_premap(paddr_t phys, vaddr_t virt)
{
    pte_t pte = (pte_t)BOOT_PTE0;
    int pte_index;

    boot_pgd[PAGE_DIR(virt)] = (uint32_t)(kvtop(pte) >> 2) | PTE_V;
    for (pte_index = 0; pte_index < 1024; pte_index++) {
        pte[pte_index] = (uint32_t)(phys >> 2) | PTE_SYSTEM;
        phys += PAGE_SIZE;
    }

    mmu_invalidate_tlbs();
}

/*
 * Initialize mmu
 */
void mmu_init(struct mmumap* mmumap_table)
{
    struct mmumap* map;
    int map_type = 0;

    DPRINTF(("mmu_init start\n"));
    for (map = mmumap_table; map->type != 0; map++) {
        DPRINTF(("mmu_init: mapping phys %lx to virt %lx size %lx type %d\n",
                 (long)map->phys, (long)map->virt, (long)map->size, map->type));
        switch (map->type) {
        case VMT_RAM:
        case VMT_ROM:
        case VMT_DMA:
            map_type = PG_SYSTEM;
            break;
        case VMT_IO:
            map_type = PG_IOMEM;
            break;
        }

        if (mmu_map(boot_pgd, map->phys, map->virt, (size_t)map->size, map_type))
            panic("mmu_init");
    }
    DPRINTF(("mmu_init end\n"));
}
