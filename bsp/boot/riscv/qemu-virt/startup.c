/*
 * startup.c - machine-dependent startup code for RISC-V QEMU virt
 */

#include <sys/param.h>
#include <sys/bootinfo.h>
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
     * Reserved: System Page
     */
    bi->ram[1].base = CONFIG_SYSPAGE_BASE;
    bi->ram[1].size = 0x20000; /* 128KB */
    bi->ram[1].type = MT_RESERVED;

    bi->nr_rams = 2;
}

void startup(void)
{
    bootinfo_init();
}
