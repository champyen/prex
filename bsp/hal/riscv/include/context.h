/*-
 * Copyright (c) 2005-2009, Kohsuke Ohtani
 * All rights reserved.
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * ...
 */

#ifndef _RISCV_CONTEXT_H
#define _RISCV_CONTEXT_H

#ifndef __ASSEMBLY__
#include <sys/types.h>

/*
 * Common register frame for trap/interrupt.
 */
struct cpu_regs
{
    uint32_t ra;      /* x1 */
    uint32_t sp;      /* x2 */
    uint32_t gp;      /* x3 */
    uint32_t tp;      /* x4 */
    uint32_t t0;      /* x5 */
    uint32_t t1;      /* x6 */
    uint32_t t2;      /* x7 */
    uint32_t s0;      /* x8 / fp */
    uint32_t s1;      /* x9 */
    uint32_t a0;      /* x10 */
    uint32_t a1;      /* x11 */
    uint32_t a2;      /* x12 */
    uint32_t a3;      /* x13 */
    uint32_t a4;      /* x14 */
    uint32_t a5;      /* x15 */
    uint32_t a6;      /* x16 */
    uint32_t a7;      /* x17 */
    uint32_t s2;      /* x18 */
    uint32_t s3;      /* x19 */
    uint32_t s4;      /* x20 */
    uint32_t s5;      /* x21 */
    uint32_t s6;      /* x22 */
    uint32_t s7;      /* x23 */
    uint32_t s8;      /* x24 */
    uint32_t s9;      /* x25 */
    uint32_t s10;     /* x26 */
    uint32_t s11;     /* x27 */
    uint32_t t3;      /* x28 */
    uint32_t t4;      /* x29 */
    uint32_t t5;      /* x30 */
    uint32_t t6;      /* x31 */
    uint32_t pc;      /* epc */
    uint32_t status;  /* sstatus */
    uint32_t cause;   /* scause */
    uint32_t badaddr; /* stval */
};

/*
 * Kernel mode context for context switching.
 * Saves callee-saved registers.
 */
struct kern_regs
{
    uint32_t s0;
    uint32_t s1;
    uint32_t s2;
    uint32_t s3;
    uint32_t s4;
    uint32_t s5;
    uint32_t s6;
    uint32_t s7;
    uint32_t s8;
    uint32_t s9;
    uint32_t s10;
    uint32_t s11;
    uint32_t sp;
    uint32_t ra;
};

/*
 * Processor context
 */
struct context
{
    struct kern_regs kregs;      /* kernel mode registers */
    struct cpu_regs* uregs;      /* user mode registers */
    struct cpu_regs* saved_regs; /* savecd user mode registers */
};

typedef struct context* context_t; /* context id */

void cpu_switch(struct kern_regs* prev, struct kern_regs* next);

#endif /* !__ASSEMBLY__ */

#define CTXREGS (4 * 35)

/*
 * Per-CPU control structure offsets
 */
#define CPU_ACTIVE_THREAD 0x00
#define CPU_IDLE_THREAD 0x04
#define CPU_NEST_COUNT 0x08
#define CPU_SPL_LEVEL 0x0c
#define CPU_INT_STACK 0x10

#endif /* !_RISCV_CONTEXT_H */
