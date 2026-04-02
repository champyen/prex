/*-
 * Copyright (c) 2026 Champ Yen
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
 * bcm2835_dma.c - BCM2835 DMA controller
 */

#include <sys/cdefs.h>
#include <driver.h>

#ifdef DEBUG
#define DPRINTF(a) printf a
#else
#define DPRINTF(a)
#endif

#define DMA_BASE CONFIG_BCM2835_DMA_BASE

#define DMA_CS(n)       (DMA_BASE + (n) * 0x100 + 0x00)
#define DMA_ADDR(n)     (DMA_BASE + (n) * 0x100 + 0x04)
#define DMA_INFO(n)     (DMA_BASE + (n) * 0x100 + 0x08)
#define DMA_SOURCE_AD(n) (DMA_BASE + (n) * 0x100 + 0x0c)
#define DMA_DEST_AD(n)   (DMA_BASE + (n) * 0x100 + 0x10)
#define DMA_TXFR_LEN(n)  (DMA_BASE + (n) * 0x100 + 0x14)
#define DMA_STRIDE(n)    (DMA_BASE + (n) * 0x100 + 0x18)
#define DMA_NEXTCB(n)    (DMA_BASE + (n) * 0x100 + 0x1c)
#define DMA_DEBUG(n)     (DMA_BASE + (n) * 0x100 + 0x20)

#define DMA_INT_STATUS  (DMA_BASE + 0xfe0)
#define DMA_ENABLE      (DMA_BASE + 0xff0)

/* Bus address translation for BCM2835 (RPi) 
 * 0x40000000 is L2 cached alias, 0xC0000000 is uncached alias.
 * Using 0xC0000000 to ensure coherency without manual cache flushing.
 */
#define BCM2835_BUS_ADDR(pa) ((uint32_t)(pa) | 0xC0000000)

/* CS register bits */
#define DMA_CS_ACTIVE   (1 << 0)
#define DMA_CS_END      (1 << 1)
#define DMA_CS_INT      (1 << 2)
#define DMA_CS_DREQ     (1 << 3)
#define DMA_CS_PAUSED   (1 << 4)
#define DMA_CS_DREQ_STOPS_DMA (1 << 5)
#define DMA_CS_WAITING_FOR_OUTSTANDING_WRITES (1 << 6)
#define DMA_CS_ERROR    (1 << 8)
#define DMA_CS_PRIORITY(n) ((n) << 16)
#define DMA_CS_PANIC_PRIORITY(n) ((n) << 20)
#define DMA_CS_WAIT_FOR_OUTSTANDING_WRITES (1 << 28)
#define DMA_CS_DISDEBUG (1 << 29)
#define DMA_CS_ABORT    (1 << 30)
#define DMA_CS_RESET    (1 << 31)

/* TI (Transfer Info) bits */
#define DMA_TI_INTEN    (1 << 0)
#define DMA_TI_TDMODE   (1 << 1)
#define DMA_TI_WAIT_RESP (1 << 3)
#define DMA_TI_DEST_INC (1 << 4)
#define DMA_TI_DEST_WIDTH (1 << 5)
#define DMA_TI_DEST_DREQ (1 << 6)
#define DMA_TI_DEST_IGNORE (1 << 7)
#define DMA_TI_SRC_INC  (1 << 8)
#define DMA_TI_SRC_WIDTH (1 << 9)
#define DMA_TI_SRC_DREQ (1 << 10)
#define DMA_TI_SRC_IGNORE (1 << 11)
#define DMA_TI_BURST_LENGTH(n) ((n) << 12)
#define DMA_TI_PERMAP(n) ((n) << 16)
#define DMA_TI_WAITS(n) ((n) << 21)
#define DMA_TI_NO_WIDE_BURSTS (1 << 26)

#define NR_DMAS 15

struct bcm_dma_cb {
    uint32_t ti;
    uint32_t source_ad;
    uint32_t dest_ad;
    uint32_t txfr_len;
    uint32_t stride;
    uint32_t nextconbk;
    uint32_t reserved[2];
} __attribute__((aligned(32)));

struct dma {
    int chan;
    int in_use;
    struct bcm_dma_cb* cb;
};

static struct dma dma_table[NR_DMAS];
static struct bcm_dma_cb dma_cbs[NR_DMAS] __attribute__((aligned(32)));

static int dma_init(struct driver* self);

struct driver bcm2835_dma_driver = {
    /* name */ "dma",
    /* devsops */ NULL,
    /* devsz */ 0,
    /* flags */ 0,
    /* probe */ NULL,
    /* init */ dma_init,
    /* shutdown */ NULL,
};

