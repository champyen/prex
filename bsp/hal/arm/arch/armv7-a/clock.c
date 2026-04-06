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
 * clock.c - ARM Generic Timer driver
 */

#include <kernel.h>
#include <timer.h>
#include <irq.h>
#include <cpufunc.h>
#include <sys/ipl.h>

/*
 * Default IRQ for Physical Timer (PPI)
 */
#ifndef CLOCK_IRQ
#define CLOCK_IRQ 30
#endif

static uint32_t timer_count;

/*
 * Clock interrupt service routine.
 */
static int clock_isr(void* arg)
{
    splhigh();
    /* Program next timeout */
    set_cntp_tval_reg(timer_count);
    timer_handler();
    spl0();

    return INT_DONE;
}

/*
 * Initialize clock H/W chip.
 */
void clock_init(void)
{
    uint32_t freq;

    freq = get_cntfrq();
    timer_count = freq / CONFIG_HZ;

    /* Install ISR */
    irq_attach(CLOCK_IRQ, IPL_CLOCK, 0, clock_isr, IST_NONE, NULL);

    /* Program first timeout */
    set_cntp_tval_reg(timer_count);

    /* Enable physical timer: ENABLE=1, IMASK=0 */
    set_cntp_ctl_reg(1);

    DPRINTF(("ARM Generic Timer: %d Hz, IRQ %d\n", freq, CLOCK_IRQ));
}
