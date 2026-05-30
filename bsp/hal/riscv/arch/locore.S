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
#include <mmu.h>
#define LOCORE
#include <sys/param.h>
#include <riscv_csr.h>

        .option norelax
        .section ".text","ax"

/*
 * Kernel start point
 */
ENTRY(kernel_start)
    fence.i
    /* 
     * Identify as BSP (hart 0).
     * The bootloader might not pass a0 correctly.
     */
    li a0, 0
	j	reset_entry

/*
 * Exception vector
 */
	.align 4
vector_entry:
    /* Swap tp and CSR_SCRATCH.
     * tp = &riscv_cpu, CSR_SCRATCH = user_tp (if from user)
     * tp = &cpu_control, CSR_SCRATCH = &riscv_cpu (if from kernel)
     */
    csrrw tp, CSR_SCRATCH, tp

    /* Save original t0 to riscv_cpu->temp_t0 (offset 12) */
    sw t0, 12(tp)

    /* Check if we came from Kernel Mode directly using sstatus.SPP */
    csrr t0, CSR_STATUS
    andi t0, t0, 0x100          /* Check SPP (bit 8) */
    bnez t0, kernel_trap

    /* Coming from user */
    /* Save sp temporarily in riscv_cpu->user_sp */
    sw sp, 4(tp)
    
    /* Load kernel_sp from riscv_cpu->kernel_sp */
    lw sp, 0(tp)
    
    /* Clear kernel_sp to indicate we are in kernel */
    sw zero, 0(tp)
    j 1f

kernel_trap:
    /* Restore tp and CSR_SCRATCH */
    csrrw tp, CSR_SCRATCH, tp
    j kernel_vector_entry

1:  /* Coming from user */
    /* tp = &riscv_cpu, CSR_SCRATCH = user_tp, sp = kernel_sp */
    addi sp, sp, -144
    
    /* Save ra, gp */
    sw ra, 0(sp)
    sw gp, 8(sp)
    
    /* Save user tp (from CSR_SCRATCH) */
    csrr t0, CSR_SCRATCH
    sw t0, 12(sp)
    
    /* Save user sp (from riscv_cpu->user_sp) */
    lw t0, 4(tp)
    sw t0, 4(sp)
    
    /* Restore and save original t0 (from riscv_cpu->temp_t0) */
    lw t0, 12(tp)
    sw t0, 16(sp)
    
    /* Restore CSR_SCRATCH to &riscv_cpu and load real tp */
    csrw CSR_SCRATCH, tp        /* CSR_SCRATCH = &riscv_cpu */
    lw tp, 8(tp)                /* tp = riscv_cpu->cpu_control */
    
    /* Save remaining registers */
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


    /* Save CSRs for user path */
    csrr t0, CSR_EPC
    sw t0, 124(sp)
    csrr t0, CSR_STATUS
    sw t0, 128(sp)
    csrr t0, CSR_CAUSE
    sw t0, 132(sp)
    csrr t0, CSR_TVAL
    sw t0, 136(sp)
    
    j 3f

kernel_vector_entry:
    /* We came from kernel. tp is already real kernel tp. sp is kernel sp. */
    addi sp, sp, -144
    
    /* Save ra first so we can use it as temp */
    sw ra, 0(sp)
    
    /* Restore and save original t0 (from riscv_cpu->temp_t0) */
    csrr ra, CSR_SCRATCH        /* ra = &riscv_cpu */
    lw ra, 12(ra)               /* ra = original kernel_t0 */
    sw ra, 16(sp)               /* u->t0 = original kernel_t0 */
    
    /* Restore ra */
    lw ra, 0(sp)
    
    /* Save other registers */
    addi t0, sp, 144
    sw t0, 4(sp)                /* Save original sp */
    sw gp, 8(sp)
    sw tp, 12(sp)               /* Save kernel tp */
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

    /* Save CSRs */
    csrr t0, CSR_EPC
    sw t0, 124(sp)
    csrr t0, CSR_STATUS
    sw t0, 128(sp)
    csrr t0, CSR_CAUSE
    sw t0, 132(sp)
    csrr t0, CSR_TVAL
    sw t0, 136(sp)

3:  /* Common trap handler call */

    /* Setup Global Pointer */
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    /* Check if it is an interrupt (cause < 0) */
    lw t0, 132(sp)              /* t0 = cause */
    bge t0, zero, 1f            /* Skip if exception (cause >= 0) */

    /* Interrupt entry path */
    lw t1, 8(tp)                /* t1 = nest_count */
    addi t2, t1, 1
    sw t2, 8(tp)                /* nest_count++ */

    bnez t1, 2f                 /* Skip sched_lock if nested (prev nest_count > 0) */
    call sched_lock
2:
    mv a0, sp
    call trap_handler

    /* Interrupt exit path */
    lw t1, 8(tp)                /* t1 = nest_count */
    addi t1, t1, -1
    sw t1, 8(tp)                /* nest_count-- */

    bnez t1, 3f                 /* Skip sched_unlock if nested (new nest_count > 0) */
    call sched_unlock
