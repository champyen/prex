/*
 * head.S - RISC-V bootloader entry with M-to-S transition and minimal SBI
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
    
    /* 2. Setup M-mode trap vector */
    la t0, m_trap_entry
    csrw mtvec, t0

    /* 3. Delegate interrupts and exceptions to S-mode */
    li t0, 0xbfff
    csrw mideleg, t0
    li t0, 0xfdff /* Do not delegate S-mode ecall (bit 9) */
    csrw medeleg, t0

    /* 4. Configure PMP to allow S/U mode access to all memory */
    li t0, 0xffffffff
    csrw pmpaddr0, t0
    li t0, 0x1f /* NAPOT (3), R/W/X (7) -> 3 << 3 | 7 = 0x1f */
    csrw pmpcfg0, t0

    /* 5. Enable counters for S-mode */
    li t0, 0xffffffff
    csrw mcounteren, t0

    /* 6. Set the return address for mret to our S-mode entry point */
    la t0, s_mode_entry
    csrw mepc, t0

    /* 7. Set the next privilege mode in mstatus to S-mode and enable M-mode interrupts */
    li t0, MSTATUS_MPP_S | (1 << 3) /* MPP=S, MIE=1 */
    csrw mstatus, t0

    /* 8. Initialize mscratch with a pointer to a save area */
    la t0, m_save_area
    csrw mscratch, t0

    /* 9. Switch to S-mode */
    mret

/* Minimal M-mode Trap Handler (SBI Implementation) */
.align 4
m_trap_entry:
    /* Save t0, t1, t2 to m_save_area */
    csrrw t0, mscratch, t0
    sw t1, 4(t0)
    sw t2, 8(t0)
    csrr t1, mscratch
    sw t1, 0(t0)
    csrw mscratch, t0
    
    csrr t2, mcause
    li t1, 9 /* S-mode ecall */
    beq t2, t1, handle_s_ecall
    
    li t1, 0x80000007 /* M-mode timer interrupt */
    beq t2, t1, handle_m_timer

    /* Unknown trap: hang */
    j loop

handle_s_ecall:
    /* a7: extension, a0: arg0, a1: arg1 */
    li t1, 0 /* SBI_EXT_0_1_SET_TIMER */
    bne a7, t1, 1f

    /* Write mtimecmp */
    li t1, 0x02004000 /* CLINT_MTIMECMP */
    li t0, -1
    sw t0, 0(t1) /* mtimecmp lo = -1 */
    sw a1, 4(t1) /* mtimecmp hi */
    sw a0, 0(t1) /* mtimecmp lo */
    
    /* Clear STIP in mip */
    li t0, 0x20
    csrc mip, t0

    /* Enable MTIE in mie */
    li t0, 0x80
    csrs mie, t0
    j 1f

1:  /* Return from ecall */
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    j m_trap_exit

handle_m_timer:
    /* Disable MTIE */
    li t1, 0x80
    csrc mie, t1
    /* Set STIP in mip */
    li t1, 0x20
    csrs mip, t1
    j m_trap_exit

m_trap_exit:
    /* Restore registers */
    la t0, m_save_area
    lw t1, 4(t0)
    lw t2, 8(t0)
    lw t0, 0(t0)
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

.section ".bss"
.align 4
m_save_area:
    .long 0 /* t0 */
    .long 0 /* t1 */
    .long 0 /* t2 */

.section .tail, "ax"
dummy:
    .byte 0xff

.section .note.GNU-stack,"",%progbits
