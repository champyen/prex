/*-
 * Copyright (c) 2017 Jared McNeill <jmcneill@invisible.ca>
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
 * bcm2835_sd.c - Broadcom BCM2835 SDHost controller
 */

#include <driver.h>
#include <sdmmc.h>

#define DEBUG_SDHOST 0

#if DEBUG_SDHOST
#define DPRINTF(a) printf a
#else
#define DPRINTF(a)
#endif

#define SD_BASE CONFIG_BCM2835_SD_BASE
#define SD_IRQ  CONFIG_BCM2835_SD_IRQ

#define SDCMD		(SD_BASE + 0x00)
#define	 SDCMD_NEW	(1 << 15)
#define	 SDCMD_FAIL	(1 << 14)
#define	 SDCMD_BUSY	(1 << 11)
#define	 SDCMD_NORESP	(1 << 10)
#define	 SDCMD_LONGRESP	(1 << 9)
#define	 SDCMD_WRITE	(1 << 7)
#define	 SDCMD_READ	(1 << 6)

#define SDARG		(SD_BASE + 0x04)

#define SDTOUT		(SD_BASE + 0x08)
#define	 SDTOUT_DEFAULT	0xf00000

#define SDCDIV		(SD_BASE + 0x0c)
#define	 SDCDIV_MASK	0x7ff

#define SDRSP0		(SD_BASE + 0x10)
#define SDRSP1		(SD_BASE + 0x14)
#define SDRSP2		(SD_BASE + 0x18)
#define SDRSP3		(SD_BASE + 0x1c)

#define SDHSTS		(SD_BASE + 0x20)
#define	 SDHSTS_BUSY	(1 << 10)
#define	 SDHSTS_BLOCK	(1 << 9)
#define	 SDHSTS_SDIO	(1 << 8)
#define	 SDHSTS_REW_TO	(1 << 7)
#define	 SDHSTS_CMD_TO	(1 << 6)
#define	 SDHSTS_CRC16_E	(1 << 5)
#define	 SDHSTS_CRC7_E	(1 << 4)
#define	 SDHSTS_FIFO_E	(1 << 3)
#define	 SDHSTS_DATA	(1 << 0)

#define SDVDD		(SD_BASE + 0x30)
#define	 SDVDD_POWER	(1 << 0)

#define SDEDM		(SD_BASE + 0x34)
#define	 SDEDM_RD_FIFO	(0x1f << 14)
#define	 SDEDM_WR_FIFO	(0x1f << 9)

#define SDHCFG		(SD_BASE + 0x38)
#define	 SDHCFG_BUSY_EN	(1 << 10)
#define	 SDHCFG_BLOCK_EN (1 << 8)
#define	 SDHCFG_SDIO_EN	(1 << 5)
#define	 SDHCFG_DATA_EN	(1 << 4)
#define	 SDHCFG_SLOW	(1 << 3)
#define	 SDHCFG_WIDE_EXT (1 << 2)
#define	 SDHCFG_WIDE_INT (1 << 1)
#define	 SDHCFG_REL_CMD	(1 << 0)

#define SDHBCT		(SD_BASE + 0x3c)
#define SDDATA		(SD_BASE + 0x40)
#define SDHBLC		(SD_BASE + 0x50)

#define GPIO_BASE   CONFIG_GPIO_BASE
#define GPFSEL4     (GPIO_BASE + 0x10)
#define GPFSEL5     (GPIO_BASE + 0x14)

static int bcm_sd_init(struct driver*);
static int bcm_sd_sendcmd(uint8_t cmd, uint32_t arg, uint8_t rsp_type, uint8_t* rspbuf);
static int bcm_sd_setfreq(uint32_t idx);
static int bcm_sd_setwidth(uint32_t bits);
static int bcm_sd_xmit(struct sdmmc_devinfo* info, char* buf, size_t nbyte);
static int bcm_sd_recv(struct sdmmc_devinfo* info, char* buf, size_t nbyte);

struct driver bcm2835_sd_driver = {
    /* name */ "bcm2835_sd",
    /* devops */ NULL,
    /* devsz */ 0,
    /* flags */ 0,
    /* probe */ NULL,
    /* init */ bcm_sd_init,
    /* shutdown */ NULL,
};

static struct sdmmc_ops bcm_sd_ops = {
    /* sendcmd */ bcm_sd_sendcmd,
    /* ioctl */ NULL,
    /* setfreq */ bcm_sd_setfreq,
    /* setwidth */ bcm_sd_setwidth,
    /* xmit */ bcm_sd_xmit,
    /* recv */ bcm_sd_recv,
};

static struct sdmmc_devinfo bcm_sd_info;
static char* bcm_sd_part_names[] = {"sdmmc0p1", "sdmmc0p2", "sdmmc0p3", "sdmmc0p4"};
static uint32_t bcm_sd_freq_tab[] = {400, 10000, 20000, 25000};
static uint32_t bcm_sd_hcfg = 0;

