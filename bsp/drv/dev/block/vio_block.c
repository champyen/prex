/*-
 * Copyright (c) 2026, Champ Yen (champ.yen@gmail.com)
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

#include <driver.h>
#include <ddi.h>
#include <dki.h>
#include <types.h>
#include <vio_mmio.h>

/* VirtIO Block Request Types */
#define VIO_BLK_T_IN            0
#define VIO_BLK_T_OUT           1
#define VIO_BLK_T_FLUSH         4

/* VirtIO Block Status */
#define VIO_BLK_S_OK            0
#define VIO_BLK_S_IOERR         1
#define VIO_BLK_S_UNSUPP        2

/* VirtIO Device Status */
#define VIO_STATUS_ACKNOWLEDGE  1
#define VIO_STATUS_DRIVER       2
#define VIO_STATUS_DRIVER_OK    4
#define VIO_STATUS_FEATURES_OK  8

/* VirtQueue Descriptor Flags */
#define VRING_DESC_F_NEXT       1
#define VRING_DESC_F_WRITE      2
#define VRING_DESC_F_INDIRECT   4

struct vring_desc {
    uint64_t addr;
    uint32_t len;
    uint16_t flags;
    uint16_t next;
} __packed;

struct vring_avail {
    uint16_t flags;
    uint16_t idx;
    uint16_t ring[16];
} __packed;

struct vring_used_elem {
    uint32_t id;
    uint32_t len;
} __packed;

struct vring_used {
    uint16_t flags;
    uint16_t idx;
    struct vring_used_elem ring[16];
} __packed;

struct vio_blk_req {
    uint32_t type;
    uint32_t reserved;
    uint64_t sector;
} __packed;

#define VQ_SIZE 16

struct vio_blk_softc {
    device_t dev;
    vaddr_t base;
    int irq;
    irq_t irq_handle;
    struct event done_event;

    /* VirtQueue */
    volatile struct vring_desc* desc;
    volatile struct vring_avail* avail;
    volatile struct vring_used* used;
    uint16_t last_used_idx;

    struct vio_blk_req* req;
    uint8_t* status_ptr;

    /* Partition support */
    uint32_t start_sector;
    uint32_t nsectors;
    struct vio_blk_softc* parent_sc;
};

static int vio_blk_read(device_t dev, char* buf, size_t* nbyte, int blkno);
static int vio_blk_write(device_t dev, char* buf, size_t* nbyte, int blkno);
static int vio_block_init(struct driver* self);

static struct devops vio_blk_devops = {
    /* open */ no_open,
    /* close */ no_close,
    /* read */ vio_blk_read,
    /* write */ vio_blk_write,
    /* ioctl */ no_ioctl,
    /* devctl */ no_devctl,
};

struct driver vio_block_driver = {
    /* name */ "vio_block",
    /* devops */ &vio_blk_devops,
    /* devsz */ sizeof(struct vio_blk_softc),
    /* flags */ 0,
    /* probe */ NULL,
    /* init */ vio_block_init,
    /* shutdown */ NULL,
};

static int vio_blk_isr(void* arg)
{
    struct vio_blk_softc* sc = arg;
    uint32_t status = bus_read_32(sc->base + VIO_MMIO_IRQ_STATUS);
    if (status) {
        bus_write_32(sc->base + VIO_MMIO_IRQ_ACK, status);
        return INT_CONTINUE;
    }
    return INT_DONE;
}

static void vio_blk_ist(void* arg)
{
    struct vio_blk_softc* sc = arg;
    sched_wakeup(&sc->done_event);
}

static int vio_block_init(struct driver* self)
{
    return 0;
}

#define BSIZE 512
#define MAX_PARTI 4

typedef struct part_record
{
    uint32_t status_chs;
    uint32_t part_type;
    uint32_t start; /* start sector address */
    uint32_t size;  /* in sectors */
} part_record;

static void attach_partition(struct vio_blk_softc* parent_sc, const char* name, uint32_t start, uint32_t size)
{
    device_t dev;
    struct vio_blk_softc* sc;

    dev = device_create(&vio_block_driver, name, D_BLK | D_PROT);
    sc = device_private(dev);
    
    /* Copy necessary info from parent */
    sc->dev = dev;
    sc->base = parent_sc->base;
    sc->irq = parent_sc->irq;
    sc->irq_handle = parent_sc->irq_handle;
    
    /* Partition info */
    sc->start_sector = start;
    sc->nsectors = size;
    sc->parent_sc = parent_sc;

    printf("VirtIO Block partition %s: start %u, size %u\n", name, start, size);
}

