/*
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
 * All rights reserved.
 */

#ifndef _RISCV_CONTEXT_H
#define _RISCV_CONTEXT_H

#include <machine/types.h>

#ifndef __ASSEMBLY__

/*
 * Register state for trap/interrupt (struct cpu_regs)
 * Total size: 144 bytes (16-byte aligned)
 */
struct cpu_regs
{
    uint32_t ra;       /* 0 */
    uint32_t sp;       /* 4 */
    uint32_t gp;       /* 8 */
    uint32_t tp;       /* 12 */
    uint32_t t0;       /* 16 */
    uint32_t t1;       /* 20 */
    uint32_t t2;       /* 24 */
    uint32_t s0;       /* 28 */
    uint32_t s1;       /* 32 */
    uint32_t a0;       /* 36 */
    uint32_t a1;       /* 40 */
    uint32_t a2;       /* 44 */
    uint32_t a3;       /* 48 */
    uint32_t a4;       /* 52 */
    uint32_t a5;       /* 56 */
    uint32_t a6;       /* 60 */
    uint32_t a7;       /* 64 */
    uint32_t s2;       /* 68 */
    uint32_t s3;       /* 72 */
    uint32_t s4;       /* 76 */
    uint32_t s5;       /* 80 */
    uint32_t s6;       /* 84 */
    uint32_t s7;       /* 88 */
    uint32_t s8;       /* 92 */
    uint32_t s9;       /* 96 */
    uint32_t s10;      /* 100 */
    uint32_t s11;      /* 104 */
    uint32_t t3;       /* 108 */
    uint32_t t4;       /* 112 */
    uint32_t t5;       /* 116 */
    uint32_t t6;       /* 120 */
    uint32_t epc;      /* 124 (sepc) */
    uint32_t status;   /* 128 (sstatus) */
    uint32_t cause;    /* 132 (scause) */
    uint32_t badaddr;  /* 136 (stval) */
    uint32_t padding;  /* 140 - for 16-byte alignment */
};

/*
 * Kernel mode context for context switching
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
    struct cpu_regs* saved_regs; /* saved user mode registers */
};

typedef struct context *context_t;

#endif /* !__ASSEMBLY__ */

#endif /* !_RISCV_CONTEXT_H */
