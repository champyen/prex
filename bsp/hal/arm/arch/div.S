/*-
 * Copyright (c) 2026, Champ Yen
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
 * div.S - division routines for ARM
 */

#include <machine/asm.h>

	.text
	.arm

/*
 * unsigned int __aeabi_uidiv(unsigned int num, unsigned int den)
 *
 * r0 = num
 * r1 = den
 * returns r0 = num / den
 */
ENTRY(__aeabi_uidiv)
	subs	r2, r1, #1
	bxeq	lr			/* den == 1, return num */
	bcc	L_div_zero		/* den == 0, error */

	mov	r2, r1
	mov	r1, r0
	mov	r0, #0
	mov	r3, #1

L_loop1:
	cmp	r2, r1, lsr #1
	movls	r2, r2, lsl #1
	movls	r3, r3, lsl #1
	bls	L_loop1

L_loop2:
	cmp	r1, r2
	subcs	r1, r1, r2
	addcs	r0, r0, r3
	movs	r3, r3, lsr #1
	movne	r2, r2, lsr #1
	bne	L_loop2
	bx	lr

L_div_zero:
	/* Division by zero */
	mov	r0, #0
	bx	lr

/*
 * void __aeabi_uidivmod(unsigned int num, unsigned int den)
 *
 * r0 = num
 * r1 = den
 * returns r0 = num / den, r1 = num % den
 */
ENTRY(__aeabi_uidivmod)
	push	{lr}
	bl	__aeabi_uidiv
	/* After __aeabi_uidiv, r0 = quotient, r1 = remainder (from shift-subtract) */
	pop	{pc}
