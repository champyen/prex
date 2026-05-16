/*
 * startup.c - machine-dependent startup code for RISC-V QEMU virt
 */

#include <sys/param.h>
#include <sys/bootinfo.h>
#include <boot.h>

static void bootinfo_init(void)
{
    struct bootinfo* bi = bootinfo;

    printf("bootinfo_init: setting ram[0].base to 0x80000000\n");
    printf("MARKER: fresh build\n");
    bi->ram[0].base = 0x80000000;
    bi->ram[0].size = CONFIG_RAM_SIZE;
    bi->ram[0].type = MT_USABLE;

    bi->nr_rams = 1;
}

void startup(void)
{
    bootinfo_init();
}
