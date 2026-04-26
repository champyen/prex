/*-
 * Copyright (c) 2005, Kohsuke Ohtani
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
 * crt0.S - C startup routine
 */

/**
 * Stack layout:
 *      argc            argument counter (integer)
 *      argv[0]         program name (pointer)
 *      argv[1...N]     program args (pointers)
 *      argv[argc-1]    end of args (integer)
 *      NULL
 *      env[0...N]      environment variables (pointers)
 *      NULL
 */

/*
 * Entry point called by kernel first
 */
#include <conf/config.h>

#ifdef CONFIG_USR_THUMB
        .syntax unified
        .thumb
        .thumb_func
#endif
        .text
        .global _start
        .type _start, %function
_start:
        ldr     r0, [sp], #4            /* Get argc */
        mov     r1, sp                  /* Get argv */
        add     r2, r1, r0, lsl #2      /* Get envp */ 
        mov     fp, #0                  /* Clear frame pointer */
#ifdef CONFIG_USR_THUMB
        mov     r3, sp
        bic     r3, r3, #7
        mov     sp, r3
#else
        bic     sp, sp, #7              /* Align stack to 8 bytes for AAPCS */
#endif
        bl      __prex_main


.section .note.GNU-stack,"",%progbits
