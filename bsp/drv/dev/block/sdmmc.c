/*
 * Copyright (c) 2010-2021, Champ Yen (champ.yen@gmail.com)
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
 * sdmmc.c - SD/MMC card protocol
 */

#include <driver.h>
#include <sdmmc.h>

#define DEBUG_SDMMC 1

#ifdef DEBUG_SDMMC
#define DPRINTF(a) printf a
#else
#define DPRINTF(a)
#endif

/* Block size */
#define BSIZE 512

/* enable 4BIT bus */
#define USE_4BIT 1
#define MAX_DEV 4

struct sdmmc_dev_softc
{
    device_t dev; /* device object */
    uint32_t offset;
    struct sdmmc_ops* ops;
    struct sdmmc_devinfo* info;
};

static int sdmmc_open(device_t, int);
static int sdmmc_close(device_t);
static int sdmmc_read(device_t, char*, size_t*, int);
static int sdmmc_write(device_t, char*, size_t*, int);
static int sdmmc_ioctl(device_t, u_long, void*);

static int sdmmc_probe(struct driver*);
static int sdmmc_init(struct driver*);

static struct devops sdmmc_devops = {
    /* open */ no_open,
    /* close */ no_close,
    /* read */ sdmmc_read,
    /* write */ sdmmc_write,
    /* ioctl */ no_ioctl, // sdmmc_ioctl,
    /* devctl */ no_devctl,
};

struct driver sdmmc_driver __driver_entry = {
    /* name */ "sdmmc",
    /* devops */ NULL,
    /* devsz */ 0,
    /* flags */ 0,
    /* probe */ NULL,
    /* init */ sdmmc_init,
    /* shutdown */ NULL,
};

struct driver sdmmc_dev_driver __driver_entry = {
    /* name */ NULL,
    /* devops */ &sdmmc_devops,
    /* devsz */ sizeof(struct sdmmc_dev_softc),
    /* flags */ 0,
    /* probe */ NULL,
    /* init */ sdmmc_init,
    /* shutdown */ NULL,
};

struct driver* sdmmc_drv_list[MAX_DEV];
static timer_t sdmmc_timer;
static uint32_t sdmmc_freq_tab[] = {0, 10, 12, 13, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 70, 80};
static uint32_t sdmmc_freq_factor[] = {10, 100, 1000, 10000}; /* unit in 1000Hz/10 */

static int sdmmc_wait_ready(struct sdmmc_ops* ops, struct sdmmc_devinfo* info)
{
    uint8_t* resp;

    resp = info->resp;

    /* TODO: timeout */
    do {
        uint32_t err;
        err = ops->sendcmd(CMD13, info->card_rca << 16, RSP_R1, resp);
        if (err != 0)
            return -1;
    } while ((resp[2] & 0x1E) != 0x08);

    return 0;
}

static int sdmmc_read(device_t dev, char* buf, size_t* nbyte, int sect_addr)
{

    uint32_t sectors, offset, part_idx;
    uint32_t addr, err;
    uint8_t cmd;
    uint8_t* resp;
    char* kbuf;

    struct sdmmc_dev_softc* sc;
    struct sdmmc_ops* ops;
    struct sdmmc_devinfo* info;

    // DPRINTF(("%s sz=%d sect_addr=%d\n",__func__, *nbyte, sect_addr));

    /* Translate buffer address to kernel address */
    if ((kbuf = kmem_map(buf, *nbyte)) == NULL)
        return EFAULT;

    sc = device_private(dev);
    ops = sc->ops;
    info = sc->info;
    resp = info->resp;
    if (dev != info->dev) {
        /* partition device */
        for (part_idx = 0; part_idx < MAX_PARTI; part_idx++) {
            if (info->part_dev[part_idx] == dev) {
                break;
            }
            if (part_idx == (MAX_PARTI - 1)) {
                DPRINTF(("[%s] invalid device\n", __func__));
                return -1;
            }
        }
        if (sect_addr > info->part_info[part_idx].size) {
            DPRINTF(("[%s] part %d read out of range\n", __func__, part_idx));
            return -1;
        }
        sect_addr += info->part_info[part_idx].start;
    }

    if (sdmmc_wait_ready(ops, info) != 0) {
        DPRINTF(("%s wait ready fail\n", __func__));
        *nbyte = 0;
        return -1;
    }

    if (!(info->sdmmc_type & BLK_ADDR))
        sect_addr *= 512;

    sectors = (*nbyte) / 512;
    cmd = (sectors > 1) ? CMD18 : CMD17;

    err = ops->sendcmd(cmd, sect_addr, RSP_R1, resp);
    if (err != 0 || (resp[0] & 0xC0) || (resp[1] & 0x58)) {
        DPRINTF(("[%s] resp error\n", __func__));
        *nbyte = 0;
        return -1;
    }

    do {
        err = ops->recv(info, kbuf, BSIZE);
        if (err != 0) {
        }
        kbuf += BSIZE;
        sectors--;
    } while (sectors > 0);

    if (*nbyte > 512) {
        err = ops->sendcmd(CMD12, 0, RSP_R1, resp);
    }

    // DPRINTF(("%s end\n",__func__));
    return 0;
}

