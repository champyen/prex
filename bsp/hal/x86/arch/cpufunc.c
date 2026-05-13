/*-
 * Copyright (c) 2008, Kohsuke Ohtani
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
 * cpufunc.c - CPU specific functions for x86
 */

#include <sys/types.h>
#include <cpufunc.h>

void cpu_idle(void)
{
    __asm__ volatile("hlt");
}

void flush_tlb(void)
{
    uint32_t val;
    __asm__ volatile("movl %%cr3, %0\n"
                     "movl %0, %%cr3"
                     : "=r"(val)
                     :
                     : "memory");
}

void flush_cache(void)
{
    __asm__ volatile("wbinvd" : : : "memory");
}

void load_tr(uint32_t tr)
{
    __asm__ volatile("ltr %w0" : : "a"(tr));
}

void load_gdt(void* gdt)
{
    __asm__ volatile("lgdt (%0)" : : "r"(gdt));
}

void load_idt(void* idt)
{
    __asm__ volatile("lidt (%0)" : : "r"(idt));
}

uint32_t get_cr2(void)
{
    uint32_t val;
    __asm__ volatile("movl %%cr2, %0" : "=r"(val));
    return val;
}

void set_cr3(uint32_t val)
{
    __asm__ volatile("movl %0, %%cr3" : : "r"(val) : "memory");
}

uint32_t get_cr3(void)
{
    uint32_t val;
    __asm__ volatile("movl %%cr3, %0" : "=r"(val));
    return val;
}

void outb(int port, u_char val)
{
    __asm__ volatile("outb %0, %w1" : : "a"(val), "d"(port));
}

u_char inb(int port)
{
    u_char val;
    __asm__ volatile("inb %w1, %0" : "=a"(val) : "d"(port));
    return val;
}

void outb_p(int port, u_char val)
{
    __asm__ volatile("outb %0, %w1\noutb %%al, $0x80" : : "a"(val), "d"(port));
}

u_char inb_p(int port)
{
    u_char val;
    __asm__ volatile("inb %w1, %0\noutb %%al, $0x80" : "=a"(val) : "d"(port));
    return val;
}

void rdmsr(uint32_t msr, uint32_t* lo, uint32_t* hi)
{
    __asm__ volatile("rdmsr" : "=a"(*lo), "=d"(*hi) : "c"(msr));
}

void wrmsr(uint32_t msr, uint32_t lo, uint32_t hi)
{
    __asm__ volatile("wrmsr" : : "a"(lo), "d"(hi), "c"(msr));
}

void cpuid(uint32_t op, uint32_t* eax, uint32_t* ebx, uint32_t* ecx, uint32_t* edx)
{
    __asm__ volatile("cpuid" : "=a"(*eax), "=b"(*ebx), "=c"(*ecx), "=d"(*edx) : "a"(op));
}
