/*
 * head.S - RISC-V bootloader entry with M-to-S transition and minimal SBI
 */

#include <conf/config.h>
#include <machine/syspage.h>

#define MSTATUS_MPP_S (1 << 11)

.section ".entry", "ax"
.global _entry
_entry:
    j _start

.section ".start", "ax"
.global _start
_start:
    /* 1. Disable interrupts */
    csrw mie, zero
    
    /* 2. Setup M-mode trap vector (All cores) */
    la t0, m_trap_entry
    csrw mtvec, t0

    /* 4. Initialize mscratch */
    li t0, 0x80000800
    csrr t1, mhartid
    slli t1, t1, 5
    add t0, t0, t1
    csrw mscratch, t0

    /* 5. Branch based on hartid */
    csrr t0, mhartid
    bnez t0, ap_wait_loop

    /* --- BSP (Hart 0) Path --- */

    /* 6. Delegate interrupts and exceptions to S-mode */
    li t0, 0xbfff
    csrw mideleg, t0
    li t0, 0xfdff
    csrw medeleg, t0

    /* 7. Configure PMP */
    li t0, 0xffffffff
    csrw pmpaddr0, t0
    li t0, 0x1f
    csrw pmpcfg0, t0

    /* 8. Enable counters */
    li t0, 0xffffffff
    csrw mcounteren, t0

    /* 9. Switch to S-mode */
    la t0, s_mode_entry
    csrw mepc, t0
    li t0, MSTATUS_MPP_S | (1 << 3)
    csrw mstatus, t0
    li a0, 0
    li a1, 0
    mret

ap_wait_loop:
1:
    /* Check start flag in System Page: 0x80000900 + hartid * 4 */
    li t0, 0x80000900
    csrr t1, mhartid
    slli t2, t1, 2
    add t0, t0, t2
    lw t3, 0(t0)
    beqz t3, 1b
    
    /* Clear flag */
    sw zero, 0(t0)

    /* Get entry point */
    addi t0, t0, 0x40
    lw t0, 0(t0)
    
    /* Transition to S-mode */
    csrw mepc, t0
    li t1, MSTATUS_MPP_S | (1 << 3)
    csrw mstatus, t1
    
    csrr a0, mhartid
    li a1, 0
    mret

/* Minimal SBI */
.align 4
m_trap_entry:
    csrrw t0, mscratch, t0
    sw t1, 4(t0)
    sw t2, 8(t0)
    sw a0, 12(t0)
    sw a1, 16(t0)
    sw a2, 20(t0)
    sw ra, 24(t0)
    csrr t1, mscratch
    sw t1, 0(t0)
    csrw mscratch, t0
    
    csrr t2, mcause
    li t1, 9 /* S-ecall */
    beq t2, t1, handle_s_ecall
    
    /* MSI */
    li t1, 3
    beq t2, t1, 1f
    li t1, 0x80000003
    beq t2, t1, 1f
    
    /* Timer */
    li t1, 0x80000007
    beq t2, t1, handle_m_timer

    j m_trap_exit

1:  /* Handle MSI */
    li t1, 0x02000000
    csrr t0, mhartid
    slli t0, t0, 2
    add t1, t1, t0
    sw zero, 0(t1)
    j m_trap_exit

handle_s_ecall:
    li t1, 0
    beq a7, t1, handle_set_timer
    li t1, 0x48534D
    beq a7, t1, handle_hsm
    li a0, -2
    j 1f

handle_set_timer:
    li t1, 0x02004000
    csrr t0, mhartid
    slli t0, t0, 3
    add t1, t1, t0
    li t0, -1
    sw t0, 0(t1)
    sw a1, 4(t1)
    sw a0, 0(t1)
    li t0, 0x20
    csrc mip, t0
    li t0, 0x80
    csrs mie, t0
    li a0, 0
    j 1f

handle_hsm:
    li t1, 0
    bne a6, t1, 2f
    li t1, 0x80000900
    slli t2, a0, 2
    add t0, t1, t2
    li t2, 1
    sw t2, 0(t0)
    addi t0, t0, 0x40
    sw a1, 0(t0)
    li t1, 0x02000000
    slli t2, a0, 2
    add t1, t1, t2
    li t2, 1
    sw t2, 0(t1)
    li a0, 0
    j 1f
2:  li a0, -2
    j 1f

1:  csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    j m_trap_exit

handle_m_timer:
    li t1, 0x80
    csrc mie, t1
    li t1, 0x20
    csrs mip, t1
    j m_trap_exit

m_trap_exit:
    csrr t0, mscratch
    lw t1, 4(t0)
    lw t2, 8(t0)
    lw a0, 12(t0)
    lw a1, 16(t0)
    lw a2, 20(t0)
    lw ra, 24(t0)
    lw t0, 0(t0)
    mret

s_mode_entry:
    la sp, BOOTSTKTOP
    /* hartid is in a0 */
    mv t0, a0
    bnez t0, 3f
    la t0, __bss
    la t1, __end
    bgeu t0, t1, 2f
1:  sw zero, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, 1b
2:  li t0, 0x80000900
    li t1, 32
1:  sw zero, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, 1b
3:  call main

loop:
    wfi
    j loop

.section .tail, "ax"
dummy:
    .byte 0xff

.section .note.GNU-stack,"",%progbits