static int sdmmc_write(device_t dev, char* buf, size_t* nbyte, int sect_addr)
{
    uint32_t sectors, offset, part_idx;
    uint32_t addr;
    uint32_t err;
    uint8_t cmd;
    uint8_t* resp;
    char* kbuf;

    struct sdmmc_dev_softc* sc;
    struct sdmmc_ops* ops;
    struct sdmmc_devinfo* info;

    // DPRINTF(("%s sz=%d sect_addr=%d\n",__func__, *nbyte, sect_addr));

    /* Translate buffer address to kernel address */
    if ((kbuf = kmem_map(buf, *nbyte)) == NULL)
        return EFAULT;

    sc = device_private(dev);
    ops = sc->ops;
    info = sc->info;
    resp = info->resp;
    if (dev != info->dev) {
        /* partition device */
        for (part_idx = 0; part_idx < MAX_PARTI; part_idx++) {
            if (info->part_dev[part_idx] == dev) {
                break;
            }
            if (part_idx == (MAX_PARTI - 1)) {
                DPRINTF(("[%s] invalid device\n", __func__));
                return -1;
            }
        }
        if (sect_addr > info->part_info[part_idx].size) {
            DPRINTF(("[%s] part %d read out of range\n", __func__, part_idx));
            return -1;
        }
        sect_addr += info->part_info[part_idx].start;
    }

    if (sdmmc_wait_ready(ops, info) != 0) {
        DPRINTF(("%s wait ready fail\n", __func__));
        *nbyte = 0;
        return -1;
    }

    if (!(info->sdmmc_type & BLK_ADDR))
        sect_addr *= 512; /* byte address */

    sectors = (*nbyte) / 512;

    if (sectors == 1) {
        cmd = CMD24;
    } else {
        cmd = (info->sdmmc_type & (SDV1_CARD | SDV2_CARD)) ? ACMD23 : CMD23;
        err = ops->sendcmd(cmd, sectors, RSP_R1, resp);
        if (err != 0 || (resp[0] & 0xC0) || (resp[1] & 0x58)) {
            /* TODO: error state */
        }
        cmd = CMD25;
    }

    err = ops->sendcmd(cmd, sect_addr, RSP_R1, resp);
    if (err != 0 || (resp[0] & 0xC0) || (resp[1] & 0x58)) {
        /* TODO: error state */
    }

    do {
        err = ops->xmit(info, kbuf, BSIZE);
        if (err != 0) {
            /* TODO: error state */
        }
        kbuf += BSIZE;
        sectors--;
    } while (sectors > 0);

    if (cmd == CMD25 && (info->sdmmc_type & (SDV1_CARD | SDV2_CARD))) {
        err = ops->sendcmd(CMD12, 0, RSP_R1, resp);
    }

    if (sdmmc_wait_ready(ops, info) != 0) {
        DPRINTF(("%s wait ready fail\n", __func__));
        *nbyte = 0;
        return -1;
    }

    // DPRINTF(("%s end\n",__func__));
    return 0;
}

static int sdmmc_probe(struct driver* self)
{
    return 0;
}

device_t sdmmc_attach(struct sdmmc_ops* ops, struct sdmmc_devinfo* info)
{
    struct sdmmc_dev_softc* sc;
    device_t dev;
    char* name;
    uint32_t i;

    for (i = 0; i < MAX_DEV; i++) {
        if (sdmmc_drv_list[i] == NULL)
            break;
        if (i == MAX_DEV)
            return NULL;
    }

    info->dev_idx = i;

    sdmmc_drv_list[i] = kmem_alloc(sizeof(struct driver));
    memcpy(sdmmc_drv_list[i], &sdmmc_dev_driver, sizeof(struct driver));
    sdmmc_drv_list[i]->name = info->dev_name;

    name = (char*)(sdmmc_drv_list[i]->name);

    dev = device_create(sdmmc_drv_list[i], sdmmc_drv_list[i]->name, D_BLK);
    info->dev = dev;
    info->part_status = 0;
    if (dev != NULL) {
        sc = device_private(dev);
        sc->dev = dev;
        sc->ops = ops;
        sc->info = info;
        DPRINTF(("[%s] register SD/MMC adapter %s %x\n", __func__, sdmmc_drv_list[i]->name, dev));
    } else {
        device_destroy(dev);
        kmem_free(sdmmc_drv_list[i]);
        DPRINTF(("[%s] register %s failed\n", __func__, sdmmc_drv_list[i]->name));
        dev = NULL;
    }

    return dev;
}

