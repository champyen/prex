/*-
 * Copyright (c) 2008-2009, Kohsuke Ohtani
 * All rights reserved.
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * ...
 */

#ifndef _RISCV_SYSPAGE_H
#define _RISCV_SYSPAGE_H

#include <conf/config.h>

#define SYSPAGE CONFIG_SYSPAGE_BASE

/* 
 * Memory layout for RISC-V QEMU-Virt (NOMMU)
 * 0x80000000 - 0x8000FFFF: Bootloader (64KB)
 * 0x80010000 - ...       : OS Image Archive
 * 0x80100000 - 0x8010FFFF: System Page (64KB)
 */

#define BOOTINFO (SYSPAGE + 0x100000)
#define INTSTK (SYSPAGE + 0x101000)
#define SYSSTK (SYSPAGE + 0x102000)
#define BOOTSTK (SYSPAGE + 0x103000)
#define BOOT_PGD (SYSPAGE + 0x105000)

#define RAMBASE CONFIG_SYSPAGE_PHY_BASE
#define BOOT_PGD_PHYS (BOOT_PGD)

#define INTSTKSZ 0x1000
#define SYSSTKSZ 0x1000
#define BOOTSTKSZ 0x2000

#define INTSTKTOP (INTSTK + INTSTKSZ)
#define SYSSTKTOP (SYSSTK + SYSSTKSZ)
#define BOOTSTKTOP (BOOTSTK + BOOTSTKSZ)

#define SYSPAGESZ 0x10000

#endif /* !_RISCV_SYSPAGE_H */
