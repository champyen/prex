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
     * Usable: Entire DRAM
     */
    bi->ram[0].base = 0x80000000;
    bi->ram[0].size = CONFIG_RAM_SIZE;
    bi->ram[0].type = MT_USABLE;

    /*
     * Reserved: System Page (0x80100000 - 0x80100FFF)
     * Used by M-mode trap handler state in locore.S
     */
    bi->ram[1].base = 0x80100000;
    bi->ram[1].size = 0x1000; /* 4KB */
    bi->ram[1].type = MT_RESERVED;

    bi->nr_rams = 2;
}

void startup(void)
{
    bootinfo_init();
}
