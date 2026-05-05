/*-
 * Copyright (c) 2005-2007, Kohsuke Ohtani
 * Copyright (c) 2010, Richard Pandion
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
 * locore.S - low level platform support for ARMv7-A
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
	.syntax unified
	.arm

/*
 * Kernel start point
 */
ENTRY(kernel_start)
	b	reset_entry		/* Relative jump */
vector_start:
	/*
	 * Exception vector
	 *
	 * This table will be copied to an appropriate location.
	 * (the location is platform specific.)
	 */
	ldr	pc, reset_target	/* 0x00 mode: svc */
	ldr	pc, undefined_target	/* 0x04 mode: ? */
	ldr	pc, swi_target		/* 0x08 mode: svc */
	ldr	pc, prefetch_target	/* 0x0c mode: abort */
	ldr	pc, abort_target	/* 0x10 mode: abort */
	ldr	pc, unused_target	/* 0x14 unused */
	ldr	pc, irq_target		/* 0x18 mode: irq */
	ldr	pc, fiq_target		/* 0x1c mode: fiq */

reset_target:		.word	reset_entry
undefined_target:	.word	undefined_entry
swi_target:		.word	syscall_entry
prefetch_target:	.word	prefetch_entry
abort_target:		.word	abort_entry
unused_target:		.word	unused_entry
irq_target:		.word	interrupt_entry
fiq_target:		.word	fiq_entry

vector_end:

	.global bootinfo
bootinfo:		.word	BOOTINFO
boot_stack:		.word	BOOTSTKTOP
int_stack:		.word	INTSTKTOP - 0x100
irq_mode_stack:		.word	INTSTKTOP
sys_mode_stack:		.word	SYSSTKTOP
abort_mode_stack:	.word	ABTSTKTOP
irq_nesting:	 	.word	irq_nesting_value
curspl:	 		.word	curspl_value
init_done:	 	.word	init_done_value
#ifdef CONFIG_MMU
reload_pc_target:	.word	reload_pc
#endif

ENTRY(reset_entry)
#ifdef CONFIG_SMP
	/*
	 * Check CPU ID.
	 * APs (CPU ID != 0) jump to ap_entry.
	 */
	mrc	p15, 0, r0, c0, c0, 5
	and	r0, r0, #0xff
	cmp	r0, #0
	bne	ap_entry
#endif
	/*
	 * Setup stack pointer for each processor mode
	 */
	mov	r0, #(PSR_IRQ_MODE|PSR_FIQ_DIS|PSR_IRQ_DIS)
	msr	cpsr, r0
	ldr	sp, irq_mode_stack	/* Set IRQ mode stack */

	mov	r0, #(PSR_UND_MODE|PSR_FIQ_DIS|PSR_IRQ_DIS)
	msr	cpsr, r0
	ldr	sp, abort_mode_stack	/* Set Undefined mode stack */

	mov	r0, #(PSR_ABT_MODE|PSR_FIQ_DIS|PSR_IRQ_DIS)
	msr	cpsr, r0
	ldr	sp, abort_mode_stack	/* Set Abort mode stack */

	mov	r0, #(PSR_SYS_MODE|PSR_FIQ_DIS|PSR_IRQ_DIS)
	msr	cpsr, r0
	ldr	sp, sys_mode_stack	/* Set SYS mode stack */

	mov	r0, #(PSR_SVC_MODE|PSR_FIQ_DIS|PSR_IRQ_DIS)
	msr	cpsr, r0
	ldr	sp, boot_stack		/* Set SVC mode stack */

	/* It is svc mode now. */

#ifdef CONFIG_CACHE
	/*
	 * Setup control register with default values
	 */
	ldr	r1, =(CTL_AFE | CTL_TRE | CTL_ICACHE | CTL_BPRD | CTL_CACHE | CTL_MMU)
	mrc	p15, 0, r0, c1, c0, 0
	bic	r0, r0, r1
	mcr	p15, 0, r0, c1, c0, 0
	/*
	 * Disable L2 cache and set cache level to 0
	 */
	mrc p15, 0, r0, c1, c0, 1		/* Read auxiliary control register */
	ldr r1,=(AUXCTL_L2EN)
	bic r0, r0, r1					/* Disable L2 cache */
	mcr p15, 0, r0, c1, c0, 1 		/* Load auxiliary control register... */
	mrc	p15, 0, r0, c1, c0, 1		/* ...and read it back */
	ldr	r0, =0x0
	mcr	p15, 2, r0, c0, c0, 0		/* set cache level to 0 in CSSR */
