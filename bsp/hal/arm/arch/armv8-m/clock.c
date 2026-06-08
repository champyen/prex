/*-
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
 * clock.c - armv8-m SysTick timer driver
 */

#include <kernel.h>
#include <timer.h>
#include <irq.h>
#include <cpufunc.h>
#include <sys/ipl.h>

/* SysTick Registers */
#define SYST_CSR   (*(volatile uint32_t*)0xE000E010)
#define SYST_RVR   (*(volatile uint32_t*)0xE000E014)
#define SYST_CVR   (*(volatile uint32_t*)0xE000E018)
#define SYST_CALIB (*(volatile uint32_t*)0xE000E01C)

#define SYST_CSR_ENABLE    0x00000001
#define SYST_CSR_TICKINT   0x00000002
#define SYST_CSR_CLKSOURCE 0x00000004
#define SYST_CSR_COUNTFLAG 0x01000000

#define SCB_SHPR3    (*(volatile uint32_t*)0xE000ED20)

/*
 * Initialize clock H/W chip.
 */
void clock_init(void)
{
    /* 
     * Musca-B1 CPU freq is 50MHz by default in QEMU.
     */
    uint32_t freq = 50000000; 
    uint32_t ticks = freq / CONFIG_HZ;
    
    /* Set SysTick priority (0x60, matching IPL_CLOCK mask) */
    SCB_SHPR3 = (SCB_SHPR3 & 0x00FFFFFF) | 0x60000000; 

    SYST_RVR = ticks - 1;
    SYST_CVR = 0;
    SYST_CSR = SYST_CSR_CLKSOURCE | SYST_CSR_TICKINT | SYST_CSR_ENABLE;
    
    DPRINTF(("SysTick: %d ticks at %d Hz\n", ticks, freq));
}

#ifdef CONFIG_SMP
void clock_ap_init(void)
{
    /* SysTick is per-core */
    uint32_t freq = 50000000; 
    uint32_t ticks = freq / CONFIG_HZ;
    
    SYST_RVR = ticks - 1;
    SYST_CVR = 0;
    SYST_CSR = SYST_CSR_CLKSOURCE | SYST_CSR_TICKINT | SYST_CSR_ENABLE;
}
#endif
