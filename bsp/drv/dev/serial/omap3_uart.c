/*-
 * Copyright (c) 2009, Kohsuke Ohtani
 * Copyright (c) 2009-2010, Richard Pandion
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
 * omap3_uart.c - OMAP3 integrated UART device driver
 */

#include <driver.h>
#include <tty.h>
#include <serial.h>

/* #define DEBUG_OMAP3_UART 1 */

#ifdef DEBUG_OMAP3_UART
#define DPRINTF(a) printf a
#else
#define DPRINTF(a)
#endif

#define UART_BASE CONFIG_OMAP3_UART_BASE
#define UART_IRQ CONFIG_OMAP3_UART_IRQ

#define UART_CLK 48000000
#define BAUD_RATE 115200

#ifdef CONFIG_MMU
#define INTCPS_ILR(a) (0xa8200100 + (0x04 * a))
#else
#define INTCPS_ILR(a) (0x48200100 + (0x04 * a))
#endif

/* Register offsets UART in OMAP35 SoC */
#define UART_RHR (UART_BASE + 0x00) /* receive buffer register */
#define UART_THR (UART_BASE + 0x00) /* transmit holding register */
#define UART_IER (UART_BASE + 0x04) /* interrupt enable register */
#define UART_FCR (UART_BASE + 0x08) /* FIFO control register */
#define UART_IIR (UART_BASE + 0x08) /* interrupt identification register */
#define UART_LCR (UART_BASE + 0x0C) /* line control register */
#define UART_MCR (UART_BASE + 0x10) /* modem control register */
#define UART_LSR (UART_BASE + 0x14) /* line status register */
#define UART_MSR (UART_BASE + 0x18) /* mode definition register */
#define UART_MDR1 (UART_BASE + 0x20) /* modem status register */
#define UART_DLL (UART_BASE + 0x00) /* divisor latch LSB (LCR[7] = 1) */
#define UART_DLH (UART_BASE + 0x04) /* divisor latch MSB (LCR[7] = 1) */

/* Interrupt enable register */
#define IER_RDA 0x01 /* enable receive data available */
#define IER_THRE 0x02 /* enable transmitter holding register empty */
#define IER_RLS 0x04 /* enable recieve line status */
#define IER_RMS 0x08 /* enable receive modem status */

/* Interrupt identification register */
#define IIR_MSR 0x00 /* modem status change */
#define IIR_IP 0x01 /* 0 when interrupt pending */
#define IIR_TXB 0x02 /* transmitter holding register empty */
#define IIR_RXB 0x04 /* received data available */
#define IIR_LSR 0x06 /* line status change */
#define IIR_RXTO 0x0C /* receive data timeout */
#define IIR_MASK 0x0E /* mask off just the meaningful bits */

/* line status register */
#define LSR_RCV_FIFO 0x80
#define LSR_TSRE 0x40 /* Transmitter empty: byte sent */
#define LSR_TXRDY 0x20 /* Transmitter buffer empty */
#define LSR_BI 0x10 /* Break detected */
#define LSR_FE 0x08 /* Framing error: bad stop bit */
#define LSR_PE 0x04 /* Parity error */
#define LSR_OE 0x02 /* Overrun, lost incoming byte */
#define LSR_RXRDY 0x01 /* Byte ready in Receive Buffer */
#define LSR_RCV_MASK 0x1f /* Mask for incoming data or error */

/* Bit definitions for line control */
#define LCR_BITS_MASK 0x03
#define LCR_STB2 0x04
#define LCR_PEN 0x08
#define LCR_EPS 0x10
#define LCR_SPS 0x20
#define LCR_BREAK 0x40
#define LCR_DLAB 0x80

/* Bit definitions for modem control */
#define MCR_DTR 0x01
#define MCR_RTS 0x02
#define MCR_CDSTSCH 0x08
#define MCR_LOOPBACK 0x10
#define MCR_XON 0x20
#define MCR_TCRTLR 0x40
#define MCR_CLKSEL 0x80

/* Bit definitions for fifo control register  */
#define FCR_ENABLE 0x01
#define FCR_RXCLR 0x02
#define FCR_TXCLR 0x04
#define FCR_DMA 0x08

/* Mode settings for mode definition register 1  */
#define MDR1_ENABLE 0x00
#define MDR1_AUTOBAUD 0x02
#define MDR1_DISABLE 0x07

/* Forward functions */
static void omap3_uart_xmt_char(struct serial_port*, char);
static char omap3_uart_rcv_char(struct serial_port*);
static void omap3_uart_set_poll(struct serial_port*, int);
static int omap3_uart_isr(void*);
static void omap3_uart_start(struct serial_port*);
static void omap3_uart_stop(struct serial_port*);
static int omap3_uart_init(struct driver*);

