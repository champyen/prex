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
    /* 
     * In Cortex-M, hardware stacks r0-r3, r12, lr, pc, xPSR.
     * We need to build the rest of struct cpu_regs.
     */
    push    {r4-r11}                /* Save remaining registers */
    mov     r0, sp                  /* r0: Pointer to struct cpu_regs */
    
    /* 
     * Get SVC number from stacked PC.
     * Hardware stacked frame starts at SP + (8 * 4).
     * PC is at offset 24 from that.
     */
    ldr     r1, [sp, #32 + 24]      /* Stacked PC */
    ldrb    r4, [r1, #-2]           /* SVC number (immediate) */
    
    /* Call syscall_handler(int num, struct cpu_regs *regs) */
    mov     r0, r4                  /* num */
    mov     r1, sp                  /* regs */
    bl      syscall_handler

    /* Restore and return */
    .global syscall_ret
syscall_ret:
    pop     {r4-r11}
    bx      lr

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
