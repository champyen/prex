/*
 * cpufunc.c - CPU specific functions for RISC-V
 */

#include <sys/types.h>
#include <cpu_control.h>
#include <cpufunc.h>
#include <riscv_csr.h>

void cpu_idle(void)
{
#ifdef CONFIG_SMODE
    __asm__ volatile("csrsi sstatus, 2; wfi");
#else
    __asm__ volatile("csrsi mstatus, 8; wfi");
#endif
}

uint32_t hal_cpu_id(void)
{
    struct cpu_control* cpu;
#ifdef CONFIG_SMODE
    __asm__ volatile("mv %0, tp" : "=r"(cpu));
    if (cpu) return cpu->cpu_id;
#else
    uint32_t id;
    __asm__ volatile("csrr %0, mhartid" : "=r"(id));
    return id;
#endif
    return 0;
}

void flush_tlb(void)
{
    __asm__ volatile("sfence.vma");
}

void cpu_barrier(void)
{
    __asm__ volatile("fence");
}

/*
 * Note: These require board specific implementation for Sv32
 */
void* get_faultaddress(void)
{
    void* addr;
    __asm__ volatile("csrr %0, " STR(CSR_TVAL) : "=r"(addr));
    return addr;
}

int get_faultstatus(void)
{
    int status;
    __asm__ volatile("csrr %0, " STR(CSR_CAUSE) : "=r"(status));
    return status;
}

void switch_ttb(paddr_t ttb)
{
#ifdef CONFIG_SMODE
    /* Sv32: set satp and flush TLB */
    uint32_t satp = (0x80000000) | (ttb >> 12); /* Mode 1 (Sv32) + PPN */
    __asm__ volatile("csrw " STR(CSR_SATP) ", %0" : : "r"(satp));
    __asm__ volatile("sfence.vma");
#endif
}

void set_ttb(paddr_t ttb)
{
#ifdef CONFIG_SMODE
    uint32_t satp = (0x80000000) | (ttb >> 12);
    __asm__ volatile("csrw " STR(CSR_SATP) ", %0" : : "r"(satp));
#endif
}

paddr_t get_ttb(void)
{
#ifdef CONFIG_SMODE
    uint32_t satp;
    __asm__ volatile("csrr %0, " STR(CSR_SATP) : "=r"(satp));
    return (paddr_t)(satp << 12);
#else
    return 0;
#endif
}

void flush_cache(void)
{
    /* RISC-V doesn't have a standard cache flush instruction in user spec, 
       but fence.i is used for instruction cache. */
    __asm__ volatile("fence.i");
}