3:
    j syscall_ret

1:  /* Exception path */
    mv a0, sp
    call trap_handler
    /* Fall through to syscall_ret */

ENTRY(syscall_ret)
#ifdef CONFIG_SMODE
    csrci sstatus, 2
#else
    csrci mstatus, 8
#endif
    fence.i

    /* Restore CSRs */
    lw t0, 124(sp)
    csrw CSR_EPC, t0
    lw t0, 128(sp)
    
    /* Clear SIE bit (bit 1) to ensure interrupts are disabled in S-mode
     * during the return path. They will be enabled by sret restoring from SPIE.
     */
    andi t0, t0, ~2

#ifdef CONFIG_SMODE
    li t1, 1 << 18      /* Force SUM=1 */
    or t0, t0, t1
#endif
    csrw CSR_STATUS, t0
    
    /* Returning to user mode? Check privilege bit */
    andi t0, t0, 0x100  /* Check SPP (bit 8) */
    bnez t0, returning_to_kernel
    
    /* Returning to user mode: Save kernel stack top to riscv_cpu->kernel_sp */
    csrr t1, CSR_SCRATCH        /* t1 = &riscv_cpu */
    addi t2, sp, 144
    sw t2, 0(t1)                 /* riscv_cpu->kernel_sp = sp + 144 */

    /* Returning to user mode: Restore user tp */
    lw tp, 12(sp)
    j restore_regs

returning_to_kernel:
    /* Returning to kernel mode: Keep current kernel tp */
    /* (do not load tp) */

restore_regs:  /* Restore general purpose registers */
    lw ra, 0(sp)
    lw gp, 8(sp)
    /* tp is conditionally restored above */
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
irq_nesting:		.word	irq_nesting_value
init_done:		.word	init_done_value

#ifdef CONFIG_SMP
    /*
     * Secondary hart entry point
     * a0 = hartid
     * a1 = opaque (0)
     */
ENTRY(ap_reset_entry)
    /* Park harts that are out of bounds */
    li t0, CONFIG_SMP_NCPUS
    blt a0, t0, 2f
1:  wfi
    j 1b
2:

    /* Disable interrupts */
#ifdef CONFIG_SMODE
    csrci sstatus, 2
#else
    csrci mstatus, 8
#endif

    /* Initialize CSR_SCRATCH to &riscv_cpus[hartid] */
    la t0, riscv_cpus
    slli t1, a0, 4              /* t1 = hartid * 16 */
    add t0, t0, t1              /* t0 = &riscv_cpus[hartid] */
    csrw CSR_SCRATCH, t0



    /* Setup Global Pointer */
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    /* 
     * Get local cpu_control
     * tp = &cpu_table[hartid]
     * sizeof(struct cpu_control) = 32 (aligned)
     */
    la t0, cpu_table
    slli t1, a0, 6      /* t1 = id * 64 */
    add tp, t0, t1

#ifdef CONFIG_MMU
    /* Enable MMU using the same boot page directory as BSP */
    li t0, BOOT_PGD_PHYS
    srli t0, t0, 12
    li t1, 1 << 31
    or t0, t0, t1
    csrw CSR_SATP, t0
    sfence.vma
    fence rw, rw
    fence.i
#endif

    /* Setup stack for AP */
    la t0, ap_boot_stacks
    li t1, KSTACKSZ
    addi a1, a0, 1      /* stack_top = stacks[id+1] */
    mul  t1, a1, t1     /* t1 = a1 * KSTACKSZ */
    
    add sp, t0, t1
    addi sp, sp, -1024

    la t0, vector_entry
    csrw CSR_TVEC, t0

    /* Jump to C entry */
    call smp_ap_boot
#endif

ENTRY(reset_entry)
    /* Get hartid */
#ifdef CONFIG_SMODE
    /* In S-mode, we might be here with a0 = hartid from SBI */
#else
    csrr a0, mhartid
#endif
#ifdef CONFIG_SMP
    bnez a0, ap_reset_entry
#else
    /* Non-BSP harts should park if SMP is not enabled */
    bnez a0, 1f
#endif


    /* Disable interrupts */
#ifdef CONFIG_SMODE
    csrci sstatus, 2
#else
    csrci mstatus, 8
#endif
    j 2f

1:  wfi
    j 1b
2:
    /* Enable SUM (Supervisor User Memory access) */
#ifdef CONFIG_SMODE
    li t0, 1 << 18
    csrs sstatus, t0
#endif
    
    /* Setup Global Pointer */
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    /* Setup stack */
    la sp, BOOTSTKTOP
    
    /* Setup CSR_SCRATCH to &riscv_cpus[0] */
    la t0, riscv_cpus
    csrw CSR_SCRATCH, t0

    /* Clear BSS */
    la t0, __bss
    la t1, __end
    bgeu t0, t1, 2f
1:
    sw zero, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, 1b
2:

    /* Setup trap vector */
    la t0, vector_entry
    csrw CSR_TVEC, t0
    
