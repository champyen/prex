/*-
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
 * All rights reserved.
 */

#include <sys/bootinfo.h>
#include <kernel.h>
#include <cpufunc.h>

#define UART_BASE CONFIG_PL011_BASE
#define UART_FR (*(volatile uint32_t*)(UART_BASE + 0x18))
#define UART_DR (*(volatile uint32_t*)(UART_BASE + 0x00))
#define FR_TXFF 0x20

int hal_uart_lock(void) { return 0; }
void hal_uart_unlock(int s) {}

static void serial_putc(char c)
{
    while (UART_FR & FR_TXFF);
    UART_DR = (uint32_t)c;
}

void diag_puts(char* buf)
{
    while (*buf) {
        if (*buf == '\n') serial_putc('\r');
        serial_putc(*buf++);
    }
}

void diag_init(void)
{
    diag_puts("UART initialized (Musca-B1)\n");
}
