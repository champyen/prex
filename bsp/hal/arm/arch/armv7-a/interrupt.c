/*-
 * Copyright (c) 2005-2007, Kohsuke Ohtani
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
 * interrupt.c - interrupt handling routines for ARM GICv2
 */

#include <sys/ipl.h>
#include <kernel.h>
#include <hal.h>
#include <irq.h>
#include <cpufunc.h>
#include <context.h>
#include <locore.h>

/* GIC Distributor Registers */
#define GICD_CTLR (*(volatile uint32_t*)(CONFIG_GIC_DIST_BASE + 0x000))
#define GICD_TYPER (*(volatile uint32_t*)(CONFIG_GIC_DIST_BASE + 0x004))
#define GICD_ISENABLER(n) (*(volatile uint32_t*)(CONFIG_GIC_DIST_BASE + 0x100 + (n) * 4))
#define GICD_ICENABLER(n) (*(volatile uint32_t*)(CONFIG_GIC_DIST_BASE + 0x180 + (n) * 4))
#define GICD_IPRIORITYR(n) (*(volatile uint32_t*)(CONFIG_GIC_DIST_BASE + 0x400 + (n) * 4))
#define GICD_ITARGETSR(n) (*(volatile uint32_t*)(CONFIG_GIC_DIST_BASE + 0x800 + (n) * 4))
#define GICD_ICFGR(n) (*(volatile uint32_t*)(CONFIG_GIC_DIST_BASE + 0xc00 + (n) * 4))

/* GIC CPU Interface Registers */
#define GICC_CTLR (*(volatile uint32_t*)(CONFIG_GIC_CPU_BASE + 0x000))
#define GICC_PMR (*(volatile uint32_t*)(CONFIG_GIC_CPU_BASE + 0x004))
#define GICC_BPR (*(volatile uint32_t*)(CONFIG_GIC_CPU_BASE + 0x008))
#define GICC_IAR (*(volatile uint32_t*)(CONFIG_GIC_CPU_BASE + 0x00c))
#define GICC_EOIR (*(volatile uint32_t*)(CONFIG_GIC_CPU_BASE + 0x010))

/*
 * Interrupt Priority Level
 */
volatile int irq_level;

/*
 * Interrupt mapping table
 */
static int ipl_table[CONFIG_NIRQS];
static uint32_t mask_table[NIPLS][CONFIG_NIRQS / 32];

/*
 * Set mask for current ipl
 */
static void update_mask(void)
{
    int i;
    uint32_t mask;

    for (i = 0; i < CONFIG_NIRQS / 32; i++) {
        mask = mask_table[irq_level][i];
        GICD_ICENABLER(i) = ~mask;
        GICD_ISENABLER(i) = mask;
    }
}

/*
 * Unmask interrupt in GIC for specified irq.
 */
void interrupt_unmask(int vector, int level)
{
    int i;
    uint32_t unmask = (uint32_t)1 << (vector % 32);

    ipl_table[vector] = level;

    for (i = 0; i < level; i++)
        mask_table[i][vector / 32] |= unmask;

    /* Set priority: 0 is highest, Prex uses higher numbers for higher priority? 
       No, Prex spl0 is 0, splhigh is 15. GIC 0 is highest. 
       We map Prex IPL to GIC priority. */
    uint32_t prio = (uint32_t)(NIPLS - level) << 4; /* Simplistic mapping */
    uint32_t reg = GICD_IPRIORITYR(vector / 4);
    int shift = (vector % 4) * 8;
    reg &= ~(0xff << shift);
    reg |= (prio << shift);
    GICD_IPRIORITYR(vector / 4) = reg;

    /* Target CPU0 */
    uint32_t target = GICD_ITARGETSR(vector / 4);
    target &= ~(0xff << shift);
    target |= (0x01 << shift);
    GICD_ITARGETSR(vector / 4) = target;

    update_mask();
}

/*
 * Mask interrupt in GIC for specified irq.
 */
void interrupt_mask(int vector)
{
    int i, level;
    uint32_t mask = ~((uint32_t)1 << (vector % 32));

    level = ipl_table[vector];
    for (i = 0; i < level; i++)
        mask_table[i][vector / 32] &= mask;

    ipl_table[vector] = IPL_NONE;
    GICD_ICENABLER(vector / 32) = (1 << (vector % 32));
    update_mask();
}

/*
 * Setup interrupt mode.
 */
void interrupt_setup(int vector, int mode)
{
    uint32_t reg = GICD_ICFGR(vector / 16);
    int shift = (vector % 16) * 2;
    reg &= ~(0x03 << shift);
    if (mode == IMODE_EDGE)
        reg |= (0x02 << shift);
    else
        reg |= (0x01 << shift); /* Level sensitive */
    GICD_ICFGR(vector / 16) = reg;
}

/*
 * Common interrupt handler.
 */
void interrupt_handler(void)
{
    uint32_t iar;
    int vector, old_ipl, new_ipl;

    iar = GICC_IAR;
    vector = iar & 0x3ff;

    if (vector >= 1022) /* Spurious */
        return;

    /* Adjust interrupt level */
    old_ipl = irq_level;
    new_ipl = ipl_table[vector];
    if (new_ipl > old_ipl)
        irq_level = new_ipl;
    
    update_mask();

    /* Allow another interrupt that has higher priority */
    splon();

    /* Dispatch interrupt */
    irq_handler(vector);

    sploff();

    /* End of Interrupt */
    GICC_EOIR = iar;

    /* Restore interrupt level */
    irq_level = old_ipl;
    update_mask();
}

/*
 * Initialize GIC.
 */
void interrupt_init(void)
{
    int i, j;

    irq_level = IPL_NONE;

    for (i = 0; i < CONFIG_NIRQS; i++)
        ipl_table[i] = IPL_NONE;

    for (i = 0; i < NIPLS; i++)
        for (j = 0; j < CONFIG_NIRQS / 32; j++)
            mask_table[i][j] = 0;

    /* Disable Distributor */
    GICD_CTLR = 0;

    /* Mask and clear all interrupts */
    for (i = 0; i < CONFIG_NIRQS / 32; i++) {
        GICD_ICENABLER(i) = 0xffffffff;
    }

    /* Default priority and target */
    for (i = 0; i < CONFIG_NIRQS / 4; i++) {
        GICD_IPRIORITYR(i) = 0xa0a0a0a0;
        GICD_ITARGETSR(i) = 0x01010101;
    }

    /* Enable Distributor */
    GICD_CTLR = 1;

    /* CPU Interface */
    GICC_PMR = 0xf0; /* Allow all interrupts */
    GICC_BPR = 0;    /* No grouping */
    GICC_CTLR = 1;   /* Enable CPU interface */
}