void sdmmc_insert(device_t dev)
{
    struct sdmmc_dev_softc* sc;
    struct sdmmc_ops* ops;
    struct sdmmc_devinfo* info;
    /* check card type, check partition table, create partition device node */
    uint32_t err, *freq_tab, i;
    uint8_t* resp;

    DPRINTF(("%s %X\n", __func__, dev));

    if (dev == NULL) {
        DPRINTF(("%s NULL dev\n", __func__));
        return;
    }
    sc = device_private(dev);
    ops = sc->ops;
    info = sc->info;
    resp = info->resp;

    ops->setfreq(0); /* set to lowest freq */

    /*---- Card is 'idle' state ----*/
    ops->sendcmd(CMD0, 0, RSP_R1, NULL);

    err = ops->sendcmd(CMD8, 0x1AA, RSP_R3, resp);
    if (err == 0 && ((resp[2] & 0x0F) == 0x1) && (resp[3] == 0xAA)) {
        /* SDC Ver2. The card can work at vdd range of 2.7-3.6V */
        DPRINTF(("[%s] SDC v2\n", __func__));
        do {
            err = ops->sendcmd(ACMD41, 0x40FF8000, RSP_R3, resp);
            if (err != 0)
                return -1;
        } while ((resp[0] & 0x80) == 0);
        DPRINTF(("[%s] SDv2 rsp %X %X %X %X\n", __func__, resp[0], resp[1], resp[2], resp[3]));

        info->sdmmc_type = SDV2_CARD;
        if (resp[0] & 0x40) {
            DPRINTF(("[%s] BLOCK-Address\n", __func__));
            info->sdmmc_type |= BLK_ADDR;
        }
    } else {
        uint8_t cmd;
        /* SDC Ver1 or MMC */
        if (ops->sendcmd(ACMD41, 0x00FF8000, RSP_R3, resp) == 0) {
            DPRINTF(("[%s] SDC v1\n", __func__));
            /* ACMD41 is accepted -> SDC Ver1 */
            info->sdmmc_type = SDV1_CARD;
            cmd = ACMD41;
        } else {
            /* ACMD41 is rejected -> MMC */
            DPRINTF(("[%s] MMC\n", __func__));
            info->sdmmc_type = MMC_CARD;
            cmd = CMD1;
        }

        do {
            ops->sendcmd(cmd, 0x00FF8000, RSP_R3, resp);
        } while ((resp[0] & 0x80) == 0);
    }

    /* OCR */
    memcpy(info->ocr, resp, 4);

    /*---- Card is 'ready' state ----*/
    if (ops->sendcmd(CMD2, 0, RSP_R2, resp) != 0) {
        // TODO: error state
    }

    /* CID */
    memcpy(info->cid, resp, 16);

    /*---- Card is 'ident' state ----*/
    if (info->sdmmc_type & (SDV1_CARD | SDV2_CARD)) {
        err = ops->sendcmd(CMD3, 0, RSP_R6, resp);
        info->card_rca = resp[0] << 8 | resp[1];
    } else {
        err = ops->sendcmd(CMD3, 1 << 16, RSP_R6, resp);
        info->card_rca = 1;
    }

    /*---- Card is 'stby' state ----*/
    /* Get CSD and save it */
    if (ops->sendcmd(CMD9, info->card_rca << 16, RSP_R2, resp) != 0) {
    }
    memcpy(info->csd, resp, 16);

    /* Select card */
    if (ops->sendcmd(CMD7, info->card_rca << 16, RSP_R1, resp) != 0) {
    }

    /*---- Card is 'tran' state ----*/
    if (!(info->sdmmc_type & BLK_ADDR)) {
        uint32_t err;
        /* Set data block length to 512 (for byte addressing cards) */
        err = ops->sendcmd(CMD16, 512, RSP_R1, resp);
        if (err != 0 || (resp[0] & 0xFD) || (resp[1] & 0xF9)) {
            /* TODO: error state */
        }
    }
#if USE_4BIT
    if (info->sdmmc_type & (SDV1_CARD | SDV2_CARD) && info->data_bits >= 4) {
        ops->setwidth(4);
        err = ops->sendcmd(ACMD6, 2, RSP_R1, resp);
        if (err != 0 || (resp[0] & 0xFD) || (resp[1] & 0xF9)) {
            /* TODO: error state */
        }
    }
#endif

    info->speed = sdmmc_freq_tab[(info->csd[3] & 0x78) >> 3] * sdmmc_freq_factor[info->csd[3] & 0x07];
    DPRINTF(("[%s] bus max speed %u\n", __func__, info->speed));
    freq_tab = info->freq_tab;
    for (i = 0; i < info->freq_levels; i++) {
        if (freq_tab[i] > info->speed) {
            i--;
            DPRINTF(("[%s] set busfreq to %d\n", __func__, freq_tab[i]));
            break;
        }
    }
    ops->setfreq(i);

    {
        /* update card info & reading MBR and create partition device node */
        uint8_t* csd = info->csd;
        size_t count = BSIZE;
        uint32_t* part_exist;
        uint8_t i, mbr[BSIZE], *ptr;
        struct sdmmc_dev_softc* part_sc;

        if (info->sdmmc_type & SDV2_CARD && info->sdmmc_type & BLK_ADDR) {
            info->total_sectors = (csd[9] + (csd[8] << 8) + 1) << 10;
        } else {
            uint32_t shift;
            shift = (csd[5] & 15) + ((csd[10] & 128) >> 7) + ((csd[9] & 3) << 1) + 2;
            info->total_sectors = ((csd[8] >> 6) + (csd[7] << 2) + ((csd[6] & 3) << 10) + 1) << (shift - 9);
        }
        DPRINTF(("[%s] total sectors:%d\n", __func__, info->total_sectors));

        memset(mbr, 0, BSIZE);

        DPRINTF(("%s test read\n", __func__));

        sdmmc_read(dev, mbr, &count, 0);

#if 0
		for(count = 0; count < BSIZE; count++){
			if((count % 16) == 0)
				DPRINTF(("\n"));
			DPRINTF((" %X", mbr[count]));
		}
		DPRINTF(("\n"));
#endif

        ptr = mbr + 446;
        for (i = 0; i < MAX_PARTI; i++) {
            part_exist = (uint32_t*)(ptr + 4);
            if (*part_exist) {
                device_t part_dev;
                memcpy(&info->part_info[i], ptr, sizeof(part_record));
                DPRINTF(("partition %d exist\n", i + 1));
                DPRINTF(("first sector   :%d\n", info->part_info[i].start));
                DPRINTF(("size in sectors:%d\n", info->part_info[i].size));

                memcpy(&(info->part_drv[i]), &sdmmc_dev_driver, sizeof(struct driver));
                info->part_drv[i].name = info->part_dev_name[i];

                part_dev = device_create(&(info->part_drv[i]), info->part_drv[i].name, D_BLK);
                info->part_dev[i] = part_dev;

                part_sc = device_private(part_dev);
                part_sc->ops = ops;
                part_sc->info = info;

                info->part_status |= (1 << i);
            }
            ptr += 16;
        }
    }

    DPRINTF(("%s finished\n", __func__));
}

void sdmmc_remove(device_t dev)
{
    struct sdmmc_dev_softc* sc;
    struct sdmmc_devinfo* info;
    u_long i;

    DPRINTF(("%s\n", __func__));
    sc = device_private(dev);
    info = sc->info;

    for (i = 0; i < MAX_PARTI; i++) {
        if (info->part_status & (1 << i)) {
            device_destroy(info->part_dev[i]);
        }
    }

    info->speed = 0;
    info->total_sectors = 0;
    info->part_status = 0;

    memset(info->cid, 0, 16);
    memset(info->csd, 0, 16);
    memset(info->ocr, 0, 4);
    info->card_rca = 0;

    memset(info->part_info, 0, sizeof(part_record) * MAX_PARTI);
    memset(info->part_dev, 0, sizeof(device_t) * MAX_PARTI);
    memset(info->part_drv, 0, sizeof(struct driver) * MAX_PARTI);
}

static int sdmmc_init(struct driver* self)
{
    uint32_t i;

    for (i = 0; i < MAX_DEV; i++)
        sdmmc_drv_list[i] = NULL;

    return 0;
}
