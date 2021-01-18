/*-
 * Copyright (c) 2008, Kohsuke Ohtani
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

/*
 * cpufunc.S - ARM specific CPU functions
 */

#include <conf/config.h>
#include <machine/asm.h>
#include <cpu.h>

	.section ".text","ax"
	.code 32

ENTRY(cpu_idle)
#if 0
	mcr	p15, 0, r0, c7, c0, 4	/* Wait for interrupt */
#endif
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
	nop
	nop
	nop
	mov	pc, lr

/*
 * Switch TTB for context switch
 */
ENTRY(switch_ttb)
#ifdef __beagle__
	mrc	p15, 1, r1, c0, c0, 0	/* read CSIDR */
	ldr	r2, =0x7fff
	ands	r2, r2, r1, lsr #13	/*  extract number of sets */
1:
	mov	r1, #0					/*  start with way #1 */
	orr	r1, r1, r2, lsl #6		/*  set the set number */
	mcr	p15, 0, r1, c7, c14, 2	/*  clean & invalidate by set/way */
	add	r1, r1, #0x40000000		/*  then way #2 */
	mcr	p15, 0, r1, c7, c14, 2	/*  clean & invalidate by set/way */
	add	r1, r1, #0x40000000		/*  now way #3 */
	mcr	p15, 0, r1, c7, c14, 2	/*  clean & invalidate by set/way */
	add	r1, r1, #0x40000000		/*  end with way #4 */
	mcr	p15, 0, r1, c7, c14, 2	/*  clean & invalidate by set/way */
	subs	r2, r2, #1			/*  decrement the set */
	bge	1b
	mov	r1,#0
	mcr	p15, 0, r1, c7, c5, 0	/* flush I cache */
#else
	mov	r1,#0
	mcr	p15, 0, r1, c7, c5, 0	/* flush I cache */
	mcr	p15, 0, r1, c7, c6, 0	/* flush D cache */
#endif
	mcr	p15, 0, r1, c7, c10, 4	/* drain the write buffer */
	mcr	p15, 0, r0, c2, c0, 0	/* load new TTB */
	mcr	p15, 0, r1, c8, c7, 0	/* invalidate I+D TLBs */
	nop
	nop
	nop
	mov	pc, lr

/*
 * Flush TLB
 */
ENTRY(flush_tlb)
	mov	r1,#0
	mcr	p15, 0, r1, c8, c7, 0	/* invalidate I+D TLBs */
	nop
	nop
	nop
	mov	pc, lr

#endif /* !CONFIG_MMU */

#ifdef CONFIG_CACHE
/*
 * Flush all cache
 */
ENTRY(flush_cache)
#ifdef __beagle__
	mrc	p15, 1, r1, c0, c0, 0	/* read CSIDR */
	ldr	r2, =0x7fff
	ands	r2, r2, r1, lsr #13	/*  extract number of sets */
1:
	mov	r1, #0					/*  start with way #1 */
	orr	r1, r1, r2, lsl #6		/*  set the set number */
	mcr	p15, 0, r1, c7, c14, 2	/*  clean & invalidate by set/way */
	add	r1, r1, #0x40000000		/*  then way #2 */
	mcr	p15, 0, r1, c7, c14, 2	/*  clean & invalidate by set/way */
	add	r1, r1, #0x40000000		/*  now way #3 */
	mcr	p15, 0, r1, c7, c14, 2	/*  clean & invalidate by set/way */
	add	r1, r1, #0x40000000		/*  end with way #4 */
	mcr	p15, 0, r1, c7, c14, 2	/*  clean & invalidate by set/way */
	subs	r2, r2, #1			/*  decrement the set */
	bge	1b
	mov	r1,#0
	mcr	p15, 0, r1, c7, c5, 0	/* flush I cache */
#else
	mov	r1,#0
	mcr	p15, 0, r1, c7, c5, 0	/* flush I cache */
	mcr	p15, 0, r1, c7, c6, 0	/* flush D cache */
#endif
	mcr	p15, 0, r1, c7, c10, 4	/* drain write buffer */
	mov	pc, lr
#endif /* !CONFIG_CACHE */

	.end
