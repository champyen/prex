/*
 * locore.S - low level platform support for RISC-V (Supervisor Mode)
 */

#include <conf/config.h>
#include <machine/asm.h>
#include <machine/syspage.h>
#include <machine/memory.h>
#include <sys/errno.h>
#include <context.h>
#include <trap.h>
#include <cpu.h>

	.section ".text","ax"

/*
 * Kernel start point
 */
ENTRY(kernel_start)
    fence.i
	j	reset_entry

/*
 * Exception vector
 */
	.align 4
vector_entry:
    /* Allocate space for struct cpu_regs (140 bytes) */
    addi sp, sp, -140
    
    /* Save general purpose registers */
    sw ra, 0(sp)
    sw gp, 8(sp)
    sw tp, 12(sp)
    sw t0, 16(sp)
    sw t1, 20(sp)
    sw t2, 24(sp)
    sw s0, 28(sp)
    sw s1, 32(sp)
    sw a0, 36(sp)
    sw a1, 40(sp)
    sw a2, 44(sp)
    sw a3, 48(sp)
    sw a4, 52(sp)
    sw a5, 56(sp)
    sw a6, 60(sp)
    sw a7, 64(sp)
    sw s2, 68(sp)
    sw s3, 72(sp)
    sw s4, 76(sp)
    sw s5, 80(sp)
    sw s6, 84(sp)
    sw s7, 88(sp)
    sw s8, 92(sp)
    sw s9, 96(sp)
    sw s10, 100(sp)
    sw s11, 104(sp)
    sw t3, 108(sp)
    sw t4, 112(sp)
    sw t5, 116(sp)
    sw t6, 120(sp)

    /* Original SP was sp + 140 */
    addi t0, sp, 140
    sw t0, 4(sp)

    /* Save CSRs (Supervisor Mode) */
    csrr t0, sepc
    sw t0, 132(sp)
    csrr t0, sstatus
    sw t0, 132(sp)
    csrr t0, scause
    sw t0, 132(sp)
    csrr t0, stval
    sw t0, 132(sp)

    /* Call C trap handler */
    mv a0, sp
    call trap_handler

ENTRY(syscall_ret)
    /* fence.i to ensure coherence */
    fence.i

    /* Restore CSRs (Supervisor Mode) */
    lw t0, 132(sp)
    csrw sepc, t0
    lw t0, 132(sp)
    csrw sstatus, t0
    
    /* Restore general purpose registers */
    lw ra, 0(sp)
    lw gp, 8(sp)
    lw tp, 12(sp)
    lw t0, 16(sp)
    lw t1, 20(sp)
    lw t2, 24(sp)
    lw s0, 28(sp)
    lw s1, 32(sp)
    lw a0, 36(sp)
    lw a1, 40(sp)
    lw a2, 44(sp)
    lw a3, 48(sp)
    lw a4, 52(sp)
    lw a5, 56(sp)
    lw a6, 60(sp)
    lw a7, 64(sp)
    lw s2, 68(sp)
    lw s3, 72(sp)
    lw s4, 76(sp)
    lw s5, 80(sp)
    lw s6, 84(sp)
    lw s7, 88(sp)
    lw s8, 92(sp)
    lw s9, 96(sp)
    lw s10, 100(sp)
    lw s11, 104(sp)
    lw t3, 108(sp)
    lw t4, 112(sp)
    lw t5, 116(sp)
    lw t6, 120(sp)
    
    /* Restore SP */
    lw sp, 4(sp)

    sret

	.global bootinfo
bootinfo:		.word	BOOTINFO
boot_stack:		.word	BOOTSTKTOP
int_stack:		.word	INTSTKTOP - 0x100
irq_nesting:	 	.word	irq_nesting_value
init_done:	 	.word	init_done_value

ENTRY(reset_entry)
    /* Disable interrupts (SIE bit) */
    csrci sstatus, 2 /* S-mode SIE is bit 1 (mask 2) */
    
    /* Setup Global Pointer */
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    /* Setup stack */
    la sp, BOOTSTKTOP
    
    /* Setup trap vector (Supervisor Mode) */
    la t0, vector_entry
    csrw stvec, t0
    
    /* Jump to kernel main */
    /* Note: BSS was cleared by bootloader */
    call main

/*
 * Context switch
 */
ENTRY(cpu_switch)
    /* Save previous context */
    sw s0, 0(a0)
    sw s1, 4(a0)
    sw s2, 8(a0)
    sw s3, 12(a0)
    sw s4, 16(a0)
    sw s5, 20(a0)
    sw s6, 24(a0)
    sw s7, 28(a0)
    sw s8, 32(a0)
    sw s9, 36(a0)
    sw s10, 40(a0)
    sw s11, 44(a0)
    sw sp, 48(a0)
    sw ra, 52(a0)

    /* Restore next context */
    lw s0, 0(a1)
    lw s1, 4(a1)
    lw s2, 8(a1)
    lw s3, 12(a1)
    lw s4, 16(a1)
    lw s5, 20(a1)
    lw s6, 24(a1)
    lw s7, 28(a1)
    lw s8, 32(a1)
    lw s9, 36(a1)
    lw s10, 40(a1)
    lw s11, 44(a1)
    lw sp, 48(a1)
    lw ra, 52(a1)
    ret

ENTRY(kernel_thread_entry)
    mv a0, s1
    jr s0

/*
 * SPL Level management (Supervisor Mode)
 */
ENTRY(get_status)
    csrr a0, sstatus
    ret

ENTRY(sploff)
    csrci sstatus, 2 /* Disable SIE */
    ret

ENTRY(splon)
    csrsi sstatus, 2 /* Enable SIE */
    ret

ENTRY(copyin)
    li t0, 0
    beqz a0, 3f     /* Check NULL source */
    beqz a1, 3f     /* Check NULL dest */
    beqz a2, 2f
1:
    lb t1, 0(a0)
    sb t1, 0(a1)
    addi a0, a0, 1
    addi a1, a1, 1
    addi a2, a2, -1
    bnez a2, 1b
2:
    mv a0, t0
    ret
3:
    li a0, 14 /* EFAULT */
    ret

ENTRY(copyout)
    li t0, 0
    beqz a0, 3f     /* Check NULL source */
    beqz a1, 3f     /* Check NULL dest */
    beqz a2, 2f
1:
    lb t1, 0(a0)
    sb t1, 0(a1)
    addi a0, a0, 1
    addi a1, a1, 1
    addi a2, a2, -1
    bnez a2, 1b
2:
    mv a0, t0
    ret
3:
    li a0, 14 /* EFAULT */
    ret

ENTRY(copyinstr)
    li t0, 0
    beqz a0, 4f
    beqz a1, 4f
    beqz a2, 3f
1:
    lb t1, 0(a0)
    sb t1, 0(a1)
    beqz t1, 2f
    addi a0, a0, 1
    addi a1, a1, 1
    addi a2, a2, -1
    bnez a2, 1b
3:
    li t0, 36 /* ENAMETOOLONG */
2:
    mv a0, t0
    ret
4:
    li a0, 14 /* EFAULT */
    ret

	.section ".bss"
irq_nesting_value:
	.long	0
init_done_value:
	.long	0

	.end

.section .note.GNU-stack,\"\",%progbits
