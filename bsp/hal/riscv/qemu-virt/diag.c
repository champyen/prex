/*
 * diag.c - diagnostic message support for RISC-V QEMU virt
 */

#include <sys/bootinfo.h>
#include <kernel.h>
#include <cpufunc.h>
#include <mmu.h>
#include <smp.h>

#define UART_BASE CONFIG_NS16550_BASE

#define UART_THR (*(volatile uint8_t*)(UART_BASE + 0))
#define UART_LSR (*(volatile uint8_t*)(UART_BASE + 5))

#define LSR_THRE 0x20

int hal_uart_lock(void)
{
    return 0;
}

void hal_uart_unlock(int s)
{
}

void diag_putc(char c)
{
    while (!(UART_LSR & LSR_THRE))
        ;
    UART_THR = (uint8_t)c;
}

void diag_puts(char* buf)
{
    while (*buf) {
        if (*buf == '\n')
            diag_putc('\r');
        diag_putc(*buf++);
    }
}

void diag_init(void)
{
}
