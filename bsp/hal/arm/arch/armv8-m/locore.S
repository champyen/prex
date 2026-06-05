/*-
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
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
 * locore.S - low level platform support for armv8-m (Cortex-M33)
 */

#include <conf/config.h>
#include <machine/asm.h>
#include <machine/syspage.h>
#include <machine/memory.h>
#include <sys/errno.h>
#define LOCORE
#include <sys/param.h>
#include <context.h>
#include <trap.h>
#include <cpu.h>

    .section ".text","ax"
    .syntax unified
    .thumb

/*
 * Kernel start point
 */
    .align 10
ENTRY(kernel_start)
    /* 
     * Vector table for Cortex-M 
     * Note: This will be pointed to by VTOR.
     */
    .word   BOOTSTKTOP      /* 0: Initial SP */
    .word   reset_entry + 1 /* 1: Reset */
    .word   nmi_handler + 1
    .word   hardfault_handler + 1
    .word   memmanage_handler + 1
    .word   busfault_handler + 1
    .word   usagefault_handler + 1
    .word   0               /* Reserved */
    .word   0               /* Reserved */
    .word   0               /* Reserved */
    .word   0               /* Reserved */
    .word   syscall_entry + 1 /* SVCall */
    .word   debugmon_handler + 1
    .word   0               /* Reserved */
    .word   pendsv_entry + 1 /* PendSV */
    .word   systick_entry + 1 /* SysTick */

    /* External Interrupts (NVIC) start here */
    .rept 240
    .word  interrupt_entry + 1
    .endr

    .global bootinfo
bootinfo:       .word   BOOTINFO

ENTRY(reset_entry)
    cpsid   i               /* Disable interrupts */
    
    /* Set up stack pointer */
    ldr     sp, =BOOTSTKTOP
    
    /* Enforce 8-byte stack alignment on exceptions (SCB->CCR) */
    ldr     r0, =0xE000ED14
    ldr     r1, [r0]
    orr     r1, r1, #8
    str     r1, [r0]

    /* Clear kernel BSS */
    ldr     r1, =__bss
    ldr     r2, =__end
    mov     r0, #0
    cmp     r1, r2
    beq     2f
1:
    str     r0, [r1], #4
    cmp     r1, r2
    blo     1b
2:
    /* Jump to kernel main */
    ldr     r0, =main
    bx      r0

ENTRY(nmi_handler)
    b       nmi_handler

ENTRY(hardfault_handler)
    b       hardfault_handler

ENTRY(memmanage_handler)
    b       memmanage_handler

ENTRY(busfault_handler)
    b       busfault_handler

ENTRY(usagefault_handler)
    b       usagefault_handler

ENTRY(debugmon_handler)
    b       debugmon_handler

/*
 * System call entry (SVCall)
 */