struct driver omap3_uart_driver = {
    /* name */ "omap3_uart",
    /* devops */ NULL,
    /* devsz */ 0,
    /* flags */ 0,
    /* probe */ NULL,
    /* init */ omap3_uart_init,
    /* unload */ NULL,
};

static struct serial_ops omap3_uart_ops = {
    /* xmt_char */ omap3_uart_xmt_char,
    /* rcv_char */ omap3_uart_rcv_char,
    /* set_poll */ omap3_uart_set_poll,
    /* start */ omap3_uart_start,
    /* stop */ omap3_uart_stop,
};

static struct serial_port omap3_uart_port;

static void
omap3_uart_xmt_char(struct serial_port* sp, char c)
{
    struct tty* tp = sp->tty;
    struct tty_queue* tq = &tp->t_outq;

#define ttyq_empty(q) ((q)->tq_count == 0)

    while (!(bus_read_16(UART_LSR) & LSR_TXRDY))
        ;
    bus_write_16(UART_THR, (uint32_t)c);

    if (ttyq_empty(tq))
        serial_xmt_done(sp);
}

static char
omap3_uart_rcv_char(struct serial_port* sp)
{
    char c;

    while (!(bus_read_16(UART_LSR) & LSR_RXRDY))
        ;
    c = bus_read_16(UART_RHR) & 0xff;
    return c;
}

static void
omap3_uart_set_poll(struct serial_port* sp, int on)
{

    if (on) {
        /* Disable interrupt for polling mode. */
        bus_write_16(UART_IER, 0x00);
    } else {
        /* enable interrupt again */
        bus_write_16(UART_IER, IER_RDA | IER_RLS);
    }
}

static int
omap3_uart_isr(void* arg)
{
    struct serial_port* sp = arg;
    char c;

    switch (bus_read_16(UART_IIR) & IIR_MASK) {
    case IIR_LSR: /* Line status change */
        if (bus_read_16(UART_LSR) & (LSR_BI | LSR_FE | LSR_PE | LSR_OE)) {
            /*
		 	 * Status error
		 	 * Read whatever happens to be in the buffer to "eat" the
		 	 * spurious data associated with break, parity error, etc.
		 	*/
            bus_read_16(UART_RHR);
        }
        /* Read LSR again to clear interrupt */
        bus_read_16(UART_LSR);
        break;
    case IIR_RXTO: /* Receive data timeout */
        /*
		 	 * "Eat" the spurious data (same as above).
		 	 *  This also clears the interrupt. 
		 	*/
        bus_read_16(UART_RHR);
        break;
    case IIR_RXB: /* Received data available */
        c = bus_read_16(UART_RHR) & 0xff; /* Read pending data */
        serial_rcv_char(sp, c);
        break;
    case IIR_TXB: /* Transmitter holding register empty */
        bus_read_16(UART_IIR); /* Clear interrupt */
        serial_xmt_done(sp);
        break;
    default:
        break;
    }
    return 0;
}

static void
omap3_uart_start(struct serial_port* sp)
{
    int baud_divisor = UART_CLK / 16 / BAUD_RATE;

    bus_write_16(UART_IER, 0x00);
    bus_write_16(UART_MDR1, MDR1_DISABLE);
    bus_write_16(UART_LCR, LCR_DLAB | LCR_BITS_MASK);
    bus_write_16(UART_DLL, baud_divisor & 0xff);
    bus_write_16(UART_DLH, (baud_divisor >> 8) & 0xff);
    bus_write_16(UART_LCR, LCR_BITS_MASK);
    bus_write_16(UART_MCR, MCR_DTR | MCR_RTS);
    bus_write_16(UART_FCR, FCR_RXCLR | FCR_TXCLR);
    bus_write_16(UART_MDR1, MDR1_ENABLE);

    DPRINTF(("Installing UART IRQ\n"));

    /* Install interrupt handler */
    sp->irq = irq_attach(UART_IRQ, IPL_COMM, 0, omap3_uart_isr,
        IST_NONE, sp);

    /* Enable interrupts */
    bus_write_32(INTCPS_ILR(UART_IRQ), ((NIPLS - IPL_COMM) << 2));
    bus_write_16(UART_IER, IER_RDA | IER_RLS);
    DPRINTF(("UART interrupt enabled\n"));
}

static void
omap3_uart_stop(struct serial_port* sp)
{

    /* Disable interrupts */
    bus_write_16(UART_IER, 0x00);
    /* Disable UART */
    bus_write_16(UART_MDR1, MDR1_DISABLE);
}

static int
omap3_uart_init(struct driver* self)
{

    serial_attach(&omap3_uart_ops, &omap3_uart_port);
    return 0;
}
