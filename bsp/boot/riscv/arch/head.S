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
    /* 1. Disable interrupts but enable MSIE (bit 3) for IPI */
    li t0, 8
    csrw mie, t0
    
    /* 2. Setup M-mode trap vector (All cores) */
    la t0, m_trap_entry
    csrw mtvec, t0

    /* 4. Initialize mscratch */
    li t0, 0x80000800
    csrr t1, mhartid
    slli t1, t1, 5
    add t0, t0, t1
    csrw mscratch, t0

    /* 6. Delegate interrupts and exceptions to S-mode if configured */
#ifdef CONFIG_SMODE
    li t0, 0xbfff
    csrw mideleg, t0
    li t0, 0xfdff
    csrw medeleg, t0
#endif

    /* 7. Configure PMP */
    li t0, 0xffffffff
    csrw pmpaddr0, t0
    li t0, 0x1f
    csrw pmpcfg0, t0

    /* 8. Enable counters */
    li t0, 0xffffffff
    csrw mcounteren, t0

    /* 5. Branch based on hartid */
    csrr t0, mhartid
    bnez t0, ap_wait_loop

    /* --- BSP (Hart 0) Path --- */

    /* 9. Switch to S-mode (or stay in M-mode) */
    li a0, 0
    li a1, 0
#ifdef CONFIG_SMODE
    la t0, s_mode_entry
    csrw mepc, t0
    li t0, MSTATUS_MPP_S
    csrw mstatus, t0
    mret
#else
    j s_mode_entry
#endif

ap_wait_loop:
    /* Clear our own MSIP to ensure no stale interrupts */
    li t0, 0x02000000
    csrr t1, mhartid
    slli t1, t1, 2
    add t0, t0, t1
    sw zero, 0(t0)
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
    
    /* Ensure flag is visible before reading entry point */
    fence r, r

    /* Get entry point */
    addi t0, t0, 0x40
    lw t0, 0(t0)
    
    /* Clear satp explicitly to ensure physical addressing */
    csrw satp, zero

    /* Transition to S-mode (or stay in M-mode) */
    csrr a0, mhartid
    li a1, 0
#ifdef CONFIG_SMODE
    csrw mepc, t0
    li t1, MSTATUS_MPP_S
    csrw mstatus, t1
    mret
#else
    jr t0
#endif

/* Minimal SBI */
.align 4
m_trap_entry:
    csrrw t0, mscratch, t0
    bnez t0, 2f
    
    /* If mscratch was 0, print 'X' and hang */
    li t1, CONFIG_NS16550_PHY_BASE
    li t2, 'X'
    sb t2, 0(t1)
1:  j 1b

2:
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

    /* Set S-software interrupt pending (SSIP = bit 1) in mip */
    li t0, 2
    csrs mip, t0

    j m_trap_exit

handle_s_ecall:
    li t1, 0
    beq a7, t1, handle_set_timer
    li t1, 0x48534D
    beq a7, t1, handle_hsm
    li t1, 0x735049     /* sPI (IPI) Extension */
    beq a7, t1, handle_s_ipi
    li a0, -2
    j 1f

handle_s_ipi:
    /* a0 = hart_mask, a1 = hart_mask_base */
    li t1, 0x02000000   /* CLINT MSIP base */
    li t2, 0            /* hart index */
3:
    srl t5, a0, t2      /* shift mask right by t2 */
    andi t5, t5, 1      /* get lowest bit */
    beqz t5, 4f         /* if 0, skip */
    
    /* Trigger MSI on hart (t2 + a1) */
    add t5, t2, a1      /* t5 = hartid */
    slli t5, t5, 2      /* t5 = hartid * 4 */
    add t5, t1, t5      /* t5 = MSIP address */
    li t6, 1
    sw t6, 0(t5)        /* Trigger MSI! */
4:
    addi t2, t2, 1      /* next hart */
    li t5, CONFIG_SMP_NCPUS
    blt t2, t5, 3b      /* loop if t2 < NCPUS */
    
    li a0, 0            /* return SBI_SUCCESS */
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
    
    /* 1. Write entry address first */
    addi t3, t0, 0x40
    sw a1, 0(t3)
    
    /* 2. Memory barrier to ensure entry address is written before flag */
    fence w, w
    
    /* 3. Write start flag last */
    li t2, 1
    sw t2, 0(t0)
    
    li a0, 0
    j 1f
2:  li a0, -2
    j 1f

1:  csrr t0, mscratch
    sw a0, 12(t0)
    csrr t1, mepc
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

m_print_hex:
    li t3, CONFIG_NS16550_PHY_BASE
    li t4, 8
1:
    srli t5, a0, 28
    andi t5, t5, 0xf
    li t6, 10
    blt t5, t6, 2f
    addi t5, t5, 'a' - 10
    j 3f
2:  addi t5, t5, '0'
3:
4:  lb t6, 5(t3)
    andi t6, t6, 0x20
    beqz t6, 4b
    sb t5, 0(t3)
    slli a0, a0, 4
    addi t4, t4, -1
    bnez t4, 1b
    ret

loop:
    wfi
    j loop

.section .tail, "ax"
dummy:
    .byte 0xff

.section .note.GNU-stack,"",%progbits