dma_t dma_attach(int chan)
{
    struct dma* dma;
    int s;

    if (chan < 0 || chan >= NR_DMAS)
        return NODMA;

    s = splhigh();
    dma = &dma_table[chan];
    if (dma->in_use) {
        splx(s);
        return NODMA;
    }
    dma->chan = chan;
    dma->in_use = 1;
    dma->cb = &dma_cbs[chan];
    
    /* Reset channel */
    bus_write_32(DMA_CS(chan), DMA_CS_RESET);
    while (bus_read_32(DMA_CS(chan)) & DMA_CS_RESET)
        ;

    splx(s);
    return (dma_t)dma;
}

void dma_detach(dma_t handle)
{
    struct dma* dma = (struct dma*)handle;
    int s;

    ASSERT(dma->in_use);

    s = splhigh();
    dma_stop(handle);
    dma->in_use = 0;
    splx(s);
}

void dma_setup(dma_t handle, void* addr, u_long count, int read)
{
    struct dma* dma = (struct dma*)handle;
    struct bcm_dma_cb* cb = dma->cb;
    int chan = dma->chan;
    paddr_t pa = kvtop(addr);

    cb->ti = DMA_TI_SRC_INC | DMA_TI_DEST_INC | DMA_TI_INTEN;
    if (read) {
        /* Peripheral -> Memory */
        cb->source_ad = 0; /* Should be set to peripheral address */
        cb->dest_ad = BCM2835_BUS_ADDR(pa);
    } else {
        /* Memory -> Peripheral */
        cb->source_ad = BCM2835_BUS_ADDR(pa);
        cb->dest_ad = 0; /* Should be set to peripheral address */
    }
    cb->txfr_len = (uint32_t)count;
    cb->stride = 0;
    cb->nextconbk = 0;

    bus_write_32(DMA_ADDR(chan), BCM2835_BUS_ADDR(kvtop(cb)));
    bus_write_32(DMA_CS(chan), DMA_CS_ACTIVE);
}

void dma_stop(dma_t handle)
{
    struct dma* dma = (struct dma*)handle;
    int chan = dma->chan;

    bus_write_32(DMA_CS(chan), 0);
}

void* dma_alloc(size_t size)
{
    paddr_t p;
    size = round_page(size);
    p = page_alloc(size);
    if (p == 0)
        return NULL;
    return ptokv(p);
}

static int dma_init(struct driver* self)
{
    int i;

    for (i = 0; i < NR_DMAS; i++) {
        dma_table[i].chan = i;
        dma_table[i].in_use = 0;
        dma_table[i].cb = &dma_cbs[i];
    }

    /* Enable all DMA channels */
    bus_write_32(DMA_ENABLE, 0x7fff);

    printf("BCM2835 DMA driver initialized\n");

    /* Self test: Memory-to-memory DMA */
    printf("BCM2835 DMA: Running self test...\n");
    {
        char *src, *dst;
        struct bcm_dma_cb *test_cb = &dma_cbs[0];
        const char *test_str = "BCM2835 DMA Test OK";
        int len = 20;

        src = dma_alloc(PAGE_SIZE);
        dst = dma_alloc(PAGE_SIZE);

        if (src && dst) {
            for (i = 0; i < len; i++) src[i] = test_str[i];
            for (i = 0; i < len; i++) dst[i] = 0;

            test_cb->ti = DMA_TI_SRC_INC | DMA_TI_DEST_INC;
            test_cb->source_ad = BCM2835_BUS_ADDR(kvtop(src));
            test_cb->dest_ad = BCM2835_BUS_ADDR(kvtop(dst));
            test_cb->txfr_len = len;
            test_cb->stride = 0;
            test_cb->nextconbk = 0;

            bus_write_32(DMA_ADDR(0), BCM2835_BUS_ADDR(kvtop(test_cb)));
            bus_write_32(DMA_CS(0), DMA_CS_ACTIVE);

            /* Wait for completion */
            i = 1000000;
            while (!(bus_read_32(DMA_CS(0)) & DMA_CS_END) && --i > 0)
                ;

            if (i > 0) {
                int match = 1;
                for (i = 0; i < len; i++) {
                    if (dst[i] != src[i]) {
                        match = 0;
                        break;
                    }
                }
                if (match) {
                    printf("BCM2835 DMA: Memory-to-memory test passed\n");
                } else {
                    printf("BCM2835 DMA: Memory-to-memory test failed (data mismatch)\n");
                }
            } else {
                printf("BCM2835 DMA: Memory-to-memory test failed (timeout), CS=0x%x\n", bus_read_32(DMA_CS(0)));
            }
            
            /* Clear end flag */
            bus_write_32(DMA_CS(0), DMA_CS_END);
        } else {
            printf("BCM2835 DMA: Memory-to-memory test failed (alloc error)\n");
        }
    }

    return 0;
}