/* Reference frequency for RPi0 is typically 250MHz for SDHost?
 * NetBSD driver gets it from FDT. For RPi it's usually around 250MHz.
 */
static uint32_t bcm_sd_ref_clk = 250000000;

static int bcm_sd_wait_idle(void)
{
    int i;
    for (i = 0; i < 1000000; i++) {
        if (!(bus_read_32(SDCMD) & SDCMD_NEW))
            return 0;
        delay_usec(1);
    }
    return ETIMEDOUT;
}

static int bcm_sd_sendcmd(uint8_t cmd, uint32_t arg, uint8_t rsp_type, uint8_t* rspbuf)
{
    uint32_t cmdval = SDCMD_NEW | (cmd & 0x3f);
    int error;

    DPRINTF(("bcm_sd_sendcmd: cmd=%d arg=%x rsp_type=%d\n", cmd, arg, rsp_type));

    bus_write_32(SDHCFG, bcm_sd_hcfg | SDHCFG_BUSY_EN);

    /* Clear status */
    bus_write_32(SDHSTS, 0x7ff);

    if (bcm_sd_wait_idle() != 0) {
        DPRINTF(("bcm_sd_sendcmd: device busy\n"));
        return EBUSY;
    }

    if (rsp_type == RSP_NONE) // No response? sdmmc.h defines enum starting from RSP_R1=0
        cmdval |= SDCMD_NORESP;

    if (rsp_type == RSP_R2)
        cmdval |= SDCMD_LONGRESP;

    if (rsp_type == RSP_R1B)
        cmdval |= SDCMD_BUSY;

    if (cmd == CMD17 || cmd == CMD18 || cmd == CMD24 || cmd == CMD25) {
        if (cmd == CMD17 || cmd == CMD18)
            cmdval |= SDCMD_READ;
        else
            cmdval |= SDCMD_WRITE;

        bus_write_32(SDHBCT, 512); // Block size
        bus_write_32(SDHBLC, 1);   // Block count (Prex usually does 1 by 1)
    } else {
        bus_write_32(SDHBCT, 0);
        bus_write_32(SDHBLC, 0);
    }

    bus_write_32(SDARG, arg);
    bus_write_32(SDCMD, cmdval);

    error = bcm_sd_wait_idle();
    if (error != 0) {
        DPRINTF(("bcm_sd_sendcmd: wait idle timeout\n"));
        return error;
    }

    if (bus_read_32(SDCMD) & SDCMD_FAIL) {
        DPRINTF(("bcm_sd_sendcmd: command failed\n"));
        return EIO;
    }

    if (rspbuf) {
        if (rsp_type == RSP_R2) {
            /* SDHost responses are MSB first in SDRSP0-3?
             * NetBSD reads them into c_resp[0-3].
             */
            uint32_t r0 = bus_read_32(SDRSP0);
            uint32_t r1 = bus_read_32(SDRSP1);
            uint32_t r2 = bus_read_32(SDRSP2);
            uint32_t r3 = bus_read_32(SDRSP3);

            /* Prex expects big endian order in byte array for R2 (CID/CSD) */
            rspbuf[0] = (r3 >> 24) & 0xff; rspbuf[1] = (r3 >> 16) & 0xff;
            rspbuf[2] = (r3 >> 8) & 0xff;  rspbuf[3] = r3 & 0xff;
            rspbuf[4] = (r2 >> 24) & 0xff; rspbuf[5] = (r2 >> 16) & 0xff;
            rspbuf[6] = (r2 >> 8) & 0xff;  rspbuf[7] = r2 & 0xff;
            rspbuf[8] = (r1 >> 24) & 0xff; rspbuf[9] = (r1 >> 16) & 0xff;
            rspbuf[10] = (r1 >> 8) & 0xff; rspbuf[11] = r1 & 0xff;
            rspbuf[12] = (r0 >> 24) & 0xff; rspbuf[13] = (r0 >> 16) & 0xff;
            rspbuf[14] = (r0 >> 8) & 0xff; rspbuf[15] = r0 & 0xff;
        } else {
            uint32_t r = bus_read_32(SDRSP0);
            rspbuf[0] = (r >> 24) & 0xff;
            rspbuf[1] = (r >> 16) & 0xff;
            rspbuf[2] = (r >> 8) & 0xff;
            rspbuf[3] = r & 0xff;
        }
    }

    bus_write_32(SDHCFG, bcm_sd_hcfg);

    return 0;
}

static int bcm_sd_setfreq(uint32_t idx)
{
    uint32_t div;
    uint32_t freq;

    if (idx >= 4)
        idx = 3;
    freq = bcm_sd_freq_tab[idx] * 1000;

    if (freq == 0)
        div = SDCDIV_MASK;
    else {
        div = bcm_sd_ref_clk / freq;
        if (div < 2)
            div = 2;
        if ((bcm_sd_ref_clk / div) > freq)
            div++;
        div -= 2;
        if (div > SDCDIV_MASK)
            div = SDCDIV_MASK;
    }

    bus_write_32(SDCDIV, div);
    return 0;
}

