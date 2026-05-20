/*-
 * Copyright (c) 2008-2009, Kohsuke Ohtani
 * All rights reserved.
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the author nor the names of any co-contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#ifndef _RISCV_SYSPAGE_H
#define _RISCV_SYSPAGE_H

#include <conf/config.h>

#define SYSPAGE CONFIG_SYSPAGE_BASE

/* 
 * Memory layout for RISC-V QEMU-Virt
 * 0x80000000 - 0x80000FFF: M-Mode Save Area (4KB)
 * 0x80001000 - 0x8000FFFF: System Page / Boot Info / Stacks / PGT (60KB)
 * 0x80010000 - 0x80013FFF: Bootloader (LOADER_TEXT) (16KB padded)
 * 0x80014000 - ...       : OS Image Archive (BOOTIMG_BASE)
 */

#define BOOTINFO (SYSPAGE + 0x01000)
#define INTSTK (SYSPAGE + 0x02000)
#define SYSSTK (SYSPAGE + 0x03000)
#define BOOTSTK (SYSPAGE + 0x04000)
#define BOOT_PGD (SYSPAGE + 0x06000)
#define BOOT_PTE0 (SYSPAGE + 0x07000)
#define BOOT_PTE1 (SYSPAGE + 0x08000)

#define RAMBASE CONFIG_SYSPAGE_PHY_BASE
#define BOOT_PGD_PHYS (RAMBASE + 0x06000)
#define BOOT_PTE0_PHYS (RAMBASE + 0x07000)
#define BOOT_PTE1_PHYS (RAMBASE + 0x08000)

#define INTSTKSZ 0x1000
#define SYSSTKSZ 0x1000
#define BOOTSTKSZ 0x2000

#define INTSTKTOP (INTSTK + INTSTKSZ)
#define SYSSTKTOP (SYSSTK + SYSSTKSZ)
#define BOOTSTKTOP (BOOTSTK + BOOTSTKSZ)

#define SYSPAGESZ 0x10000

#endif /* !_RISCV_SYSPAGE_H */
