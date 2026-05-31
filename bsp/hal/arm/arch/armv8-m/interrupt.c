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
 * interrupt.c - interrupt handling routines for armv8-m NVIC
 */

#include <sys/ipl.h>
#include <kernel.h>
#include <hal.h>
#include <irq.h>
#include <cpufunc.h>
#include <context.h>
#include <locore.h>

/* NVIC Registers */
#define NVIC_ISER(n) (*(volatile uint32_t*)(0xE000E100 + (n) * 4))
#define NVIC_ICER(n) (*(volatile uint32_t*)(0xE000E180 + (n) * 4))
#define NVIC_ISPR(n) (*(volatile uint32_t*)(0xE000E200 + (n) * 4))
#define NVIC_ICPR(n) (*(volatile uint32_t*)(0xE000E280 + (n) * 4))
#define NVIC_IABR(n) (*(volatile uint32_t*)(0xE000E300 + (n) * 4))
#define NVIC_IPR(n)  (*(volatile uint32_t*)(0xE000E400 + (n) * 4))

/* SCB Registers */
#define SCB_ICSR     (*(volatile uint32_t*)0xE000ED04)
#define SCB_SHPR1    (*(volatile uint32_t*)0xE000ED18)
#define SCB_SHPR2    (*(volatile uint32_t*)0xE000ED1C)
#define SCB_SHPR3    (*(volatile uint32_t*)0xE000ED20)

/*
 * Interrupt mapping table
 */
static int ipl_table[CONFIG_NIRQS];

/*
 * Set mask for current ipl
 */
static void update_mask(void)
{
    /* 
     * Cortex-M uses BASEPRI for priority masking.
     * Prex IPL 0 (spl0) allows all.
     * Prex IPL 15 (splhigh) masks all.
     */
    uint32_t prio = (uint32_t)(NIPLS - curspl) << 4;
    if (curspl == 0) prio = 0;
    __asm__ volatile("msr basepri, %0" : : "r"(prio) : "memory");
}

/*
 * Unmask interrupt in NVIC for specified irq.
 */
void interrupt_unmask(int vector, int level)
{
    if (vector < 0) return;
    
    ipl_table[vector] = level;
    uint32_t prio = (uint32_t)(NIPLS - level) << 4;
    
    uint32_t reg = NVIC_IPR(vector / 4);
    int shift = (vector % 4) * 8;
    reg &= ~(0xff << shift);
    reg |= (prio << shift);
    NVIC_IPR(vector / 4) = reg;
    
    NVIC_ISER(vector / 32) = (1 << (vector % 32));
    update_mask();
}

/*
 * Mask interrupt in NVIC for specified irq.
 */
void interrupt_mask(int vector)
{
    if (vector < 0) return;
    ipl_table[vector] = IPL_NONE;
    NVIC_ICER(vector / 32) = (1 << (vector % 32));
    update_mask();
}

/*
 * Setup interrupt mode.
 */
void interrupt_setup(int vector, int mode)
{
}

/*
 * Common interrupt handler.
 */
void interrupt_handler(void)
{
    uint32_t ipsr;
    __asm__ volatile("mrs %0, ipsr" : "=r"(ipsr));
    
    int vector = (int)ipsr - 16;
    int old_ipl, new_ipl;

    /* SysTick is vector -1 */
    if (vector == -1) {
        old_ipl = curspl;
        if (IPL_CLOCK > old_ipl)
            curspl = IPL_CLOCK;
        update_mask();
        splon();
        timer_handler();
        sploff();
        curspl = old_ipl;
        update_mask();
        return;
    }

    if (vector < 0) { /* System handlers */
        return;
    }

    /* Adjust interrupt level */
    old_ipl = curspl;
    new_ipl = ipl_table[vector];
    if (new_ipl > old_ipl)
        curspl = new_ipl;

    update_mask();

    /* Allow another interrupt that has higher priority */
    splon();

    /* Dispatch interrupt */
    irq_handler(vector);

    sploff();

    /* Restore interrupt level */
    curspl = old_ipl;
    update_mask();
}

/*
 * Initialize NVIC.
 */
void interrupt_init(void)
{
    int i;

    for (i = 0; i < CONFIG_NIRQS; i++)
        ipl_table[i] = IPL_NONE;

    /* Disable all NVIC interrupts */
    for (i = 0; i < CONFIG_NIRQS / 32; i++) {
        NVIC_ICER(i) = 0xffffffff;
        NVIC_ICPR(i) = 0xffffffff;
    }

    /* Default priority to lowest */
    for (i = 0; i < CONFIG_NIRQS / 4; i++) {
        NVIC_IPR(i) = 0xf0f0f0f0;
    }

    update_mask();
}
