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

    /* Copy .data from Flash to SRAM */
    ldr     r0, =_data_flash_start
    ldr     r1, =_data_start
    ldr     r2, =_data_end
copy_data:
    cmp     r1, r2
    bhs     zero_bss
    ldr     r3, [r0], #4
    str     r3, [r1], #4
    b       copy_data

zero_bss:
    /* Zero .bss in SRAM */
    ldr     r1, =_bss_start
    ldr     r2, =_bss_end
    movs    r3, #0
zero_loop:
    cmp     r1, r2
    bhs     call_main
    str     r3, [r1], #4
    b       zero_loop

call_main:
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
