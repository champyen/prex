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
 * vio_net.c - VirtIO Network Device Driver (MD)
 */

#include <driver.h>
#include <ddi.h>
#include <dki.h>
#include <types.h>
#include <vio_mmio.h>
#include <net.h>

#define DEBUG_VIO_NET
#ifdef DEBUG_VIO_NET
#define DPRINTF(a) printf a
#else
#define DPRINTF(a)
#endif

/* VirtIO Net Feature Bits */
#define VIRTIO_NET_F_MAC       5
#define VIRTIO_NET_F_STATUS    16

/* VirtIO Net VirtQueue Indices */
#define VIO_NET_VQ_RX          0
#define VIO_NET_VQ_TX          1
#define VIO_NET_VQ_MAX         2

/* VirtIO Device Status */
#define VIO_STATUS_ACKNOWLEDGE  1
#define VIO_STATUS_DRIVER       2
#define VIO_STATUS_DRIVER_OK    4
#define VIO_STATUS_FEATURES_OK  8

/* VirtQueue Descriptor Flags */
#define VRING_DESC_F_NEXT       1
#define VRING_DESC_F_WRITE      2

#define VQ_SIZE 16
#define PKT_BUF_SIZE 2048

struct vring_desc {
    uint64_t addr;
    uint32_t len;
    uint16_t flags;
    uint16_t next;
} __packed;

struct vring_avail {
    uint16_t flags;
    uint16_t idx;
    uint16_t ring[VQ_SIZE];
} __packed;

struct vring_used_elem {
    uint32_t id;
    uint32_t len;
} __packed;

struct vring_used {
    uint16_t flags;
    uint16_t idx;
    struct vring_used_elem ring[VQ_SIZE];
} __packed;

struct virtio_net_hdr {
    uint8_t  flags;
    uint8_t  gso_type;
    uint16_t hdr_len;
    uint16_t gso_size;
    uint16_t csum_start;
    uint16_t csum_offset;
} __packed;

struct vio_net_vq {
    volatile struct vring_desc* desc;
    volatile struct vring_avail* avail;
    volatile struct vring_used* used;
    uint16_t last_used_idx;
    uint16_t next_free;
};

struct vio_net_softc {
    device_t            net_dev;
    vaddr_t             base;
    int                 irq;
    irq_t               irq_handle;
    
    struct vio_net_vq   vqs[VIO_NET_VQ_MAX];
    uint8_t             mac[NET_ADDR_LEN];
    
    /* Shared buffers */
    struct virtio_net_hdr *tx_hdr;
    void                  *rx_pkts[VQ_SIZE];
    struct virtio_net_hdr *rx_hdrs[VQ_SIZE];
};

static int vio_net_open(void *priv) {
    return 0;
}

static void vio_net_close(void *priv) {
}

static int vio_net_xmit(void *priv, void *buf, size_t len) {
    struct vio_net_softc *sc = priv;
    struct vio_net_vq *vq = &sc->vqs[VIO_NET_VQ_TX];
    void *kbuf;

    kbuf = kmem_map(buf, len);
    if (kbuf == NULL) return EFAULT;

    memset(sc->tx_hdr, 0, sizeof(struct virtio_net_hdr));

    /* 
     * Fill descriptors for TX:
     * Desc 0: Header (Read-only for device)
     * Desc 1: Data (Read-only for device)
     */
    vq->desc[0].addr = (uint64_t)kvtop(sc->tx_hdr);
    vq->desc[0].len = sizeof(struct virtio_net_hdr);
    vq->desc[0].flags = VRING_DESC_F_NEXT;
    vq->desc[0].next = 1;

    vq->desc[1].addr = (uint64_t)kvtop(kbuf);
    vq->desc[1].len = (uint32_t)len;
    vq->desc[1].flags = 0;
    vq->desc[1].next = 0;

    vq->avail->ring[vq->avail->idx % VQ_SIZE] = 0;
    __sync_synchronize();
    vq->avail->idx++;
    __sync_synchronize();

    bus_write_32(sc->base + VIO_MMIO_QUEUE_NOTIFY, VIO_NET_VQ_TX);

    /* Wait for completion (simplified polling for now, or use event) */
    while (vq->used->idx == vq->last_used_idx);
    vq->last_used_idx = vq->used->idx;

    return 0;
}

