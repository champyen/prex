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

#ifndef _SDMMC_H
#define _SDMMC_H

#include <sys/cdefs.h>
#include <sys/ioctl.h>

#define MAX_PARTI 4

/* ----- MMC/SDC command ----- */
#define APP_CMD 0x80
#define CMD0 (0)              /* GO_IDLE_STATE */
#define CMD1 (1)              /* SEND_OP_COND (MMC) */
#define CMD2 (2)              /* ALL_SEND_CID */
#define CMD3 (3)              /* SEND_RELATIVE_ADDR */
#define ACMD6 (6 | APP_CMD)   /* SET_BUS_WIDTH (SDC) */
#define CMD7 (7)              /* SELECT_CARD */
#define CMD8 (8)              /* SEND_IF_COND */
#define CMD9 (9)              /* SEND_CSD */
#define CMD10 (10)            /* SEND_CID */
#define CMD12 (12)            /* STOP_TRANSMISSION */
#define CMD13 (13)            /* SEND_STATUS */
#define ACMD13 (13 | APP_CMD) /* SD_STATUS (SDC) */
#define CMD16 (16)            /* SET_BLOCKLEN */
#define CMD17 (17)            /* READ_SINGLE_BLOCK */
#define CMD18 (18)            /* READ_MULTIPLE_BLOCK */
#define CMD23 (23)            /* SET_BLK_COUNT (MMC) */
#define ACMD23 (23 | APP_CMD) /* SET_WR_BLK_ERASE_COUNT (SDC) */
#define CMD24 (24)            /* WRITE_BLOCK */
#define CMD25 (25)            /* WRITE_MULTIPLE_BLOCK */
#define ACMD41 (41 | APP_CMD) /* SEND_OP_COND (SDC) */
#define ACMD42 (42 | APP_CMD) /* SEND_OP_COND (SDC) */
#define CMD55 (55)            /* APP_CMD */

typedef struct part_record
{
    uint32_t status_chs;
    uint32_t part_type;
    uint32_t start; /* start sector address */
    uint32_t size;  /* in sectors */
} part_record;

struct sdmmc_devinfo
{
    char* dev_name;
    char** part_dev_name;
    uint32_t freq_levels; /* how many freqs are supported */
    uint32_t* freq_tab;   /* the list of supported freq, from low to high*/
    uint32_t blk_size;    /* multiple of 512 */
    uint32_t data_bits;   /* 1, 4 or 8 */
    uint32_t inserted;    /* is the card inserted */

    /* fields used by SD/MMC stack */
    uint8_t resp[16];
    paddr_t tmpbuf; /* used for read/write */

    device_t dev;
    uint32_t sdmmc_type; /* [31:16] - CardType, [15:0] flags */
    uint32_t dev_idx;
    uint32_t speed;
    uint32_t total_sectors;
    uint8_t csd[16]; /* CSD:16byte CID:16bytes OCR:4bytes */
    uint8_t cid[16];
    uint8_t ocr[4];
    uint32_t card_rca;

    /* TODO: multi-partition support */
    uint32_t part_status;
    part_record part_info[MAX_PARTI];
    device_t part_dev[MAX_PARTI];
    struct driver part_drv[MAX_PARTI];
};

struct sdmmc_ops
{
    int (*sendcmd)(uint8_t cmd, uint32_t arg, uint8_t rsp_type, uint8_t* rspbuf);
    int (*ioctl)(u_long cmd, void* arg);
    int (*setfreq)(uint32_t idx);
    int (*setwidth)(uint32_t bits); /* set data bus width */
    int (*xmit)(struct sdmmc_devinfo* info, char* buf, size_t nbyte);
    int (*recv)(struct sdmmc_devinfo* info, char* buf, size_t nbyte);
};

#define MMC_CARD 0x00010000
#define SDV1_CARD 0x00020000
#define SDV2_CARD 0x00040000
#define BLK_ADDR 0x00000001

typedef enum SDMMC_RSP_TYPE
{
    RSP_R1 = 0,
    RSP_R2,
    RSP_R3,
    RSP_R4,
    RSP_R5,
    RSP_R6,
} rsp_type;

__BEGIN_DECLS
device_t sdmmc_attach(struct sdmmc_ops* ops, struct sdmmc_devinfo* info);
void sdmmc_insert(device_t dev);
void sdmmc_remove(device_t dev);
__END_DECLS

#endif /* !_CPUFREQ_H */