#endif

#ifdef CONFIG_MMU
	/*
	 * Initialize boot page directory
	 */
	ldr	r1, =BOOT_PGD_PHYS		/* Page directory base address */
	add	r2, r1, #0x4000			/* 16k in size */
	ldr	r0, =0x0
1:
	str	r0, [r1], #4
	teq	r1, r2
	bne	1b

	/*
	 * Initialize boot page table entries for 4 sections of 1 MB each
	 * (to map first 4 MB of RAM - see below)
	 */
	ldr	r1, =BOOT_PTE0_PHYS		/* Page table entry base address */
	add	r2, r1, #0x1000			/* 4K in size (1k per section x 4 sections) */
	ldr	r0, =(RAMBASE | 0x1a)	/* We map from RAMBASE */
1:
	str	r0, [r1], #4
	add	r0, r0, #0x1000
	teq	r1, r2
	bne	1b

	/* Initialize BOOT_PTE1_PHYS (used for premap) */
	ldr	r1, =BOOT_PTE1_PHYS
	add	r2, r1, #0x1000
	ldr	r0, =0x0
1:
	str	r0, [r1], #4
	teq	r1, r2
	bne	1b

	/*
	 * Map first 4 MB of RAM on KERNBASE virtual address
	 * Also map 1:1. This is required to enable paging
	 */
	ldr	r1, =(BOOT_PGD_PHYS + (KERNBASE >> 18))
	ldr	r2, =(BOOT_PGD_PHYS + (RAMBASE  >> 18))
	ldr	r0, =(BOOT_PTE0_PHYS | 0x01)
	str	r0, [r1], #4
	str	r0, [r2], #4
	add	r0, r0, #0x400
	str	r0, [r1], #4
	str	r0, [r2], #4
	add	r0, r0, #0x400
	str	r0, [r1], #4
	str	r0, [r2], #4
	add	r0, r0, #0x400
	str	r0, [r1]
	str	r0, [r2], #4

	/* Map BOOT_PTE1_PHYS at UART_BASE (0xC9000000) */
/*
	ldr	r1, =(BOOT_PGD_PHYS + (0xC9000000 >> 18))
	ldr	r0, =(BOOT_PTE1_PHYS | 0x01)
	str	r0, [r1]
*/
	dsb
	ldr	r1, =BOOT_PGD_PHYS
	mcr	p15, 0, r1, c2, c0, 0		/* Load page table pointer */
	mcr	p15, 0, r0, c8, c7, 0		/* Flush I,D TLBs */
	dsb
	isb
	ldr	r0, =0x55555555				/* AP is defined in page table entries */
	mcr	p15, 0, r0, c3, c0			/* Load domain access register */
	mrc	p15, 0, r0, c1, c0, 0		/* Read control register */
	ldr	r1, =(CTL_ICACHE | CTL_BPRD | CTL_CACHE | CTL_MMU)
	orr	r0, r0, r1					/* Enable MMU, caches and branch prediction */
	ldr	r1, =(CTL_AFLT | CTL_AFE | CTL_TRE)
	bic	r0, r0, r1					/* Disable alignment checks, AFE and TRE */
	mcr	p15, 0, r0, c1, c0, 0		/* Load control register... */
	mrc	p15, 0, r0, c1, c0, 0		/* ...and read it back */
	isb

	/*
	 * Reload PC register for virtual address.
	 */
	ldr	pc, reload_pc_target	/* Reset pc here */
reload_pc:

#else /* !CONFIG_MMU */
    mrc p15, 0, r0, c1, c0, 0    /* Read control register */
    ldr r1,=(CTL_AFLT)
    bic r0, r0, r1              /* Disable alignment checks */
    mcr p15, 0, r0, c1, c0, 0
