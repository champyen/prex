/*
 * cpufunc.c - CPU specific functions for RISC-V
 */

#include <sys/types.h>
#include <cpufunc.h>

void cpu_idle(void)
{
    __asm__ volatile("wfi");
}

uint32_t hal_cpu_id(void)
{
    uint32_t id;
    __asm__ volatile("csrr %0, mhartid" : "=r"(id));
    return id;
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
    __asm__ volatile("csrr %0, mtval" : "=r"(addr));
    return addr;
}

int get_faultstatus(void)
{
    int status;
    __asm__ volatile("csrr %0, mcause" : "=r"(status));
    return status;
}

void switch_ttb(paddr_t ttb)
{
    /* Sv32: set satp and flush TLB */
    uint32_t satp = (0x80000000) | (ttb >> 12); /* Mode 1 (Sv32) + PPN */
    __asm__ volatile("csrw satp, %0" : : "r"(satp));
    __asm__ volatile("sfence.vma");
}

void set_ttb(paddr_t ttb)
{
    uint32_t satp = (0x80000000) | (ttb >> 12);
    __asm__ volatile("csrw satp, %0" : : "r"(satp));
}

paddr_t get_ttb(void)
{
    uint32_t satp;
    __asm__ volatile("csrr %0, satp" : "=r"(satp));
    return (paddr_t)(satp << 12);
}

void flush_cache(void)
{
    /* RISC-V doesn't have a standard cache flush instruction in user spec, 
       but fence.i is used for instruction cache. */
    __asm__ volatile("fence.i");
}