static int bcm_sd_setwidth(uint32_t bits)
{
    if (bits == 4)
        bcm_sd_hcfg |= SDHCFG_WIDE_EXT;
    else
        bcm_sd_hcfg &= ~SDHCFG_WIDE_EXT;
    bcm_sd_hcfg |= (SDHCFG_WIDE_INT | SDHCFG_SLOW);
    bus_write_32(SDHCFG, bcm_sd_hcfg);
    return 0;
}

static int bcm_sd_xmit(struct sdmmc_devinfo* info, char* buf, size_t nbyte)
{
    uint32_t* p = (uint32_t*)buf;
    int count = nbyte / 4;
    int retry;

    while (count > 0) {
        retry = 1000000;
        while (((bus_read_32(SDEDM) >> 4) & 0x1f) >= 16 && --retry > 0)
            delay_usec(1);
        if (retry == 0) {
            return ETIMEDOUT;
        }
        bus_write_32(SDDATA, *p++);
        count--;
    }

    /* Wait for transfer end */
    retry = 1000000;
    while (!(bus_read_32(SDHSTS) & SDHSTS_BLOCK) && --retry > 0)
        delay_usec(1);

    return 0;
}

static int bcm_sd_recv(struct sdmmc_devinfo* info, char* buf, size_t nbyte)
{
    uint32_t* p = (uint32_t*)buf;
    int count = nbyte / 4;
    int retry = 10000000;

    while (count > 0 && --retry > 0) {
        if (bus_read_32(SDHSTS) & SDHSTS_DATA) {
            *p++ = bus_read_32(SDDATA);
            count--;
        } else {
            /* trigger refill in QEMU */
            bus_write_32(SDHCFG, bcm_sd_hcfg);
        }
    }
    if (retry == 0) {
        return ETIMEDOUT;
    }

    /* Wait for transfer end */
    retry = 1000000;
    while (!(bus_read_32(SDHSTS) & SDHSTS_BLOCK) && --retry > 0)
        ;
    return 0;
}

static int bcm_sd_init(struct driver* self)
{
    uint32_t edm, val;

    DPRINTF(("bcm_sd_init\n"));
    /* GPIO 48~53 to ALTO (100) */
    val = bus_read_32(GPFSEL4);
    val &= ~(7 << 24); val |= (4 << 24);    /* GPIO 48 */
    val &= ~(7 << 27); val |= (4 << 27);    /* GPIO 49 */
    bus_write_32(GPFSEL4, val);

    val = bus_read_32(GPFSEL5);
    val &= ~(7 << 0); val |= (4 << 0);      /* GPIO 50 */
    val &= ~(7 << 3); val |= (4 << 3);      /* GPIO 51 */
    val &= ~(7 << 6); val |= (4 << 6);      /* GPIO 52 */
    val &= ~(7 << 9); val |= (4 << 9);      /* GPIO 32 */
    bus_write_32(GPFSEL5, val);

    /* Reset host */
    bus_write_32(SDVDD, 0);
    delay_usec(20000);
    bus_write_32(SDVDD, SDVDD_POWER);
    delay_usec(100000);

    bus_write_32(SDCMD, 0);
    bus_write_32(SDARG, 0);
    bus_write_32(SDTOUT, SDTOUT_DEFAULT);
    bus_write_32(SDCDIV, 0);
    bus_write_32(SDHSTS, 0x7ff);
    bus_write_32(SDHCFG, 0);
    bus_write_32(SDHBCT, 0);
    bus_write_32(SDHBLC, 0);

    edm = bus_read_32(SDEDM);
    edm &= ~(SDEDM_RD_FIFO | SDEDM_WR_FIFO | 0xf);
    edm |= (4 << 14); // SDEDM_RD_FIFO threshold
    edm |= (4 << 9);  // SDEDM_WR_FIFO threshold
    bus_write_32(SDEDM, edm);
    delay_usec(20000);

    bcm_sd_hcfg = SDHCFG_WIDE_INT | SDHCFG_SLOW | SDHCFG_DATA_EN | SDHCFG_BLOCK_EN;
    bus_write_32(SDHCFG, bcm_sd_hcfg);
    bus_write_32(SDCDIV, SDCDIV_MASK);
    bus_write_32(SDHSTS, 0x7ff);

    bcm_sd_info.dev_name = "sdmmc0";
    bcm_sd_info.part_dev_name = bcm_sd_part_names;
    bcm_sd_info.blk_size = 512;
    bcm_sd_info.data_bits = 1;
    bcm_sd_info.freq_levels = 4;
    bcm_sd_info.freq_tab = bcm_sd_freq_tab;

    /* Initialize clock to identification frequency */
    bcm_sd_setfreq(0);

    device_t dev = sdmmc_attach(&bcm_sd_ops, &bcm_sd_info);
    if (dev != 0) {
        sdmmc_insert(dev);
    }

    return 0;
}
