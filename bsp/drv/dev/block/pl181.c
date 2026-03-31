/*-
 * Copyright (c) 2015 Jared D. McNeill <jmcneill@invisible.ca>
 * Copyright (c) 2026 Champ Yen <champ.yen@gmail.com>
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
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
 * AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

/*
 * pl181.c - ARM PrimeCell PL181 MMCI
 */

#include <driver.h>
#include <sdmmc.h>

#define DEBUG_PL181 0

#if DEBUG_PL181
#define DPRINTF(a) printf a
#else
#define DPRINTF(a)
#endif

#define MMCI_BASE CONFIG_PL181_BASE
#define MMCI_IRQ CONFIG_PL181_IRQ
#define MMCI_CLK CONFIG_PL181_CLK

#define MMCI_POWER_REG (MMCI_BASE + 0x000)
#define MMCI_CLOCK_REG (MMCI_BASE + 0x004)
#define MMCI_ARGUMENT_REG (MMCI_BASE + 0x008)
#define MMCI_COMMAND_REG (MMCI_BASE + 0x00c)
#define MMCI_RESP_CMD_REG (MMCI_BASE + 0x010)
#define MMCI_RESP0_REG (MMCI_BASE + 0x014)
#define MMCI_RESP1_REG (MMCI_BASE + 0x018)
#define MMCI_RESP2_REG (MMCI_BASE + 0x01c)
#define MMCI_RESP3_REG (MMCI_BASE + 0x020)
#define MMCI_DATA_TIMER_REG (MMCI_BASE + 0x024)
#define MMCI_DATA_LENGTH_REG (MMCI_BASE + 0x028)
#define MMCI_DATA_CTRL_REG (MMCI_BASE + 0x02c)
#define MMCI_DATA_CNT_REG (MMCI_BASE + 0x030)
#define MMCI_STATUS_REG (MMCI_BASE + 0x034)
#define MMCI_CLEAR_REG (MMCI_BASE + 0x038)
#define MMCI_MASK0_REG (MMCI_BASE + 0x03c)
#define MMCI_MASK1_REG (MMCI_BASE + 0x040)
#define MMCI_FIFO_CNT_REG (MMCI_BASE + 0x048)
#define MMCI_FIFO_REG (MMCI_BASE + 0x080)

#define MMCI_POWER_CTRL_OFF 0
#define MMCI_POWER_CTRL_POWERUP 2
#define MMCI_POWER_CTRL_POWERON 3
#define MMCI_POWER_ROD 0x80

#define MMCI_CLOCK_ENABLE 0x100
#define MMCI_CLOCK_PWRSAVE 0x200
#define MMCI_CLOCK_BYPASS 0x400

#define MMCI_COMMAND_RESPONSE 0x040
#define MMCI_COMMAND_LONGRSP 0x080
#define MMCI_COMMAND_INTERRUPT 0x100
#define MMCI_COMMAND_PENDING 0x200
#define MMCI_COMMAND_ENABLE 0x400

#define MMCI_DATA_CTRL_ENABLE 0x01
#define MMCI_DATA_CTRL_DIRECTION 0x02
#define MMCI_DATA_CTRL_MODE 0x04
#define MMCI_DATA_CTRL_DMAENABLE 0x08

#define MMCI_INT_CMD_CRC_FAIL 0x00000001
#define MMCI_INT_DATA_CRC_FAIL 0x00000002
#define MMCI_INT_CMD_TIMEOUT 0x00000004
#define MMCI_INT_DATA_TIMEOUT 0x00000008
#define MMCI_INT_TX_UNDERRUN 0x00000010
#define MMCI_INT_RX_OVERRUN 0x00000020
#define MMCI_INT_CMD_RESP_END 0x00000040
#define MMCI_INT_CMD_SENT 0x00000080
#define MMCI_INT_DATA_END 0x00000100
#define MMCI_INT_DATA_BLOCK_END 0x00000400
#define MMCI_INT_CMD_ACTIVE 0x00000800
#define MMCI_INT_TX_ACTIVE 0x00001000
#define MMCI_INT_RX_ACTIVE 0x00002000
#define MMCI_INT_TX_FIFO_HALF_EMPTY 0x00004000
#define MMCI_INT_RX_FIFO_HALF_FULL 0x00008000
#define MMCI_INT_TX_FIFO_FULL 0x00010000
#define MMCI_INT_RX_FIFO_FULL 0x00020000
#define MMCI_INT_TX_FIFO_EMPTY 0x00040000
#define MMCI_INT_RX_FIFO_EMPTY 0x00080000
#define MMCI_INT_TX_DATA_AVAIL 0x00100000
#define MMCI_INT_RX_DATA_AVAIL 0x00200000