ENTRY(syscall_entry)
    /* Check if exception was taken from user space (PSP) */
    tst     lr, #4                  /* EXC_RETURN bit 2 is 1 if PSP was active */
    bne     syscall_from_user

    /* ----------------------------------------------------
     * Case A: SVC called from Kernel Mode (MSP)
     * ---------------------------------------------------- */
    push    {r4-r11}
    push    {lr}                    /* Save EXC_RETURN */
    add     r1, sp, #4              /* r1 = regs (pointer to cpu_regs) */
    ldr     r2, [r1, #32 + 24]      /* Stacked PC */
    ldrb    r0, [r2, #-2]           /* Get SVC immediate number */
    bl      syscall_handler         /* Call C dispatcher */
    str     r0, [sp, #4 + 32]       /* Store return value in cpu_regs.r0 */
    pop     {lr}                    /* Restore EXC_RETURN */
    pop     {r4-r11}
    bx      lr                      /* Return to kernel */

    /* ----------------------------------------------------
     * Case B: SVC called from User Mode (PSP)
     * ---------------------------------------------------- */
syscall_from_user:
    mrs     r12, psp                /* r12 = User PSP pointer */

    /* Allocate space for struct cpu_regs on MSP (76 bytes) */
    sub     sp, sp, #76

    /* Save software-saved registers r4-r11 at MSP offset 0 */
    stmia   sp, {r4-r11}

    /* Copy hardware frame {r0-r3, r12, lr, pc, xPSR} from PSP to MSP offset 32 */
    ldmia   r12!, {r4-r11}          /* Pop user registers into temp regs */
    add     r0, sp, #32
    stmia   r0, {r4-r11}            /* Store into MSP frame */

    /* Restore clobbered r4-r11 from MSP offset 0 */
    ldmia   sp, {r4-r11}

    /* Save user SP (original PSP before exception = current r12) */
    str     r12, [sp, #64]          /* cpu_regs.sp = original PSP */

    /* Save EXC_RETURN to svc_lr */
    str     lr, [sp, #72]           /* cpu_regs.svc_lr = EXC_RETURN */

    /* Retrieve SVC number from copied stacked PC (offset 56 on MSP) */
    ldr     r1, [sp, #56]           /* Stacked PC */
    ldrb    r0, [r1, #-2]           /* SVC number (1st parameter) */

    /* Update PSP to reflect hardware frame removal */
    msr     psp, r12

    mov     r1, sp                  /* regs (2nd parameter) */
    bl      syscall_handler         /* Call C dispatcher */

    /* Store the system call return value (in r0) into the stacked r0 */
    str     r0, [sp, #32]           /* cpu_regs.r0 = return value */

    .global syscall_ret
syscall_ret:
    /* Restore EXC_RETURN */
    ldr     lr, [sp, #72]           /* Restore EXC_RETURN */

    /* ----------------------------------------------------
     * Return to User Mode (PSP)
     * ---------------------------------------------------- */
    /* Read current PSP and allocate space for hardware frame */
    mrs     r0, psp
    sub     r0, r0, #32
    msr     psp, r0                 /* Update PSP first */

    /* Copy hardware frame from MSP offset 32 to user stack */
    add     r1, sp, #32
    ldmia   r1, {r4-r11}            /* Load saved hardware registers from MSP */
    stmia   r0, {r4-r11}            /* Store onto user stack (PSP) */

    /* Restore user r4-r11 from MSP offset 0 */
    ldmia   sp, {r4-r11}

    /* Deallocate cpu_regs on MSP */
    add     sp, sp, #76

    bx      lr                      /* Return to user via EXC_RETURN */

/*
 * PendSV entry (Context Switch)
 */
ENTRY(pendsv_entry)
    /* For now, just return. Prex+ uses cpu_switch for explicit switches. */
    bx      lr

/*
 * SysTick / Interrupt entry
 */
ENTRY(systick_entry)
ENTRY(interrupt_entry)
    /* 
     * Prex+ expects interrupt_handler() to be called.
     * It will use IPSR to determine the vector.
     */
    push    {r4-r11}
    bl      interrupt_handler
    pop     {r4-r11}
    bx      lr

/*
 * void sploff(void);
 */
ENTRY(sploff)
    cpsid   i
    bx      lr

/*
 * void splon(void);
 */
ENTRY(splon)
    cpsie   i
    bx      lr

/*
 * Switch register context.
 * void cpu_switch(kern_regs *prev, kern_regs *next)
 */
ENTRY(cpu_switch)
    stmia   r0, {r4-r11}            /* Save r4-r11 */
    str     sp, [r0, #32]           /* Save sp */
    str     lr, [r0, #36]           /* Save lr */

    ldmia   r1, {r4-r11}            /* Restore r4-r11 */
    ldr     sp, [r1, #32]           /* Restore sp */
    ldr     pc, [r1, #36]           /* Restore pc */

/*
 * Entry point for kernel thread
 */
ENTRY(kernel_thread_entry)
    mov     r0, r5                  /* Set argument */
    bx      r4                      /* Jump to kernel thread */
1:
    b       1b

ENTRY(vector_copy)
    /* Cortex-M uses VTOR, copying may be needed if in RAM */
    bx      lr

/*
 * Copy functions
 */
    .global known_fault1
    .global known_fault2
    .global known_fault3
ENTRY(copyin)
known_fault1:
    push    {r4, lr}
1:  subs    r2, r2, #1
    blo     2f
    ldrb    r3, [r0], #1
    strb    r3, [r1], #1
    b       1b
2:  movs    r0, #0
    pop     {r4, pc}

ENTRY(copyout)
known_fault2:
    push    {r4, lr}
1:  subs    r2, r2, #1
    blo     2f
    ldrb    r3, [r0], #1
    strb    r3, [r1], #1
    b       1b
2:  movs    r0, #0
    pop     {r4, pc}

ENTRY(copyinstr)
known_fault3:
    push    {r4, lr}
1:  subs    r2, r2, #1
    blo     3f
    ldrb    r3, [r0], #1
    strb    r3, [r1], #1
    cmp     r3, #0
    beq     2f
    b       1b
2:  movs    r0, #0
    pop     {r4, pc}
3:  movs    r0, #(ENAMETOOLONG)
    pop     {r4, pc}

ENTRY(copy_fault)
    movs    r0, #(EFAULT)
    pop     {r4, pc}

    .end
