/*-
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * ...
 */

#ifndef _RISCV_SBI_H
#define _RISCV_SBI_H

#include <sys/types.h>

struct sbiret {
    long error;
    long value;
};

static inline struct sbiret sbi_call(long ext, long fid, long arg0, long arg1, long arg2)
{
    struct sbiret ret;
    register long a0 __asm__("a0") = arg0;
    register long a1 __asm__("a1") = arg1;
    register long a2 __asm__("a2") = arg2;
    register long a6 __asm__("a6") = fid;
    register long a7 __asm__("a7") = ext;

    __asm__ volatile("ecall"
                     : "+r"(a0), "+r"(a1)
                     : "r"(a2), "r"(a6), "r"(a7)
                     : "memory");
    ret.error = a0;
    ret.value = a1;
    return ret;
}

/* SBI Extension IDs */
#define SBI_EXT_0_1_SET_TIMER 0x0
#define SBI_EXT_0_1_CONSOLE_PUTCHAR 0x1
#define SBI_EXT_0_1_CONSOLE_GETCHAR 0x2
#define SBI_EXT_BASE 0x10
#define SBI_EXT_TIME 0x54494D45
#define SBI_EXT_SRST 0x53525354

/* SBI Function IDs for Base Extension */
#define SBI_EXT_BASE_GET_SPEC_VERSION 0x0
#define SBI_EXT_BASE_GET_IMP_ID 0x1
#define SBI_EXT_BASE_GET_IMP_VERSION 0x2

/* Legacy SBI calls */
static inline void sbi_console_putchar(int ch)
{
    sbi_call(SBI_EXT_0_1_CONSOLE_PUTCHAR, 0, ch, 0, 0);
}

static inline int sbi_console_getchar(void)
{
    return sbi_call(SBI_EXT_0_1_CONSOLE_GETCHAR, 0, 0, 0, 0).error;
}

static inline void sbi_set_timer(uint64_t stime_value)
{
#if __riscv_xlen == 32
    sbi_call(SBI_EXT_0_1_SET_TIMER, 0, stime_value, stime_value >> 32, 0);
#else
    sbi_call(SBI_EXT_0_1_SET_TIMER, 0, stime_value, 0, 0);
#endif
}

#endif /* !_RISCV_SBI_H */
