/*
 * setjmp/longjmp (RISC-V)
 */

#include <conf/config.h>
#include <machine/asm.h>
#include <machine/setjmp.h>

ENTRY(setjmp)
    /* Save callee-saved registers: s0-s11, ra, sp */
    sw ra, 0(a0)
    sw sp, 4(a0)
    sw s0, 8(a0)
    sw s1, 12(a0)
    sw s2, 16(a0)
    sw s3, 20(a0)
    sw s4, 24(a0)
    sw s5, 28(a0)
    sw s6, 32(a0)
    sw s7, 36(a0)
    sw s8, 40(a0)
    sw s9, 44(a0)
    sw s10, 48(a0)
    sw s11, 52(a0)
    
    li a0, 0
    ret

ENTRY(longjmp)
    /* Restore callee-saved registers: s0-s11, ra, sp */
    lw ra, 0(a0)
    lw sp, 4(a0)
    lw s0, 8(a0)
    lw s1, 12(a0)
    lw s2, 16(a0)
    lw s3, 20(a0)
    lw s4, 24(a0)
    lw s5, 28(a0)
    lw s6, 32(a0)
    lw s7, 36(a0)
    lw s8, 40(a0)
    lw s9, 44(a0)
    lw s10, 48(a0)
    lw s11, 52(a0)

    /* If val is 0, return 1 */
    mv a0, a1
    bnez a0, 1f
    li a0, 1
1:
    ret

.section .note.GNU-stack,"",%progbits
