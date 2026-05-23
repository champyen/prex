/*
 * machdep.c - machine-dependent routines for RISC-V QEMU virt
 */

#include <machine/syspage.h>
#include <sys/power.h>
#include <sys/bootinfo.h>
#include <kernel.h>
#include <page.h>
#include <mmu.h>
#include <cpu.h>
#include <cpufunc.h>
#include <locore.h>

#ifdef CONFIG_MMU
/*
 * Virtual and physical address mapping
 *
 *      { virtual, physical, size, type }
 */
static struct mmumap mmumap_table[] = {
    /* RAM */
    {CONFIG_SYSPAGE_BASE, CONFIG_SYSPAGE_PHY_BASE, AUTOSIZE, VMT_RAM},
    /* PLIC */
    {CONFIG_PLIC_BASE, CONFIG_PLIC_PHY_BASE, 0x00400000, VMT_IO}, // Map 4MB of PLIC
    /* UART */
    {CONFIG_NS16550_BASE, CONFIG_NS16550_PHY_BASE, 0x00001000, VMT_IO}, // Map 4KB of UART
    /* VirtIO MMIO */
#ifdef CONFIG_VIO_MMIO
    {CONFIG_VIO_MMIO_BASE, CONFIG_VIO_MMIO_PHY_BASE, 0x00008000, VMT_IO}, // Map 8 VirtIO slots (32KB)
#endif
    {0, 0, 0, 0}
};
#endif

void machine_idle(void)
{
    cpu_idle();
}

void machine_powerdown(int state)
{
    splhigh();
    for (;;)
        cpu_idle();
}

void machine_abort(void)
{
    for (;;)
        cpu_idle();
}

void machine_bootinfo(struct bootinfo** bip)
{
    *bip = (struct bootinfo*)BOOTINFO;
}

void machine_startup(void)
{
#ifdef CONFIG_MMU
    struct bootinfo* bi = (struct bootinfo*)BOOTINFO;
#endif

    cpu_init();
    page_reserve(CONFIG_SYSPAGE_PHY_BASE, SYSPAGESZ);

#ifdef CONFIG_MMU
    /*
     * Modify page mapping
     * We assume the first block in ram[] is main memory.
     */
    mmumap_table[0].size = bi->ram[0].size;

    /*
     * Initialize MMU
     */
    DPRINTF(("Calling mmu_init...\n"));
    mmu_init(mmumap_table);
    DPRINTF(("mmu_init done.\n"));
#endif
}
