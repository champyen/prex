/*
 * Copyright (c) 2009-2010, Richard Pandion
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

#ifndef _BEAGLE_PLATFORM_H
#define _BEAGLE_PLATFORM_H

/* number of interrupt vectors */
#define NIRQS 96

#ifdef CONFIG_MMU
/* base address for L4 Peripherals registers */
#define L4_Per 0xa9000000
/* base address for L4 Core registers */
#define L4_Core 0xa8000000
#else
/* base address for L4 Peripherals registers */
#define L4_Per 0x49000000
/* base address for L4 Core registers */
#define L4_Core 0x48000000
#endif

#define L4_PRCM_CM (L4_Core + 0x4000)
#define L4_MPU_INTC (L4_Core + 0x200000)

#define L4_UART3 (L4_Per + 0x20000)
#define L4_GPTIMER2 (L4_Per + 0x32000)

#define UART_BASE L4_UART3
#define TIMER_BASE L4_GPTIMER2
#define MPU_INTC_BASE L4_MPU_INTC
#define PER_CM_BASE (L4_PRCM_CM + 0x1000)

__BEGIN_DECLS
void mpu_intc_sync(void);
void set_vbar(vaddr_t);
void machine_reset(void);
__END_DECLS

#endif /* !_BEAGLE_PLATFORM_H */