#define PL181_FIFO_DEPTH 64

static int pl181_init(struct driver*);
static int pl181_sendcmd(uint8_t cmd, uint32_t arg, uint8_t rsp_type, uint8_t* rspbuf);
static int pl181_setfreq(uint32_t idx);
static int pl181_setwidth(uint32_t bits);
static int pl181_xmit(struct sdmmc_devinfo* info, char* buf, size_t nbyte);
static int pl181_recv(struct sdmmc_devinfo* info, char* buf, size_t nbyte);

struct driver pl181_driver = {
    /* name */ "pl181",
    /* devops */ NULL,
    /* devsz */ 0,
    /* flags */ 0,
    /* probe */ NULL,
    /* init */ pl181_init,
    /* shutdown */ NULL,
};

static struct sdmmc_ops pl181_ops = {
    /* sendcmd */ pl181_sendcmd,
    /* ioctl */ NULL,
    /* setfreq */ pl181_setfreq,
    /* setwidth */ pl181_setwidth,
    /* xmit */ pl181_xmit,
    /* recv */ pl181_recv,
};

static struct sdmmc_devinfo pl181_info;
static char* pl181_part_names[] = {"sdmmc0p1", "sdmmc0p2", "sdmmc0p3", "sdmmc0p4"};
static uint32_t pl181_freq_tab[] = {400, 10000, 20000, 24000};

static int pl181_sendcmd(uint8_t cmd, uint32_t arg, uint8_t rsp_type, uint8_t* rspbuf)
{
    uint32_t cmdval = MMCI_COMMAND_ENABLE | (cmd & 0x3f);
    uint32_t status;
    int i;

    DPRINTF(("pl181_sendcmd: cmd=%d arg=%x rsp_type=%d\n", cmd, arg, rsp_type));

    /* Clear interrupts */
    bus_write_32(MMCI_CLEAR_REG, 0xffffffff);

    if (rsp_type != RSP_R1 && rsp_type != RSP_R2 && rsp_type != RSP_R3 && rsp_type != RSP_R4 && rsp_type != RSP_R5 &&
        rsp_type != RSP_R6) {
        /* No response expected? */
    } else {
        cmdval |= MMCI_COMMAND_RESPONSE;
        if (rsp_type == RSP_R2)
            cmdval |= MMCI_COMMAND_LONGRSP;
    }

    /* Handle data transfer setup if needed */
    if (cmd == CMD17 || cmd == CMD18 || cmd == CMD24 || cmd == CMD25) {
        uint32_t datactrl = MMCI_DATA_CTRL_ENABLE;
        if (cmd == CMD17 || cmd == CMD18)
            datactrl |= MMCI_DATA_CTRL_DIRECTION;

        bus_write_32(MMCI_DATA_TIMER_REG, 0xffffffff);
        bus_write_32(MMCI_DATA_LENGTH_REG, 512); // Prex uses 512 byte blocks
        bus_write_32(MMCI_DATA_CTRL_REG, datactrl | (9 << 4)); // 2^9 = 512
    }

    bus_write_32(MMCI_ARGUMENT_REG, arg);
    bus_write_32(MMCI_COMMAND_REG, cmdval);

    /* Wait for response or timeout */
    for (i = 0; i < 1000000; i++) {
        status = bus_read_32(MMCI_STATUS_REG);
        if (status & (MMCI_INT_CMD_RESP_END | MMCI_INT_CMD_SENT | MMCI_INT_CMD_TIMEOUT | MMCI_INT_CMD_CRC_FAIL))
            break;
    }

    if (status & (MMCI_INT_CMD_TIMEOUT)) {
        DPRINTF(("pl181_sendcmd: timeout status=%lx\n", (long)status));
        return ETIMEDOUT;
    }

    if ((status & MMCI_INT_CMD_CRC_FAIL) && (rsp_type != RSP_R3)) {
        DPRINTF(("pl181_sendcmd: crc fail status=%lx\n", (long)status));
        return EIO;
    }

    if (rspbuf) {
        if (rsp_type == RSP_R2) {
            uint32_t r;
            r = bus_read_32(MMCI_RESP0_REG);
            rspbuf[15] = r & 0xff;
            rspbuf[14] = (r >> 8) & 0xff;
            rspbuf[13] = (r >> 16) & 0xff;
            rspbuf[12] = (r >> 24) & 0xff;
            r = bus_read_32(MMCI_RESP1_REG);
            rspbuf[11] = r & 0xff;
            rspbuf[10] = (r >> 8) & 0xff;
            rspbuf[9] = (r >> 16) & 0xff;
            rspbuf[8] = (r >> 24) & 0xff;
            r = bus_read_32(MMCI_RESP2_REG);
            rspbuf[7] = r & 0xff;
            rspbuf[6] = (r >> 8) & 0xff;
            rspbuf[5] = (r >> 16) & 0xff;
            rspbuf[4] = (r >> 24) & 0xff;
            r = bus_read_32(MMCI_RESP3_REG);
            rspbuf[3] = r & 0xff;
            rspbuf[2] = (r >> 8) & 0xff;
            rspbuf[1] = (r >> 16) & 0xff;
            rspbuf[0] = (r >> 24) & 0xff;
        } else {
            uint32_t r = bus_read_32(MMCI_RESP0_REG);
            DPRINTF(("pl181_sendcmd: resp0=%lx\n", (long)r));
            rspbuf[0] = (r >> 24) & 0xff;
            rspbuf[1] = (r >> 16) & 0xff;
            rspbuf[2] = (r >> 8) & 0xff;
            rspbuf[3] = r & 0xff;
        }
    }

    return 0;
}

