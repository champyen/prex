/*-
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
 * All rights reserved.
 */

#include <sys/param.h>
#include <sys/bootinfo.h>
#include <boot.h>

static void bootinfo_init(void)
{
    struct bootinfo* bi = bootinfo;
    bi->video.text_x = 80;
    bi->video.text_y = 25;
    bi->ram[0].base = CONFIG_SYSPAGE_PHY_BASE;
    bi->ram[0].size = CONFIG_RAM_SIZE;
    bi->ram[0].type = MT_USABLE;
    bi->nr_rams = 1;
}

void startup(void)
{
    bootinfo_init();
}
