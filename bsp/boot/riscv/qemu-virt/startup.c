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
     * Reserved: Bootloader (0x80000000 - 0x8000FFFF)
     */
    bi->ram[1].base = 0x80000000;
    bi->ram[1].size = 0x10000; /* 64KB */
    bi->ram[1].type = MT_RESERVED;

    /*
     * Reserved: System Page / Boot Info (0x80100000 - 0x8011FFFF)
     * Used by M-mode trap handler state and bootinfo
     */
    bi->ram[2].base = 0x80100000;
    bi->ram[2].size = 0x20000; /* 128KB */
    bi->ram[2].type = MT_RESERVED;

    bi->nr_rams = 3;
}

void startup(void)
{
    bootinfo_init();
}
