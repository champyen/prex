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

#ifndef _ARM_SYSTRAP_H
#define _ARM_SYSTRAP_H

#include <conf/config.h>

/*
 * SYSCALLn macros for use in standalone assembly files (.S)
 */
#ifdef CONFIG_USR_THUMB
#define _SYSCALL_ATTR                                                                                                  \
    .syntax unified;                                                                                                   \
    .thumb;                                                                                                            \
    .thumb_func;
#else
#define _SYSCALL_ATTR
#endif

#if defined(__gba__)
#define __SYSCALL_BODY(id)                                                                                             \
    stmfd sp!, {r4, r5, lr};                                                                                           \
    ldr r4, =id;                                                                                                       \
    ldr r5, =0x200007c;                                                                                                \
    add lr, pc, #2;                                                                                                    \
    bx r5;                                                                                                             \
    ldmfd sp!, {r4, r5, pc}
#elif defined(CONFIG_USR_THUMB)
#define __SYSCALL_BODY(id)                                                                                             \
    svc id;                                                                                                            \
    bx lr
#else
#define __SYSCALL_BODY(id)                                                                                             \
    swi id;                                                                                                            \
    bx lr
#endif

#define SYSCALL_STUB(name, id)                                                                                         \
    _SYSCALL_ATTR ;                                                                                                    \
    .weak name;                                                                                                        \
    .type name, %function;                                                                                             \
    .align 2;                                                                                                          \
    name: __SYSCALL_BODY(id)

#define SYSCALL0(name)                                                                                                 \
    _SYSCALL_ATTR ;                                                                                                    \
    .global name;                                                                                                      \
    .type name, %function;                                                                                             \
    .align 2;                                                                                                          \
    name: __SYSCALL_BODY(SYS_##name)

#define SYSCALL1(name) SYSCALL0(name)
#define SYSCALL2(name) SYSCALL0(name)
#define SYSCALL3(name) SYSCALL0(name)
#define SYSCALL4(name) SYSCALL0(name)

/*
 * C-style string macros for use in __asm__ volatile()
 */
#define __STRINGIFY(x) #x
#define __TOSTRING(x) __STRINGIFY(x)

#if defined(__gba__)
#define __SYSCALL_BODY_STR(id)                                                                                         \
    "stmfd sp!, {r4, r5, lr}\n"                                                                                        \
    "ldr r4, =" __TOSTRING(id) "\n"                                                                                    \
    "ldr r5, =0x200007c\n"                                                                                             \
    "add lr, pc, #2\n"                                                                                                 \
    "bx r5\n"                                                                                                          \
    "ldmfd sp!, {r4, r5, pc}"
#elif defined(CONFIG_USR_THUMB)
#define __SYSCALL_BODY_STR(id) "svc " __TOSTRING(id) "\nbx lr"
#else
#define __SYSCALL_BODY_STR(id) "swi " __TOSTRING(id) "\nbx lr"
#endif

#endif /* _ARM_SYSTRAP_H */
