/*
 * Copyright (c) 2007, Kohsuke Ohtani
 * All rights reserved.
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * ...
 */

#ifndef _RISCV_SIGNAL_H
#define _RISCV_SIGNAL_H

typedef int sig_atomic_t;

struct sigcontext
{
    int sc_onstack;
    int sc_mask;

    int sc_ra;      /* x1 */
    int sc_sp;      /* x2 */
    int sc_gp;      /* x3 */
    int sc_tp;      /* x4 */
    int sc_t0;      /* x5 */
    int sc_t1;      /* x6 */
    int sc_t2;      /* x7 */
    int sc_s0;      /* x8 */
    int sc_s1;      /* x9 */
    int sc_a0;      /* x10 */
    int sc_a1;      /* x11 */
    int sc_a2;      /* x12 */
    int sc_a3;      /* x13 */
    int sc_a4;      /* x14 */
    int sc_a5;      /* x15 */
    int sc_a6;      /* x16 */
    int sc_a7;      /* x17 */
    int sc_s2;      /* x18 */
    int sc_s3;      /* x19 */
    int sc_s4;      /* x20 */
    int sc_s5;      /* x21 */
    int sc_s6;      /* x22 */
    int sc_s7;      /* x23 */
    int sc_s8;      /* x24 */
    int sc_s9;      /* x25 */
    int sc_s10;     /* x26 */
    int sc_s11;     /* x27 */
    int sc_t3;      /* x28 */
    int sc_t4;      /* x29 */
    int sc_t5;      /* x30 */
    int sc_t6;      /* x31 */
    int sc_pc;      /* epc */
    int sc_status;  /* sstatus */
};

#endif /* !_RISCV_SIGNAL_H */
