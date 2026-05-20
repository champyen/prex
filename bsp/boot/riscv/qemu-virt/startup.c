/*
 * startup.c - machine-dependent startup code for RISC-V QEMU virt
 */

#include <sys/param.h>
#include <sys/bootinfo.h>
#include <machine/syspage.h>
#include <boot.h>

static void bootinfo_init(void)
{
    struct bootinfo* bi = bootinfo;

    /*
     * Usable: Entire DRAM (starting from 0x80000000)
     */
    bi->ram[0].base = 0x80000000;
    bi->ram[0].size = CONFIG_RAM_SIZE;
    bi->ram[0].type = MT_USABLE;

    /*
     * Reserved: System Page (0x80000000 - 0x8000FFFF)
     * This covers M-mode jump, System Page, BootInfo, Loader Stacks, and PGT.
     */
    bi->ram[1].base = CONFIG_SYSPAGE_BASE;
    bi->ram[1].size = SYSPAGESZ;
    bi->ram[1].type = MT_RESERVED;

    /*
     * Reserved: Bootloader (0x80010000 - 0x80013FFF)
     * For RISC-V, the M-mode trap handler stays resident in the bootloader.
     */
    bi->ram[2].base = CONFIG_LOADER_TEXT;
    bi->ram[2].size = 0x4000; /* 16KB */
    bi->ram[2].type = MT_RESERVED;

    bi->nr_rams = 3;
}

void startup(void)
{
    bootinfo_init();
}
