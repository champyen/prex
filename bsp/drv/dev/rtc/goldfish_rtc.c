/*-
 * Copyright (c) 2005-2009, Kohsuke Ohtani
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
 * goldfish_rtc.c - Google Goldfish RTC driver
 */

#include <sys/time.h>
#include <sys/ioctl.h>

#include <driver.h>
#include <rtc.h>

#define RTC_BASE CONFIG_GOLDFISH_RTC_BASE

#define GOLDFISH_TIMER_TIME_LOW         0x00  /* RO low 32-bits of time */
#define GOLDFISH_TIMER_TIME_HIGH        0x04  /* RO high 32-bits of time */

static int goldfish_rtc_init(struct driver*);
static int goldfish_rtc_gettime(void*, struct timeval*);
static int goldfish_rtc_settime(void*, struct timeval*);

struct driver goldfish_rtc_driver = {
    /* name */ "goldfish_rtc",
    /* devops */ NULL,
    /* devsz */ 0,
    /* flags */ 0,
    /* probe */ NULL,
    /* init */ goldfish_rtc_init,
    /* shutdown */ NULL,
};

struct rtc_ops goldfish_rtc_ops = {
    /* gettime */ goldfish_rtc_gettime,
    /* settime */ goldfish_rtc_settime,
};

static int goldfish_rtc_gettime(void* aux, struct timeval* tv)
{
    uint32_t l32 = bus_read_32(RTC_BASE + GOLDFISH_TIMER_TIME_LOW);
    uint32_t h32 = bus_read_32(RTC_BASE + GOLDFISH_TIMER_TIME_HIGH);
    uint64_t nsec = ((uint64_t)h32 << 32) | l32;

    tv->tv_sec = (long)(nsec / 1000000000ULL);
    tv->tv_usec = (long)((nsec % 1000000000ULL) / 1000ULL);
    return 0;
}

static int goldfish_rtc_settime(void* aux, struct timeval* tv)
{
    /* Goldfish RTC time is read-only from the VM clock */
    return 0;
}

static int goldfish_rtc_init(struct driver* self)
{
    rtc_attach(&goldfish_rtc_ops, NULL);
    return 0;
}