#endif /* !CONFIG_MMU */

	/*
	 * Clear kernel BSS
	 */
	ldr	r1, =__bss
	ldr	r2, =__end
	mov	r0, #0
	cmp	r1, r2
	beq	2f
1:
	str	r0, [r1], #4
	cmp	r1, r2
	bls	1b
2:

	/*
	 * Initilize spl.
	 */
	ldr	r1, curspl		/* curspl = 15 */
	mov	r2, #15
	str	r2, [r1]

	/*
	 * Jump to kernel main routine
	 */
	b	main

/*
 * Relocate exception vector
 *
 * void vector_copy(vaddr_t dest);
 */
ENTRY(vector_copy)
	ldr	r1, =vector_start
	ldr	r2, =vector_end
1:
	ldmia	r1!, {r3}
	stmia	r0!, {r3}
	teq	r1, r2
	bne	1b
	bx	lr

#ifdef CONFIG_CACHE
/*
 * Enable cache
 */
ENTRY(cache_init)
	bx	lr
#endif

/*
 * Interrupt entry point
 */
ENTRY(interrupt_entry)
	stmfd	sp, {r0-r4}		/* Save work registers */
	sub	r4, sp, #(4*5)		/* r4: Pointer to saved registers */
	mrs	r0, spsr		/* r0: cpsr */
	sub	r3, lr, #4		/* r3: original pc */

	mrs	r1, cpsr		/* Set processor to SVC mode */
	bic	r1, r1, #PSR_MODE
	orr	r1, r1, #PSR_SVC_MODE
	msr	cpsr_c, r1

	mov	r1, sp			/* r1: svc_sp */
	mov	r2, lr			/* r2: svc_lr */
	stmfd	sp!, {r0-r3, r12}	/* Push cpsr, svc_sp, svc_lr, pc + dummy */
	ldmfd	r4, {r0-r4}		/* Restore work registers */
	sub	sp, sp, #(4*15)
	stmia	sp, {r0-r14}^		/* Push r0-r14 */
	nop				/* Instruction gap for stm^ */

	ldr	r4, irq_nesting   	/* Increment IRQ nesting level */
	ldr	r5, [r4]		/* r5: Previous nesting level */
	add	r0, r5, #1
 	str	r0, [r4]

	mov	r7, sp			/* Save stack */
	ldr	r3, int_stack		/* Adjust stack for IRQ */
	cmp	r5, #0			/* Outermost interrupt? */
	moveq	sp, r3			/* If outermost, switch stack */
	bleq	sched_lock		/* If outermost, lock scheduler */
	bl	interrupt_handler	/* Call main interrupt handler */

	mov	sp, r7			/* Restore stack */
	str	r5, [r4]		/* Restore IRQ nesting level */
	cmp	r5, #0			/* Outermost interrupt? */
	bne	interrupt_ret
	bl	sched_unlock		/* Try to preempt */

	ldr	r0, [sp, #REG_CPSR]	/* Get previous mode */
	and	r0, r0, #PSR_MODE
	cmp	r0, #PSR_APP_MODE	/* Return to application mode? */
	bne	interrupt_ret

	mrs	r5, cpsr		/* Enable IRQ */
	bic	r4, r5, #0xc0
	msr	cpsr_c, r4
	bl	exception_deliver	/* Check exception */
	msr	cpsr_c, r5		/* Restore IRQ */
interrupt_ret:
	mov	r0, sp
 	ldr	r1, [r0, #REG_CPSR]	/* Restore spsr */
 	msr	spsr_all, r1
 	ldmfd	r0, {r0-r14}^		/* Restore user mode registers */
	nop				/* Instruction gap for ldm^ */
	add	sp, sp, #(4*16)
	ldmia	sp, {sp, lr, pc}^	/* Restore lr and exit */

/*
 * System call entry
 */
	.global syscall_ret
ENTRY(syscall_entry)
	sub	sp, sp, #CTXREGS	/* Adjust stack */
	stmia	sp, {r0-r14}^		/* Push r0-r14 */
	nop				/* Instruction gap for stm^ */
	mrs	r5, spsr		/* Push cpsr */
	str	r5, [sp, #REG_CPSR]
	add	r12, sp, #CTXREGS
	str	r12, [sp, #REG_SVCSP]	/* Push svc_sp */
	bic	lr, lr, #1		/* Mask bit 0 of lr */
	str	lr, [sp, #REG_SVCLR]	/* Push svc_lr */
	str	lr, [sp, #REG_PC]	/* Push pc */

	tst	r5, #PSR_THUMB		/* Check Thumb mode */
	ldreq	r4, [lr, #-4]		/* ARM mode: Load swi instruction */
	biceq	r4, r4, #0xff000000	/* Mask out opcode */
	beq	1f
	ldrb	r4, [lr, #-2]		/* Thumb mode: Load svc immediate */
1:

	mrs	r5, cpsr		/* Enable IRQ */
	bic	r5, r5, #0xc0
	msr	cpsr_c, r5

	stmfd	sp!, {r4, r5}
	bl	syscall_handler		/* System call dispatcher */
	ldmfd	sp!, {r4, r5}

	cmp	r4, #0			/* Skip storing error if exception_return */
	strne	r0, [sp]		/* Set return value to r0 */
	bl	exception_deliver	/* Check exception */
syscall_ret:
	mrs	r5, cpsr		/* Disable IRQ */
	orr	r5, r5, #0xc0
	msr	cpsr_c, r5
	mov	r5, sp
	ldr	r1, [r5, #REG_CPSR]	/* Restore spsr */
	msr	spsr_all, r1
 	ldmfd	r5, {r0-r14}^		/* Restore user mode registers */
	nop				/* Instruction gap for ldm^ */
	add	sp, sp, #REG_SVCSP
	ldmia	sp, {sp, lr, pc}^	/* Restore lr and exit */

/*
 * Undefined instruction
 */
ENTRY(undefined_entry)
	sub	sp, sp, #CTXREGS	/* Adjust stack */
	stmia	sp, {r0-r14}^		/* Push r0-r14 */
	nop				/* Instruction gap for stm^ */
	mov	r0, #TRAP_UNDEFINED
	b	trap_common

/*
 * Prefetch abort
 */
ENTRY(prefetch_entry)
	sub	lr, lr, #4		/* Adjust the lr */
	sub	sp, sp, #CTXREGS	/* Adjust stack */
	stmia	sp, {r0-r14}^		/* Push r0-r14 */
	nop				/* Instruction gap for stm^ */
	mov	r0, #TRAP_PREFETCH_ABORT
	b	trap_common

/*
 * Data abort
 */
ENTRY(abort_entry)
	sub	lr, lr, #8		/* Adjust the lr */
	sub	sp, sp, #CTXREGS	/* Adjust stack */
	stmia	sp, {r0-r14}^		/* Push r0-r14 */
	nop				/* Instruction gap for stm^ */
	mov	r0, #TRAP_DATA_ABORT
	b	trap_common

/*
 * Common entry for all traps
 * r0 - trap type
 */
ENTRY(trap_common)
	add	r5, sp, #CTXREGS
	str	r5, [sp, #REG_SVCSP]	/* Push svc_sp */
	str	lr, [sp, #REG_PC]	/* Push pc */
	mrs	r5, spsr		/* Push cpsr */
	str	r5, [sp, #REG_CPSR]

	str	r0, [sp, #REG_R0]	/* Set trap type to R0 */
	mov	r0, sp
	bl	trap_handler

	mov	r5, sp
	ldr	r1, [r5, #REG_CPSR]	/* Restore cpsr */
	msr	spsr_all, r1
	ldr	lr, [r5, #REG_PC]	/* Restore pc (lr) */
	ldr	sp, [r5, #REG_SVCSP]	/* Restore svc_sp */
	ldmfd	r5, {r0-r14}^		/* Restore user mode registers */
	nop				/* Instruction gap for ldm^ */
	movs	pc, lr			/* Exit, with restoring cpsr */

ENTRY(unused_entry)
	b	unused_entry		/* Not support... */

#ifdef CONFIG_SMP
/*
 * Secondary CPU entry point
 * r0: cpuid (already set in reset_entry)
 */
ENTRY(ap_entry)
	/*
	 * Load AP-specific stack.
	 * sp = &ap_boot_stacks[cpuid][KSTACKSZ]
	 */
	ldr	r1, =ap_boot_stacks
	mov	r2, #768		/* KSTACKSZ */
	add	r3, r0, #1
	mul	r4, r3, r2
	add	sp, r1, r4

	/*
	 * Setup stack pointer for each processor mode
	 */
	mov	r0, #(PSR_IRQ_MODE|PSR_FIQ_DIS|PSR_IRQ_DIS)
	msr	cpsr, r0
	mov	sp, sp			/* Reuse same stack for early boot */

	mov	r0, #(PSR_SVC_MODE|PSR_FIQ_DIS|PSR_IRQ_DIS)
	msr	cpsr, r0

#ifdef CONFIG_MMU
	/*
	 * Enable MMU for AP (Reuse BSP's boot page directory)
	 */
	dsb
	ldr	r1, =BOOT_PGD_PHYS
	mcr	p15, 0, r1, c2, c0, 0		/* Load page table pointer */
	mov	r0, #0
	mcr	p15, 0, r0, c8, c7, 0		/* Flush I,D TLBs */
	dsb
	isb
	ldr	r0, =0x55555555				/* AP is defined in page table entries */
	mcr	p15, 0, r0, c3, c0			/* Load domain access register */
	mrc	p15, 0, r0, c1, c0, 0		/* Read control register */
	ldr	r1, =(CTL_ICACHE | CTL_BPRD | CTL_CACHE | CTL_MMU)
	orr	r0, r0, r1					/* Enable MMU, caches and branch prediction */
	ldr	r1, =(CTL_AFLT | CTL_AFE | CTL_TRE)
	bic	r0, r0, r1					/* Disable alignment checks, AFE and TRE */
	mcr	p15, 0, r0, c1, c0, 0		/* Load control register... */
	mrc	p15, 0, r0, c1, c0, 0		/* ...and read it back */
	isb

	/*
	 * Reload PC register for virtual address.
	 */
	ldr	pc, ap_reload_pc_target
ap_reload_pc:
#endif

	/* Jump to C code */
	b	smp_ap_boot

#ifdef CONFIG_MMU
ap_reload_pc_target:	.word	ap_reload_pc
#endif

#endif /* CONFIG_SMP */
		/* Not support... */

ENTRY(fiq_entry)
	b	fiq_entry		/* Not support... */

/*
 * Switch register context.
 * r0 = previous kern_regs, r1 = next kern_regs
 * Interrupts must be disabled by caller.
 *
 * syntax - void cpu_switch(kern_regs *prev, kern_regs *next)
 *
 * Note: GCC uses r0-r3,r12 as scratch registers
 */
ENTRY(cpu_switch)
	stmia	r0, {r4-r11, sp, lr}	/* Save previous register context */
	ldmia	r1, {r4-r11, sp, pc}	/* Restore next register context */

/*
 * Entry point for kernel thread
 */
ENTRY(kernel_thread_entry)
	mov	r0, r5			/* Set argument */
	bx	r4			/* Jump to kernel thread */
1:
	b	1b


/*
 * Copy data from user to kernel space.
 * Returns 0 on success, or EFAULT on page fault.
 *
 *  syntax - int copyin(const void *uaddr, void *kaddr, size_t len)
 */
	.global known_fault1
ENTRY(copyin)
 	mov	r12, sp
 	stmdb	sp!, {r4, r5, r11, r12, lr, pc}
 	sub	r11, r12, #4
	cmp	r0, #(USERLIMIT)
	bhi	copy_fault
 	mov	r12, #0
 	b	2f
1:
	ldrb	r3, [r12, r0]
known_fault1:				/* May be fault here */
 	strb	r3, [r12, r1]
 	add	r12, r12, #1
2:
	subs	r2, r2, #1
 	bcs	1b
	mov	r0, #0			/* Set no error */
 	ldmia	sp, {r4, r5, r11, sp, pc}

/*
 * Copy data to user from kernel space.
 * Returns 0 on success, or EFAULT on page fault.
 *
 *  syntax - int copyout(const void *kaddr, void *uaddr, size_t len)
 */
	.global known_fault2
ENTRY(copyout)
 	mov	r12, sp
 	stmdb	sp!, {r4, r5, r11, r12, lr, pc}
 	sub	r11, r12, #4
	cmp	r1, #(USERLIMIT)
	bhi	copy_fault
 	mov	r12, #0
 	b	2f
1:
	ldrb	r3, [r12, r0]
known_fault2:				/* May be fault here */
 	strb	r3, [r12, r1]
 	add	r12, r12, #1
2:
	subs	r2, r2, #1
 	bcs	1b
	mov	r0, #0			/* Set no error */
 	ldmia	sp, {r4, r5, r11, sp, pc}

/*
 * copyinstr - Copy string from user space.
 * Returns 0 on success, or EFAULT on page fault, or ENAMETOOLONG.
 *
 *  syntax - int copyinstr(const char *uaddr, void *kaddr, size_t len);
 */
	.global known_fault3
ENTRY(copyinstr)
 	mov	r12, sp
 	stmdb	sp!, {r4, r5, r11, r12, lr, pc}
 	sub	r11, r12, #4
	cmp	r0, #(USERLIMIT)
	bhi	copy_fault
 	mov	r12, #0
 	b	2f
1:
	ldrb	r3, [r12, r0]
known_fault3:				/* May be fault here */
 	strb	r3, [r12, r1]
	cmp	r3, #0
	beq	3f
 	add	r12, r12, #1
2:
	subs	r2, r2, #1
 	bcs	1b
	mov	r0, #(ENAMETOOLONG)
	b	4f
3:
	mov	r0, #0			/* Set no error */
4:
 	ldmia	sp, {r4, r5, r11, sp, pc}

/*
 * Fault entry for user access
 */
ENTRY(copy_fault)
	mov	r0, #(EFAULT)
 	ldmia	sp, {r4, r5, r11, sp, pc}


/*
 * int spl0(void);
 */
ENTRY(spl0)
	ldr	r1, curspl		/* curspl = 0 */
	ldr	r0, [r1]
	mov	r2, #0
	str	r2, [r1]

	mrs	r1, cpsr		/* Enable interrupt */
	bic	r1, r1, #0xc0
	msr	cpsr_c, r1
	bx	lr

/*
 * int splhigh(void);
 */
ENTRY(splhigh)
	mrs	r1, cpsr		/* Disable interrupt */
	orr	r1, r1, #0xc0
	msr	cpsr_c, r1

	ldr	r1, curspl		/* curspl = 15 */
	ldr	r0, [r1]
	mov	r2, #15
	str	r2, [r1]
	bx	lr

/*
 * void splx(int s);
 */
ENTRY(splx)
	mov	r3, r0			/* r3: new spl */
	ldr	r1, curspl
	ldr	r0, [r1]
	cmp	r3, r0
	moveq	pc, lr			/* Return if equal */
	str	r3, [r1]

	cmp	r3, #0
	mrs	r1, cpsr
	bic	r1, r1, #0xc0
	orrne	r1, r1, #0xc0		/* Disable interrupt if curspl != 0 */
	msr	cpsr_c, r1
	bx	lr


/*
 * void sploff(void);
 */
ENTRY(sploff)
	mrs	r0, cpsr
	orr	r0, r0, #0xc0
	msr	cpsr_c, r0
	bx	lr

/*
 * void splon(void);
 */
ENTRY(splon)
	mrs	r0, cpsr
	bic	r0, r0, #0xc0
	msr	cpsr_c, r0
	bx	lr

/*
 * Interrupt nest counter.
 */
	.section ".bss"
irq_nesting_value:
	.long	0

/*
 * Current spl
 */
curspl_value:
	.long	0

/*
 * Init flag for debug
 */
init_done_value:
	.long	0

	.end

.section .note.GNU-stack,"",%progbits
