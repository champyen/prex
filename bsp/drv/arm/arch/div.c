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
 * div.c - division routines for ARM
 */

#include <sys/types.h>

/*
 * ARM EABI defines that {u}idivmod returns quotient in R0 and remainder in R1.
 * In GCC, a struct of two 32-bit words is returned in R0 and R1, which matches
 * the EABI requirement.
 */
typedef struct
{
    unsigned int quot;
    unsigned int rem;
} uidiv_return_t;

typedef struct
{
    int quot;
    int rem;
} idiv_return_t;

/*
 * unsigned int __aeabi_uidiv(unsigned int num, unsigned int den)
 */
unsigned int __aeabi_uidiv(unsigned int num, unsigned int den)
{
    if (den == 0)
        return 0;

#if defined(CONFIG_ARMV7A)
    /* Use ARMv7-A hardware division if available */
    unsigned int res;
    __asm__ volatile("udiv %0, %1, %2" : "=r"(res) : "r"(num), "r"(den));
    return res;
#else
    unsigned int quot = 0;
    unsigned int qbit = 1;

    if (num < den)
        return 0;

    /* Fallback: manual bit counting */
    int shift = 0;
    unsigned int temp_den = den;
    unsigned int temp_num = num;
    while ((temp_den & 0x80000000) == 0 && temp_den < temp_num) {
        temp_den <<= 1;
        shift++;
    }
    den <<= shift;
    qbit <<= shift;

    while (qbit > 0) {
        if (num >= den) {
            num -= den;
            quot += qbit;
        }
        den >>= 1;
        qbit >>= 1;
    }
    return quot;
#endif
}

/*
 * uidiv_return_t __aeabi_uidivmod(unsigned int num, unsigned int den)
 */
uidiv_return_t __aeabi_uidivmod(unsigned int num, unsigned int den)
{
    unsigned int q = __aeabi_uidiv(num, den);
    unsigned int r = num - (q * den);
    return (uidiv_return_t){q, r};
}

/*
 * int __aeabi_idiv(int num, int den)
 */
int __aeabi_idiv(int num, int den)
{
    if (den == 0)
        return 0;

#if defined(CONFIG_ARMV7A)
    /* Use ARMv7-A hardware division if available */
    int res;
    __asm__ volatile("sdiv %0, %1, %2" : "=r"(res) : "r"(num), "r"(den));
    return res;
#else
    unsigned int u_num = (num < 0) ? (unsigned int)-num : (unsigned int)num;
    unsigned int u_den = (den < 0) ? (unsigned int)-den : (unsigned int)den;
    unsigned int u_quot = __aeabi_uidiv(u_num, u_den);
    int quot = (int)u_quot;
    if ((num ^ den) < 0)
        quot = -quot;
    return quot;
#endif
}

/*
 * idiv_return_t __aeabi_idivmod(int num, int den)
 */
idiv_return_t __aeabi_idivmod(int num, int den)
{
    int q = __aeabi_idiv(num, den);
    int r = num - (q * den);
    return (idiv_return_t){q, r};
}