int vio_block_attach(vaddr_t base, int irq)
{
    struct vio_blk_softc* sc;
    device_t dev;
    uint32_t status;
    static int unit = 0;
    char name[16] = "vd0";

    if (unit < 10) name[2] = '0' + unit++;
    dev = device_create(&vio_block_driver, name, D_BLK | D_PROT);
    sc = device_private(dev);
    sc->dev = dev;
    sc->base = base;
    sc->irq = irq;
    sc->last_used_idx = 0;
    sc->start_sector = 0;
    sc->nsectors = 0; /* Unknown yet */
    sc->parent_sc = NULL;
    event_init(&sc->done_event, "vio_blk");

    /* Reset device */
    bus_write_32(base + VIO_MMIO_STATUS, 0);

    /* Acknowledge */
    status = VIO_STATUS_ACKNOWLEDGE | VIO_STATUS_DRIVER;
    bus_write_32(base + VIO_MMIO_STATUS, status);

    /* Feature negotiation (we accept no features for now) */
    bus_write_32(base + VIO_MMIO_DRV_FEATURE, 0);

    /* Tell device our page size */
    bus_write_32(base + VIO_MMIO_PAGE_SIZE, 4096);

    /* Setup VirtQueue */
    bus_write_32(base + VIO_MMIO_QUEUE_SEL, 0);
    uint32_t q_max = bus_read_32(base + VIO_MMIO_QUEUE_NUM_MAX);
    if (q_max < VQ_SIZE) {
        printf("VirtQueue size too small: %d\n", (int)q_max);
        return -1;
    }

    /* Use page_alloc for 4K alignment, allocate 2 pages for legacy layout plus extra for manual alignment */
    paddr_t raw_pa = page_alloc(8192 + 4096);
    if (raw_pa == 0) {
        printf("Failed to allocate VQ memory\n");
        return -1;
    }
    paddr_t vq_pa = (raw_pa + 4095) & ~4095;
    void* vq_mem = ptokv(vq_pa);
    memset(vq_mem, 0, 8192);
    sc->desc = (struct vring_desc*)vq_mem;
    sc->avail = (struct vring_avail*)((char*)vq_mem + VQ_SIZE * sizeof(struct vring_desc));
    sc->used = (struct vring_used*)((char*)vq_mem + 4096);

    bus_write_32(base + VIO_MMIO_QUEUE_SIZE, VQ_SIZE);
    bus_write_32(base + VIO_MMIO_QUEUE_ALIGN, 4096);
    bus_write_32(base + VIO_MMIO_QUEUE_PFN, (uint32_t)(vq_pa >> 12));

    /* Driver OK */
    status |= VIO_STATUS_DRIVER_OK;
    bus_write_32(base + VIO_MMIO_STATUS, status);

    sc->irq_handle = irq_attach(irq, IPL_BLOCK, 0, vio_blk_isr, vio_blk_ist, sc);

    sc->req = kmem_alloc(sizeof(struct vio_blk_req));
    sc->status_ptr = kmem_alloc(1);

    printf("VirtIO Block initialized at 0x%lx, irq %d as %s\n", base, irq, name);

    /* Read capacity */
    uint32_t cap_low = bus_read_32(base + VIO_MMIO_CFG);
    uint32_t cap_high = bus_read_32(base + VIO_MMIO_CFG + 4);
    sc->nsectors = cap_low; /* Support up to 2TB for now */
    if (cap_high != 0) printf("Warning: disk capacity > 2TB, truncated\n");

    /* Partition scan */
    uint8_t mbr[BSIZE];
    size_t count = BSIZE;
    if (vio_blk_read(dev, (char*)mbr, &count, 0) == 0) {
        uint8_t* ptr = mbr + 446;
        int i, found = 0;
        for (i = 0; i < MAX_PARTI; i++) {
            uint32_t psize = *(uint32_t*)(ptr + 12);
            if (psize > 0) {
                char pname[16];
                strlcpy(pname, name, sizeof(pname));
                int len = 0;
                while (pname[len] && len < sizeof(pname)) len++;
                if (len + 2 < sizeof(pname)) {
                    pname[len] = 'p';
                    pname[len + 1] = '1' + i;
                    pname[len + 2] = '\0';
                }
                attach_partition(sc, pname, *(uint32_t*)(ptr + 8), psize);
                found = 1;
            }
            ptr += 16;
        }
        if (!found) {
            printf("No partition found on %s, using whole disk as p1\n", name);
            char pname[16];
            strlcpy(pname, name, sizeof(pname));
            int len = 0;
            while (pname[len] && len < sizeof(pname)) len++;
            if (len + 2 < sizeof(pname)) {
                pname[len] = 'p';
                pname[len + 1] = '1';
                pname[len + 2] = '\0';
            }
            attach_partition(sc, pname, 0, sc->nsectors);
        }
    }

    return 0;
}

