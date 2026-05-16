/*
 * head.S - RISC-V bootloader entry with M-to-S transition
 */

#include <conf/config.h>
#include <machine/syspage.h>

#define MSTATUS_MPP_S (1 << 11)

.section ".start", "ax"
.global _start
_start:
    /* Only CPU 0 continues */
    csrr t0, mhartid
    bnez t0, loop

    /* 1. Disable interrupts */
    csrw mie, zero
    
    /* 2. Delegate all interrupts and exceptions to S-mode */
    li t0, 0xbfff
    csrw mideleg, t0
    li t0, 0xffff
    csrw medeleg, t0

    /* 3. Configure PMP to allow S/U mode access to all memory */
    li t0, 0xffffffff
    csrw pmpaddr0, t0
    li t0, 0x0f /* TOR (1), R/W/X (7) */
    csrw pmpcfg0, t0

    /* 4. Set the return address for mret to our S-mode entry point */
    la t0, s_mode_entry
    csrw mepc, t0

    /* 5. Set the next privilege mode in mstatus to S-mode */
    li t0, MSTATUS_MPP_S
    csrw mstatus, t0

    /* 6. Switch to S-mode */
    mret

s_mode_entry:
    /* Setup stack */
    la sp, BOOTSTKTOP
    
    /* Clear BSS */
    la t0, __bss
    la t1, __end
    bgeu t0, t1, 2f
1:
    sw zero, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, 1b
2:
    /* Jump to C main */
    call main

loop:
    wfi
    j loop

.section .tail, "ax"
dummy:
    .byte 0xff

.section .note.GNU-stack,"",%progbits