static int pl181_setfreq(uint32_t idx)
{
    uint32_t clk_div = 0;
    uint32_t clock = MMCI_CLOCK_ENABLE;
    uint32_t freq;

    if (idx >= 4)
        idx = 3;
    freq = pl181_freq_tab[idx];

    /*
     * clk_div = (MMCI_CLK / (2 * freq)) - 1
     */
    clk_div = (MMCI_CLK / (2 * freq * 1000));
    if (clk_div > 0)
        clk_div--;

    if (clk_div > 0xff)
        clk_div = 0xff;

    bus_write_32(MMCI_CLOCK_REG, clock | (clk_div & 0xff));
    return 0;
}

static int pl181_setwidth(uint32_t bits)
{
    /* PL181 on Integrator CP might not support 4-bit?
     * NetBSD driver returns 0 (success) but does nothing.
     */
    return 0;
}

static int pl181_xmit(struct sdmmc_devinfo* info, char* buf, size_t nbyte)
{
    uint32_t* p = (uint32_t*)buf;
    int count = nbyte / 4;
    uint32_t status;

    while (count > 0) {
        status = bus_read_32(MMCI_STATUS_REG);
        if (status & MMCI_INT_TX_FIFO_HALF_EMPTY) {
            int chunks = 8; // FIFO is 16 words, half is 8
            if (chunks > count)
                chunks = count;
            count -= chunks;
            while (chunks--) {
                bus_write_32(MMCI_FIFO_REG, *p++);
            }
        }
    }

    /* Wait for data end */
    while (!(bus_read_32(MMCI_STATUS_REG) & MMCI_INT_DATA_END))
        ;

    return 0;
}

static int pl181_recv(struct sdmmc_devinfo* info, char* buf, size_t nbyte)
{
    uint32_t* p = (uint32_t*)buf;
    int count = nbyte / 4;
    uint32_t status;

    while (count > 0) {
        status = bus_read_32(MMCI_STATUS_REG);
        if (status & (MMCI_INT_RX_FIFO_HALF_FULL | MMCI_INT_DATA_END)) {
            while (count > 0 && !(bus_read_32(MMCI_STATUS_REG) & MMCI_INT_RX_FIFO_EMPTY)) {
                *p++ = bus_read_32(MMCI_FIFO_REG);
                count--;
            }
        }
        if (status & (MMCI_INT_DATA_TIMEOUT | MMCI_INT_DATA_CRC_FAIL))
            return EIO;
    }

    return 0;
}

static int pl181_init(struct driver* self)
{
    DPRINTF(("pl181_init\n"));

    /* Power up MMCI */
    bus_write_32(MMCI_POWER_REG, MMCI_POWER_CTRL_POWERUP);
    delay_usec(10000);
    bus_write_32(MMCI_POWER_REG, MMCI_POWER_CTRL_POWERON);
    delay_usec(10000);

    pl181_info.dev_name = "sdmmc0";
    pl181_info.part_dev_name = pl181_part_names;
    pl181_info.blk_size = 512;
    pl181_info.data_bits = 1;
    pl181_info.freq_levels = 4;
    pl181_info.freq_tab = pl181_freq_tab;

    /* Initialize clock to identification frequency */
    pl181_setfreq(0);

    device_t dev = sdmmc_attach(&pl181_ops, &pl181_info);
    if (dev != 0) {
        sdmmc_insert(dev);
    }

    return 0;
}