#ifdef CONFIG_MMU
    /*
     * Initialize boot page directory (BOOT_PGD_PHYS)
     * Zero fill 4KB.
     */
    li t0, BOOT_PGD_PHYS
    li t1, 1024
1:
    sw zero, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, 1b

    /*
     * Initialize boot page table (BOOT_PTE0_PHYS)
     * Zero fill 4KB.
     */
    li t0, BOOT_PTE0_PHYS
    li t1, 1024
1:
    sw zero, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, 1b

    /*
     * Populate BOOT_PTE0_PHYS to map first 4MB of RAM (0x80000000)
     * PTE_SYSTEM = PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D = 0xcf.
     */
    li t0, BOOT_PTE0_PHYS
    li t1, 1024
    li t2, (0x80000000 >> 2) | 0xcf
    li t3, 0x400           /* PPN offset per page (0x1000 >> 2) */
2:
    sw t2, 0(t0)
    addi t0, t0, 4
    add t2, t2, t3
    addi t1, t1, -1
    bnez t1, 2b

    /*
     * Map BOOT_PTE0_PHYS in BOOT_PGD_PHYS[512] (0x80000000 >> 22 = 512)
     * BOOT_PGD_PHYS[512] = (BOOT_PTE0_PHYS >> 2) | PTE_V
     */
    li t0, BOOT_PGD_PHYS + 2048
    li t1, (BOOT_PTE0_PHYS >> 2) | 0x01 /* PTE_V */
    sw t1, 0(t0)


    /*
     * Map UART0 (0x10000000) to 0x10000000 (1:1) for early physical access
     * BOOT_PGD_PHYS[64] = (0x10000000 >> 2) | (PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
     * PPN for 0x10000000 is 0x10000.
     * PPN << 10 = 0x04000000.
     * Flags = 0xc7.
     * Entry = 0x040000c7.
     */
    li t0, BOOT_PGD_PHYS + 256      /* 64 * 4 = 256 */
    li t1, 0x040000c7
    sw t1, 0(t0)

    /*
     * Map UART0 to CONFIG_NS16550_BASE (0x10000000 + CONFIG_IOMEM_BASE) for early virtual access
     * Index = (0x10000000 + CONFIG_IOMEM_BASE) >> 22
     */
    li t0, BOOT_PGD_PHYS + (((0x10000000 + CONFIG_IOMEM_BASE) >> 22) * 4)
    li t1, 0x040000c7
    sw t1, 0(t0)

    /*
     * Enable MMU
     * satp = (1 << 31) | (BOOT_PGD_PHYS >> 12)
     * MODE = 1 (Sv32)
     */
    li t0, BOOT_PGD_PHYS
    srli t0, t0, 12
    li t1, 1 << 31
    or t0, t0, t1
    csrw CSR_SATP, t0

    /*
     * Flush TLB and synchronize
     */
    sfence.vma
    fence rw, rw
    fence.i
#endif

    la tp, cpu_table

    call main

/*
 * Context switch
 */
ENTRY(cpu_switch)
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

    /* Update riscv_cpu->kernel_sp for next thread */
    csrr t0, CSR_SCRATCH        /* t0 = &riscv_cpu */
    lw t1, 64(a1)               /* t1 = next->kernel_sp */
    sw t1, 0(t0)                /* riscv_cpu->kernel_sp = next->kernel_sp */

    ret

ENTRY(kernel_thread_entry)

#ifdef CONFIG_SMP
    call sched_bkl_unlock
#endif
    mv a0, s1
    jr s0

ENTRY(get_status)
    csrr a0, CSR_STATUS
    ret

ENTRY(splon)
#ifdef CONFIG_SMODE
    csrsi sstatus, 2
#else
    csrsi mstatus, 8
#endif
    ret

ENTRY(sploff)
#ifdef CONFIG_SMODE
    csrci sstatus, 2
#else
    csrci mstatus, 8
#endif
    ret

ENTRY(copyin)
    li t0, 0
1:
    bge t0, a2, 2f
    lb t1, 0(a0)
    sb t1, 0(a1)
    addi a0, a0, 1
    addi a1, a1, 1
    addi t0, t0, 1
    j 1b
2:
    li a0, 0
    ret

ENTRY(copyout)
    li t0, 0
1:
    bge t0, a2, 2f
    lb t1, 0(a0)
    sb t1, 0(a1)
    addi a0, a0, 1
    addi a1, a1, 1
    addi t0, t0, 1
    j 1b
2:
    li a0, 0
    ret

ENTRY(copyinstr)
    li t0, 0
1:
    bge t0, a2, 2f
    lb t1, 0(a0)
    sb t1, 0(a1)
    beqz t1, 3f
    addi a0, a0, 1
    addi a1, a1, 1
    addi t0, t0, 1
    j 1b
2:
    li a0, 36 /* ENAMETOOLONG */
    ret
3:
    li a0, 0
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

.section .note.GNU-stack,"",%progbits
