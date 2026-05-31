/*-
 * Copyright (c) 2008, Kohsuke Ohtani
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
 * head.S - generic header code for ARM platforms.
 */

#include <conf/config.h>
#include <machine/memory.h>
#include <machine/syspage.h>

#define ENTRY(x) .global x; .align 2; x##:

	.section ".start","ax"
#ifdef CONFIG_BOOT_THUMB
	.syntax unified
	.thumb
	.thumb_func
#else
	.code 32
#endif
/*
 * Loader entry point
 */
ENTRY(boot_entry)
#ifdef CONFIG_BOOT_THUMB
	/* If we started in ARM mode, switch to Thumb */
	.code 32
	adr	r0, 1f + 1
	bx	r0
	.thumb
1:
#endif
	b	start_vector

	.align 2
#ifdef CONFIG_BOOT_THUMB
	.thumb
#else
	.code 32
#endif
stack_end:	.word	(BOOTSTKTOP - KERNOFFSET)

start_vector:
#ifdef CONFIG_BOOT_THUMB
	mov.w	r0, #0xd3		/* Enter SVC mode, Disable IRQ,FIQ */
#else
	mov	r0, #0xd3		/* Enter SVC mode, Disable IRQ,FIQ */
#endif
	msr	cpsr_c, r0
	ldr	sp, stack_end

#ifdef CONFIG_BOOT_THUMB
	ldr	r0, =main
	bx	r0
#else
	adr	r0, thumb_mode + 1
	bx	r0
	.code 16
thumb_mode:

	ldr	r0, =main
	bx	r0			/* Change to ARM mode */
#endif

	.section .tail,"ax"
dummy:
	.byte	0xff

.end

.section .note.GNU-stack,"",%progbits
