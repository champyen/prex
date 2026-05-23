/*
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 */

#ifndef _RISCV_MEMORY_H
#define _RISCV_MEMORY_H

#include <conf/config.h>

#ifdef CONFIG_MMU
#define KERNBASE CONFIG_SYSPAGE_BASE
#define KERNOFFSET (KERNBASE - CONFIG_SYSPAGE_PHY_BASE)
#define PAGE_SIZE 4096
#define USERLIMIT CONFIG_SYSPAGE_BASE
#else
#define KERNBASE 0
#define KERNOFFSET 0
#define PAGE_SIZE 4096
#define USERLIMIT 0xffffffff
#endif

#endif /* _RISCV_MEMORY_H */
