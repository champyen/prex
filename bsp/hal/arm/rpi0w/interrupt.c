/*-
 * Copyright (c) 2008, Kohsuke Ohtani
 * Copyright (c) 2021, Champ Yen (champ.yen@gmail.com)
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
 * interrupt.c - interrupt handling routines
 */

#include <sys/ipl.h>
#include <kernel.h>
#include <hal.h>
#include <irq.h>
#include <cpufunc.h>
#include <context.h>
#include <locore.h>

#include "platform.h"

/* Number of IRQ lines */
#define NIRQS 96

/* Registers for interrupt control unit - enable/flag/master */
#define ICU_IRQSTS0 (*(volatile uint32_t*)(ICU_BASE + 0x200))
#define ICU_IRQSTS1 (*(volatile uint32_t*)(ICU_BASE + 0x204))
#define ICU_IRQSTS2 (*(volatile uint32_t*)(ICU_BASE + 0x208))
#define ICU_IRQSTS(idx) (*(volatile uint32_t*)(ICU_BASE + 0x204 + 4 * idx))
#define IRQ_FIQ (*(volatile uint32_t*)(ICU_BASE + 0x20C))

#define ICU_IRQENSET0 (*(volatile uint32_t*)(ICU_BASE + 0x210))
#define ICU_IRQENSET1 (*(volatile uint32_t*)(ICU_BASE + 0x214))
#define ICU_IRQENSET2 (*(volatile uint32_t*)(ICU_BASE + 0x218))
#define ICU_IRQENSET(idx) (*(volatile uint32_t*)(ICU_BASE + 0x210 + 4 * idx))

#define ICU_IRQENCLR0 (*(volatile uint32_t*)(ICU_BASE + 0x21C))
#define ICU_IRQENCLR1 (*(volatile uint32_t*)(ICU_BASE + 0x220))
#define ICU_IRQENCLR2 (*(volatile uint32_t*)(ICU_BASE + 0x224))
#define ICU_IRQENCLR(idx) (*(volatile uint32_t*)(ICU_BASE + 0x21C + 4 * idx))

static uint32_t irq_conv[] = {7, 9, 10, 18, 19, 53, 54, 55, 56, 57, 62};

/*
 * Interrupt Priority Level
 *
 * Each interrupt has its logical priority level, with 0 being
 * the lowest priority. While some ISR is running, all lower
 * priority interrupts are masked off.
 */
volatile int irq_level;

/*
 * Interrupt mapping table
 */
static int ipl_table[NIRQS];          /* vector -> level */
static uint32_t mask_table[NIPLS][3]; /* level -> mask */

/*
 * Set mask for current ipl
 */
static void update_mask(int old_ipl, int new_ipl)
{
    u_int mask = mask_table[irq_level][0];
    u_int mask1 = mask_table[irq_level][1];
    u_int mask2 = mask_table[irq_level][2];

    if(old_ipl < new_ipl){
        ICU_IRQENCLR(0) = ~mask;
        ICU_IRQENCLR(1) = ~mask1;
        ICU_IRQENCLR(2) = ~mask2;
    } else {
        ICU_IRQENSET(0) = mask;
        ICU_IRQENSET(1) = mask1;
        ICU_IRQENSET(2) = mask2;
    }
}

/*
 * Unmask interrupt in ICU for specified irq.
 * The interrupt mask table is also updated.
 * Assumes CPU interrupt is disabled in caller.
 */
void interrupt_unmask(int vector, int level)
{
    int i;
    uint32_t vidx = (vector >> 5);
    uint32_t unmask = (uint32_t)1 << (vector & 0x1F);

    /* Save level mapping */
    ipl_table[vector] = level;

    /*
     * Unmask the target interrupt for all
     * lower interrupt levels.
     */
    for (i = 0; i < level; i++)
        mask_table[i][vidx] |= unmask;
    ICU_IRQENSET(vidx) = mask_table[irq_level][vidx];
}

/*
 * Mask interrupt in ICU for specified irq.
 * Interrupt must be disabled when this routine is called.
 */
void interrupt_mask(int vector)
{
    int i, level;
    uint32_t vidx = (vector >> 5);
    u_int mask = (uint16_t) ~(1 << (vector & 0x1F));

    level = ipl_table[vector];
    for (i = 0; i < level; i++)
        mask_table[i][vidx] &= mask;
    ICU_IRQENCLR(vidx) = ~(mask_table[irq_level][vidx]);
    ipl_table[vector] = IPL_NONE;
}

/*
 * Setup interrupt mode.
 * Select whether an interrupt trigger is edge or level.
 */
void interrupt_setup(int vector, int mode)
{
    /* nop */
}

/*
 * Common interrupt handler.
 */
void interrupt_handler(void)
{
    uint32_t bits, vidx;
    uint32_t vector, old_ipl, new_ipl;

    /* Get interrupt source */
    bits = ICU_IRQSTS0;
    for (vector = 0; vector < 21; vector++) {
        if (bits & (uint32_t)(1 << vector))
            break;
    }

    switch (vector) {
    case 8 ... 9:
        vidx = (vector - 8);
        bits = ICU_IRQSTS(vidx);
        for (vector = 0; vector < 32; vector++) {
            if (bits & (uint32_t)(1 << vector))
                break;
        }
        vector += (vidx << 5);
        break;
    case 10 ... 20:
        vector = irq_conv[vector - 10];
        break;
    case 21:
        goto out;
    default:
        vector += 64;
        break;
    }

    /* Adjust interrupt level */
    old_ipl = irq_level;
    new_ipl = ipl_table[vector];
    if (new_ipl > old_ipl) /* Ignore spurious interrupt */
        irq_level = new_ipl;
    update_mask(old_ipl, new_ipl);

    /* Allow another interrupt that has higher priority */
    splon();

    /* Dispatch interrupt */
    irq_handler(vector);

    sploff();

    /* Restore interrupt level */
    irq_level = old_ipl;
    update_mask(new_ipl, old_ipl);
out:
    return;
}

/*
 * Initialize interrupt controllers.
 * All interrupts will be masked off.
 */
void interrupt_init(void)
{
    int i;

    irq_level = IPL_NONE;

    for (i = 0; i < NIRQS; i++)
        ipl_table[i] = IPL_NONE;

    for (i = 0; i < NIPLS; i++) {
        mask_table[i][0] = 0;
        mask_table[i][1] = 0;
        mask_table[i][2] = 0;
    }

    ICU_IRQENCLR(0) = 0xFFFFFFFF;
    ICU_IRQENCLR(1) = 0xFFFFFFFF;
    ICU_IRQENCLR(2) = 0xFFFFFFFF;
}
