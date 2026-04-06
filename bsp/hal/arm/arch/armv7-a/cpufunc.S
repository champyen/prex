/*-
 * Copyright (c) 2008, Kohsuke Ohtani
 * Copyright (c) 2010, Richard Pandion
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
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

/*
 * cpufunc.S - ARMv7-A specific CPU functions
 */

#include <conf/config.h>
#include <machine/asm.h>
#include <cpu.h>

	.section ".text","ax"
	.code 32

ENTRY(cpu_idle)
	wfi
	mov	pc, lr

/*
 * Set Vector Base Address Register
 */
ENTRY(set_vbar)
	mcr	p15, 0, r0, c12, c0, 0
	mov	pc, lr

/*
 * Data synchronization barrier
 */
ENTRY(cpu_barrier)
	dsb
	isb
	mov	pc, lr

/*
 * Fault information
 */
ENTRY(get_faultstatus)
	mrc	p15, 0, r0, c5, c0, 0
	mov	pc, lr

ENTRY(get_faultaddress)
	mrc	p15, 0, r0, c6, c0, 0
	mov	pc, lr

/*
 * Generic Timer functions
 */
ENTRY(get_cntfrq)
	mrc	p15, 0, r0, c14, c0, 0
	mov	pc, lr

ENTRY(get_cntpct)
	mrrc p15, 0, r0, r1, c14
	mov	pc, lr

ENTRY(set_cntp_tval_reg)
	mcr	p15, 0, r0, c14, c2, 0
	isb
	mov	pc, lr

ENTRY(get_cntp_tval_reg)
	mrc	p15, 0, r0, c14, c2, 0
	mov	pc, lr

ENTRY(set_cntp_ctl_reg)
	mcr	p15, 0, r0, c14, c2, 1
	isb
	mov	pc, lr

ENTRY(get_cntp_ctl_reg)
	mrc	p15, 0, r0, c14, c2, 1
	mov	pc, lr

#ifdef CONFIG_MMU
/*
 * Get TTB - Translation Table Base register
 */
ENTRY(get_ttb)
	mrc	p15, 0, r0, c2, c0, 0
	mov	pc, lr

/*
 * Set TTB
 */
ENTRY(set_ttb)
	mov	r1,#0
	mcr	p15, 0, r0, c2, c0, 0	/* load new TTB */
	mcr	p15, 0, r1, c8, c7, 0	/* invalidate I+D TLBs */
	dsb
	isb
	mov	pc, lr

/*
 * Switch TTB for context switch
 */
ENTRY(switch_ttb)
	mcr	p15, 0, r0, c2, c0, 0	/* load new TTB */
	mov	r1, #0
	mcr	p15, 0, r1, c8, c7, 0	/* invalidate I+D TLBs */
	dsb
	isb
	mov	pc, lr

/*
 * Flush TLB
 */
ENTRY(flush_tlb)
	mov	r1,#0
	mcr	p15, 0, r1, c8, c7, 0	/* invalidate I+D TLBs */
	dsb
	isb
	mov	pc, lr

#endif /* !CONFIG_MMU */

#ifdef CONFIG_CACHE
/*
 * Flush all cache
 */
ENTRY(flush_cache)
	mov	r0, #0
	mcr	p15, 0, r0, c7, c14, 0	/* clean & invalidate D-cache */
	mcr	p15, 0, r0, c7, c5, 0	/* invalidate I-cache */
	dsb
	isb
	mov	pc, lr
#endif /* !CONFIG_CACHE */

	.end