static int vio_net_get_addr(void *priv, uint8_t *addr) {
    struct vio_net_softc *sc = priv;
    memcpy(addr, sc->mac, NET_ADDR_LEN);
    return 0;
}

static struct net_hw_if vio_net_hw_if = {
    vio_net_open,
    vio_net_close,
    vio_net_xmit,
    vio_net_get_addr,
    NULL, /* set_addr */
    NULL, /* set_promisc */
};

static int vio_net_isr(void* arg)
{
    struct vio_net_softc* sc = arg;
    uint32_t status = bus_read_32(sc->base + VIO_MMIO_IRQ_STATUS);
    if (status) {
        bus_write_32(sc->base + VIO_MMIO_IRQ_ACK, status);
        return INT_CONTINUE;
    }
    return INT_DONE;
}

static void vio_net_ist(void* arg)
{
    struct vio_net_softc* sc = arg;
    struct vio_net_vq *vq = &sc->vqs[VIO_NET_VQ_RX];

    while (vq->used->idx != vq->last_used_idx) {
        volatile struct vring_used_elem *ue = &vq->used->ring[vq->last_used_idx % VQ_SIZE];
        int id = ue->id;
        uint32_t len = ue->len;
        
        /* ue->len includes the virtio header size */
        if (len > sizeof(struct virtio_net_hdr)) {
            net_rx_complete(sc->net_dev, sc->rx_pkts[id], len - sizeof(struct virtio_net_hdr));
        }

        /* Put descriptor back to avail ring */
        vq->avail->ring[vq->avail->idx % VQ_SIZE] = id;
        __sync_synchronize();
        vq->avail->idx++;
        __sync_synchronize();
        
        vq->last_used_idx++;
    }
    bus_write_32(sc->base + VIO_MMIO_QUEUE_NOTIFY, VIO_NET_VQ_RX);
}

static int vio_net_init(struct driver *self)
{
    return 0;
}

struct driver vio_net_driver = {
    "vio_net",
    NULL,
    0,
    0,
    NULL,
    vio_net_init,
    NULL,
};

