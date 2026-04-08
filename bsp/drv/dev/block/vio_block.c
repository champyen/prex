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

int vio_block_attach(vaddr_t base, int irq)
{
    struct vio_blk_softc* sc;
    device_t dev;
    uint32_t status;
    static int unit = 0;
    char name[12] = "vd0";

    if (unit < 10) name[2] = '0' + unit++;
    dev = device_create(&vio_block_driver, name, D_BLK | D_PROT);
    sc = device_private(dev);
    sc->dev = dev;
    sc->base = base;
    sc->irq = irq;
    sc->last_used_idx = 0;
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
    return 0;
}

static int vio_blk_read(device_t dev, char* buf, size_t* nbyte, int blkno)
{
    struct vio_blk_softc* sc = device_private(dev);
    void* kbuf;
    
    kbuf = kmem_map(buf, *nbyte);
    if (kbuf == NULL) return EFAULT;

    *sc->status_ptr = 0xFF;

    sc->req->type = VIO_BLK_T_IN;
    sc->req->reserved = 0;
    sc->req->sector = blkno;

    sc->desc[0].addr = (uint64_t)kvtop(sc->req);
    sc->desc[0].len = sizeof(struct vio_blk_req);
    sc->desc[0].flags = VRING_DESC_F_NEXT;
    sc->desc[0].next = 1;

    sc->desc[1].addr = (uint64_t)kvtop(kbuf);
    sc->desc[1].len = (uint32_t)*nbyte;
    sc->desc[1].flags = VRING_DESC_F_NEXT | VRING_DESC_F_WRITE;
    sc->desc[1].next = 2;

    sc->desc[2].addr = (uint64_t)kvtop(sc->status_ptr);
    sc->desc[2].len = 1;
    sc->desc[2].flags = VRING_DESC_F_WRITE;
    sc->desc[2].next = 0;

    sc->avail->ring[sc->avail->idx % 16] = 0;
    __sync_synchronize();
    sc->avail->idx++;
    __sync_synchronize();

    bus_write_32(sc->base + VIO_MMIO_QUEUE_NOTIFY, 0);

    while (sc->used->idx == sc->last_used_idx) {
        sched_sleep(&sc->done_event);
    }
    sc->last_used_idx = sc->used->idx;

    int err = (*sc->status_ptr == VIO_BLK_S_OK) ? 0 : EIO;
    if (err) printf("vio_blk_read: error status %d\n", *sc->status_ptr);
    
    return err;
}

static int vio_blk_write(device_t dev, char* buf, size_t* nbyte, int blkno)
{
    struct vio_blk_softc* sc = device_private(dev);
    void* kbuf;
    
    kbuf = kmem_map(buf, *nbyte);
    if (kbuf == NULL) return EFAULT;

    *sc->status_ptr = 0xFF;

    sc->req->type = VIO_BLK_T_OUT;
    sc->req->reserved = 0;
    sc->req->sector = blkno;

    sc->desc[0].addr = (uint64_t)kvtop(sc->req);
    sc->desc[0].len = sizeof(struct vio_blk_req);
    sc->desc[0].flags = VRING_DESC_F_NEXT;
    sc->desc[0].next = 1;

    sc->desc[1].addr = (uint64_t)kvtop(kbuf);
    sc->desc[1].len = (uint32_t)*nbyte;
    sc->desc[1].flags = VRING_DESC_F_NEXT;
    sc->desc[1].next = 2;

    sc->desc[2].addr = (uint64_t)kvtop(sc->status_ptr);
    sc->desc[2].len = 1;
    sc->desc[2].flags = VRING_DESC_F_WRITE;
    sc->desc[2].next = 0;

    sc->avail->ring[sc->avail->idx % 16] = 0;
    __sync_synchronize();
    sc->avail->idx++;
    __sync_synchronize();

    bus_write_32(sc->base + VIO_MMIO_QUEUE_NOTIFY, 0);

    while (sc->used->idx == sc->last_used_idx) {
        sched_sleep(&sc->done_event);
    }
    sc->last_used_idx = sc->used->idx;

    int err = (*sc->status_ptr == VIO_BLK_S_OK) ? 0 : EIO;
    
    return err;
}
