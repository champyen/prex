/*-
 * Copyright (c) 2005-2009, Kohsuke Ohtani
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
 * pl031.c - ARM PrimeCell PL031 RTC
 */

#include <sys/time.h>
#include <sys/ioctl.h>

#include <driver.h>
#include <rtc.h>

#define RTC_BASE CONFIG_PL031_BASE

#define PL031_RTCDR         0x00     /* RO Data read register */
#define PL031_RTCMR         0x04     /* RW Match register */
#define PL031_RTCLR         0x08     /* RW Data load register */
#define PL031_RTCCR         0x0c     /* RW Control register */
#define PL031_RTCIMSC       0x10     /* RW Interrupt mask and set register */
#define PL031_RTCRIS        0x14     /* RO Raw interrupt status register */
#define PL031_RTCMIS        0x18     /* RO Masked interrupt status register */
#define PL031_RTCICR        0x1c     /* WO Interrupt clear register */

static int pl031_init(struct driver*);
static int pl031_gettime(void*, struct timeval*);
static int pl031_settime(void*, struct timeval*);

struct driver pl031_driver = {
    /* name */ "pl031",
    /* devops */ NULL,
    /* devsz */ 0,
    /* flags */ 0,
    /* probe */ NULL,
    /* init */ pl031_init,
    /* shutdown */ NULL,
};

struct rtc_ops pl031_ops = {
    /* gettime */ pl031_gettime,
    /* settime */ pl031_settime,
};

static int pl031_gettime(void* aux, struct timeval* tv)
{
    tv->tv_usec = 0;
    tv->tv_sec = bus_read_32(RTC_BASE + PL031_RTCDR);
    return 0;
}

static int pl031_settime(void* aux, struct timeval* tv)
{
    bus_write_32(RTC_BASE + PL031_RTCLR, (uint32_t)tv->tv_sec);
    return 0;
}

static int pl031_init(struct driver* self)
{
    /* Enable RTC */
    bus_write_32(RTC_BASE + PL031_RTCCR, 1);

    rtc_attach(&pl031_ops, NULL);
    return 0;
}
