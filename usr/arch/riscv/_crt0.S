/*
 * crt0.S - C startup routine (RISC-V)
 */

#include <conf/config.h>

        .text
        .global _start
        .type _start, @function
_start:
        lw      a0, 0(sp)       /* a0 = argc */
        addi    a1, sp, 4       /* a1 = argv */
        
        /* envp = argv + (argc + 1) * 4 */
        addi    t0, a0, 1
        slli    t0, t0, 2
        add     a2, a1, t0      /* a2 = envp */

        li      s0, 0           /* Clear frame pointer */
        
        /* Align stack to 16 bytes for RISC-V ABI */
        andi    sp, sp, -16
        
        call    __prex_main
        
        /* If __prex_main returns, exit */
        mv      a0, zero
        call    exit

.section .note.GNU-stack,"",%progbits
