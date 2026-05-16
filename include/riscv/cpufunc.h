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

#ifndef _RISCV_CPUFUNC_H
#define _RISCV_CPUFUNC_H

#include <sys/types.h>

static inline void io_barrier(void)
{
    __asm__ volatile("fence i, o" : : : "memory");
}

static inline void memory_barrier(void)
{
    __asm__ volatile("fence iorw, iorw" : : : "memory");
}

#endif /* !_RISCV_CPUFUNC_H */