static int vio_blk_read(device_t dev, char* buf, size_t* nbyte, int blkno)
{
    struct vio_blk_softc* sc = device_private(dev);
    struct vio_blk_softc* psc = sc->parent_sc ? sc->parent_sc : sc;
    void* kbuf;
    
    if (sc->nsectors > 0 && blkno >= (int)sc->nsectors)
        return EIO;

    kbuf = kmem_map(buf, *nbyte);
    if (kbuf == NULL) return EFAULT;

    *psc->status_ptr = 0xFF;

    psc->req->type = VIO_BLK_T_IN;
    psc->req->reserved = 0;
    psc->req->sector = sc->start_sector + blkno;

    psc->desc[0].addr = (uint64_t)kvtop(psc->req);
    psc->desc[0].len = sizeof(struct vio_blk_req);
    psc->desc[0].flags = VRING_DESC_F_NEXT;
    psc->desc[0].next = 1;

    psc->desc[1].addr = (uint64_t)kvtop(kbuf);
    psc->desc[1].len = (uint32_t)*nbyte;
    psc->desc[1].flags = VRING_DESC_F_NEXT | VRING_DESC_F_WRITE;
    psc->desc[1].next = 2;

    psc->desc[2].addr = (uint64_t)kvtop(psc->status_ptr);
    psc->desc[2].len = 1;
    psc->desc[2].flags = VRING_DESC_F_WRITE;
    psc->desc[2].next = 0;

    psc->avail->ring[psc->avail->idx % 16] = 0;
    __sync_synchronize();
    psc->avail->idx++;
    __sync_synchronize();

    bus_write_32(psc->base + VIO_MMIO_QUEUE_NOTIFY, 0);

    while (psc->used->idx == psc->last_used_idx) {
        sched_sleep(&psc->done_event);
    }
    psc->last_used_idx = psc->used->idx;

    int err = (*psc->status_ptr == VIO_BLK_S_OK) ? 0 : EIO;
    if (err) printf("vio_blk_read: error status %d\n", *psc->status_ptr);
    
    return err;
}

static int vio_blk_write(device_t dev, char* buf, size_t* nbyte, int blkno)
{
    struct vio_blk_softc* sc = device_private(dev);
    struct vio_blk_softc* psc = sc->parent_sc ? sc->parent_sc : sc;
    void* kbuf;
    
    if (sc->nsectors > 0 && blkno >= (int)sc->nsectors)
        return EIO;

    kbuf = kmem_map(buf, *nbyte);
    if (kbuf == NULL) return EFAULT;

    *psc->status_ptr = 0xFF;

    psc->req->type = VIO_BLK_T_OUT;
    psc->req->reserved = 0;
    psc->req->sector = sc->start_sector + blkno;

    psc->desc[0].addr = (uint64_t)kvtop(psc->req);
    psc->desc[0].len = sizeof(struct vio_blk_req);
    psc->desc[0].flags = VRING_DESC_F_NEXT;
    psc->desc[0].next = 1;

    psc->desc[1].addr = (uint64_t)kvtop(kbuf);
    psc->desc[1].len = (uint32_t)*nbyte;
    psc->desc[1].flags = VRING_DESC_F_NEXT;
    psc->desc[1].next = 2;

    psc->desc[2].addr = (uint64_t)kvtop(psc->status_ptr);
    psc->desc[2].len = 1;
    psc->desc[2].flags = VRING_DESC_F_WRITE;
    psc->desc[2].next = 0;

    psc->avail->ring[psc->avail->idx % 16] = 0;
    __sync_synchronize();
    psc->avail->idx++;
    __sync_synchronize();

    bus_write_32(psc->base + VIO_MMIO_QUEUE_NOTIFY, 0);

    while (psc->used->idx == psc->last_used_idx) {
        sched_sleep(&psc->done_event);
    }
    psc->last_used_idx = psc->used->idx;

    int err = (*psc->status_ptr == VIO_BLK_S_OK) ? 0 : EIO;
    
    return err;
}
