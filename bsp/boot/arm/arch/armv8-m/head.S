/*-
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
 * All rights reserved.
 */

#include <conf/config.h>
#include <machine/memory.h>
#include <machine/syspage.h>

#define ENTRY(x) .global x; .align 2; x##:

    .section ".start","ax"
    .syntax unified
    .thumb

ENTRY(boot_entry)
    .word   BOOTSTKTOP
    .word   start_vector + 1
    .word   nmi_handler + 1
    .word   hardfault_handler + 1

    .thumb_func
start_vector:
    cpsid   i
    ldr     sp, =BOOTSTKTOP
    ldr     r0, =main
    bx      r0

    .thumb_func
nmi_handler:
    b       nmi_handler

    .thumb_func
hardfault_handler:
    b       hardfault_handler

    .section .tail,"ax"
dummy:
    .byte   0xff

.end
