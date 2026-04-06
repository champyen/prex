/*-
 * Copyright (c) 2005-2008, Kohsuke Ohtani
 * Copyright (c) 2010, Richard Pandion
 * All rights reserved.
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

#ifndef _ARM_MMU_H
#define _ARM_MMU_H

#include <sys/types.h>

typedef uint32_t* pgd_t; /* page directory */
typedef uint32_t* pte_t; /* page table entry */

#define L1TBL_SIZE 0x4000
#define L2TBL_SIZE 0x400

/*
 * Page directory entry (L1)
 */
#define PDE_PRESENT 0x00000001 /* Page table */
#define PDE_DOMAIN(x) ((x) << 5)
#define PDE_TYPE_MASK 0x00000003
#define PDE_ADDRESS 0xfffffc00

/*
 * Page table entry (L2)
 *
 * In ARMv7-A (VMSAv7) with TRE=0 and AFE=0:
 * Bits [1:0]: 10 (Large Page/Small Page)
 * Bit  [0]  : XN (Execute Never) - only for Small Page
 * Bits [5:4]: AP[2:1]
 */
#ifdef CONFIG_ARMV7A
#define PTE_PRESENT 0x00000002 /* Small Page */
#define PTE_XN 0x00000001      /* Execute Never */
#define PTE_WBUF 0x00000004
#define PTE_CACHE 0x00000008
#define PTE_AF 0x00000010      /* Access Flag (if AFE=1) */
#define PTE_SYSTEM 0x00000010  /* AP[2:1] = 00, AF = 1 */
#define PTE_USER_RO 0x00000020 /* AP[2:1] = 01 */
#define PTE_USER_RW 0x00000030 /* AP[2:1] = 01 + AP[2]=0? No. */

/* ARMv7 Permissions (AP[2:1]):
 * AP[2:1] | PL1 | PL0
 * 00      | RW  | NA
 * 01      | RW  | RW
 * 10      | RO  | NA
 * 11      | RO  | RO
 */
#undef PTE_SYSTEM
#undef PTE_USER_RO
#undef PTE_USER_RW
#define PTE_SYSTEM 0x00000010  /* PL1:RW, PL0:NA (AP=00, AF=1) */
#define PTE_USER_RO 0x00000070 /* PL1:RO, PL0:RO (AP=11, AF=1) */
#define PTE_USER_RW 0x00000030 /* PL1:RW, PL0:RW (AP=01, AF=1) */

#define PTE_ATTR_MASK 0x00000ff1
#define PTE_ADDRESS 0xfffff000
#else
#define PTE_PRESENT 0x00000002
#define PTE_WBUF 0x00000004
#define PTE_CACHE 0x00000008
#define PTE_SYSTEM 0x00000550
#define PTE_USER_RO 0x00000aa0
#define PTE_USER_RW 0x00000ff0
#define PTE_ATTR_MASK 0x00000ff0
#define PTE_ADDRESS 0xfffff000
#define PTE_XN 0
#endif

/*
 *  Virtual and physical address translation
 */
#define PAGE_DIR(virt) (int)((((vaddr_t)(virt)) >> 20) & 0xfff)
#define PAGE_TABLE(virt) (int)((((vaddr_t)(virt)) >> 12) & 0xff)

#define pte_present(pgd, virt) (pgd[PAGE_DIR(virt)] & PDE_PRESENT)

#define page_present(pte, virt) (pte[PAGE_TABLE(virt)] & PTE_PRESENT)

#define vtopte(pgd, virt) (pte_t) ptokv((pgd)[PAGE_DIR(virt)] & PDE_ADDRESS)

#define ptetopg(pte, virt) ((pte)[PAGE_TABLE(virt)] & PTE_ADDRESS)

#endif /* !_ARM_MMU_H */
