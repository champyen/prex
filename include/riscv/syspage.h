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

#define SYSPAGE 0x80100000

#define INTSTK (SYSPAGE + 0x1000)
#define SYSSTK (SYSPAGE + 0x2000)
#define BOOTINFO (SYSPAGE + 0x3000)
#define BOOTSTK (SYSPAGE + 0x4000)
#define BOOT_PGD (SYSPAGE + 0x8000)

#define RAMBASE CONFIG_SYSPAGE_PHY_BASE
#define BOOT_PGD_PHYS (SYSPAGE) /* In NOMMU, phys == virt */

#define INTSTKSZ 0x1000
#define SYSSTKSZ 0x1000
#define BOOTSTKSZ 0x2000

#define INTSTKTOP (INTSTK + INTSTKSZ)
#define SYSSTKTOP (SYSSTK + SYSSTKSZ)
#define BOOTSTKTOP (BOOTSTK + BOOTSTKSZ)

#ifdef CONFIG_MMU
#define SYSPAGESZ 0x10000
#else
#define SYSPAGESZ 0x10000
#endif

#endif /* !_RISCV_SYSPAGE_H */
