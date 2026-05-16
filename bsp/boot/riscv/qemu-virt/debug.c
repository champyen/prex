/*
 * debug.c - debug routines for RISC-V QEMU virt
 */

#include <sys/param.h>
#include <boot.h>

#define UART_BASE 0x10000000

#define UART_RHR (*(volatile uint8_t*)(UART_BASE + 0))
#define UART_THR (*(volatile uint8_t*)(UART_BASE + 0))
#define UART_IER (*(volatile uint8_t*)(UART_BASE + 1))
#define UART_FCR (*(volatile uint8_t*)(UART_BASE + 2))
#define UART_LCR (*(volatile uint8_t*)(UART_BASE + 3))
#define UART_MCR (*(volatile uint8_t*)(UART_BASE + 4))
#define UART_LSR (*(volatile uint8_t*)(UART_BASE + 5))

#define LSR_THRE 0x20

void debug_putc(int c)
{
    if (c == '\n') {
        while (!(UART_LSR & LSR_THRE))
            ;
        UART_THR = '\r';
    }
    while (!(UART_LSR & LSR_THRE))
        ;
    UART_THR = (uint8_t)c;
}

void debug_init(void)
{
    /* Minimal initialization for NS16550 */
    UART_IER = 0x00; /* Disable interrupts */
    UART_LCR = 0x03; /* 8N1 */
    UART_FCR = 0x07; /* Enable & Clear FIFO */
    UART_MCR = 0x00; /* No modem control */
}
