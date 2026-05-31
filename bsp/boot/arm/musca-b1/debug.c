/*-
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
 * All rights reserved.
 */

#include <sys/param.h>
#include <boot.h>

#define UART_BASE CONFIG_PL011_PHY_BASE
#define UART_DR (*(volatile uint32_t*)(UART_BASE + 0x00))
#define UART_FR (*(volatile uint32_t*)(UART_BASE + 0x18))
#define FR_TXFF 0x20

void debug_putc(int c)
{
    while (UART_FR & FR_TXFF);
    UART_DR = c;
}

void debug_init(void)
{
}