int vio_net_attach(vaddr_t base, int irq)
{
    struct vio_net_softc *sc;
    uint32_t status;

    sc = kmem_alloc(sizeof(struct vio_net_softc));
    if (sc == NULL) return -1;
    memset(sc, 0, sizeof(*sc));
    
    sc->base = base;
    sc->irq = irq;

    /* Reset device */
    bus_write_32(base + VIO_MMIO_STATUS, 0);

    /* Acknowledge */
    status = VIO_STATUS_ACKNOWLEDGE | VIO_STATUS_DRIVER;
    bus_write_32(base + VIO_MMIO_STATUS, status);

    /* Feature negotiation */
    uint32_t features = bus_read_32(base + VIO_MMIO_DEV_FEATURE);
    bus_write_32(base + VIO_MMIO_DRV_FEATURE, features & (1 << VIRTIO_NET_F_MAC));

    /* Tell device our page size */
    bus_write_32(base + VIO_MMIO_PAGE_SIZE, PAGE_SIZE);

    /* Setup VirtQueues */
    for (int i = 0; i < VIO_NET_VQ_MAX; i++) {
        bus_write_32(base + VIO_MMIO_QUEUE_SEL, i);
        
        paddr_t raw_pa = page_alloc(PAGE_SIZE * 2);
        void *vq_mem = ptokv(raw_pa);
        memset(vq_mem, 0, PAGE_SIZE * 2);
        
        sc->vqs[i].desc = (struct vring_desc*)vq_mem;
        sc->vqs[i].avail = (struct vring_avail*)((char*)vq_mem + VQ_SIZE * sizeof(struct vring_desc));
        sc->vqs[i].used = (struct vring_used*)((char*)vq_mem + PAGE_SIZE);
        sc->vqs[i].last_used_idx = 0;

        bus_write_32(base + VIO_MMIO_QUEUE_SIZE, VQ_SIZE);
        bus_write_32(base + VIO_MMIO_QUEUE_ALIGN, PAGE_SIZE);
        bus_write_32(base + VIO_MMIO_QUEUE_PFN, (uint32_t)(raw_pa >> 12));
    }

    /* Read MAC address from config space */
    for (int i = 0; i < NET_ADDR_LEN; i++) {
        sc->mac[i] = bus_read_8(base + VIO_MMIO_CFG + i);
    }

    /* Driver OK */
    status |= VIO_STATUS_DRIVER_OK;
    bus_write_32(base + VIO_MMIO_STATUS, status);

    /* MI Attach */
    sc->net_dev = net_attach("eth0", &vio_net_hw_if, sc);
    if (sc->net_dev == 0) {
        kmem_free(sc);
        return -1;
    }

    /* Setup RX buffers */
    struct vio_net_vq *rx_vq = &sc->vqs[VIO_NET_VQ_RX];
    for (int i = 0; i < VQ_SIZE / 2; i++) {
        int desc_idx = i * 2;
        sc->rx_hdrs[i] = kmem_alloc(sizeof(struct virtio_net_hdr));
        sc->rx_pkts[i] = kmem_alloc(PKT_BUF_SIZE);
        
        rx_vq->desc[desc_idx].addr = (uint64_t)kvtop(sc->rx_hdrs[i]);
        rx_vq->desc[desc_idx].len = sizeof(struct virtio_net_hdr);
        rx_vq->desc[desc_idx].flags = VRING_DESC_F_NEXT | VRING_DESC_F_WRITE;
        rx_vq->desc[desc_idx].next = desc_idx + 1;

        rx_vq->desc[desc_idx + 1].addr = (uint64_t)kvtop(sc->rx_pkts[i]);
        rx_vq->desc[desc_idx + 1].len = PKT_BUF_SIZE;
        rx_vq->desc[desc_idx + 1].flags = VRING_DESC_F_WRITE;
        rx_vq->desc[desc_idx + 1].next = 0;

        rx_vq->avail->ring[i] = desc_idx;
    }
    rx_vq->avail->idx = VQ_SIZE / 2;
    bus_write_32(base + VIO_MMIO_QUEUE_NOTIFY, VIO_NET_VQ_RX);

    sc->tx_hdr = kmem_alloc(sizeof(struct virtio_net_hdr));

    sc->irq_handle = irq_attach(irq, IPL_NET, 0, vio_net_isr, vio_net_ist, sc);

    DPRINTF(("VirtIO Net attached at 0x%lx, irq %d, MAC %02x:%02x:%02x:%02x:%02x:%02x\n",
           base, irq, sc->mac[0], sc->mac[1], sc->mac[2], sc->mac[3], sc->mac[4], sc->mac[5]));

    /* Simple TX test: send a dummy ARP-like broadcast packet */
    uint8_t dummy_pkt[42];
    memset(dummy_pkt, 0xFF, 6); /* Dest MAC: Broadcast */
    memcpy(dummy_pkt + 6, sc->mac, 6); /* Src MAC */
    dummy_pkt[12] = 0x08; dummy_pkt[13] = 0x06; /* Type: ARP */
    memset(dummy_pkt + 14, 0x00, 28); /* Dummy payload */
    
    DPRINTF(("VirtIO Net: Sending test broadcast packet...\n"));
    vio_net_xmit(sc, dummy_pkt, sizeof(dummy_pkt));

    return 0;
}
