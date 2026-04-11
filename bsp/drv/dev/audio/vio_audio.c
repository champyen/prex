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

#include <driver.h>
#include <ddi.h>
#include <dki.h>
#include <types.h>
#include <vio_mmio.h>
#include <audio.h>
#include <sys/audioio.h>

#ifdef DEBUG_VIO_AUDIO
#define DPRINTF(a) printf a
#else
#define DPRINTF(a)
#endif

/* VirtIO Sound Request Types */
#define VIO_SND_REQ_JACK_INFO          0x0001
#define VIO_SND_REQ_JACK_REMAP         0x0002
#define VIO_SND_REQ_PCM_INFO           0x0100
#define VIO_SND_REQ_PCM_SET_PARAMS     0x0101
#define VIO_SND_REQ_PCM_PREPARE        0x0102
#define VIO_SND_REQ_PCM_RELEASE        0x0103
#define VIO_SND_REQ_PCM_START          0x0104
#define VIO_SND_REQ_PCM_STOP           0x0105
#define VIO_SND_REQ_CHMAP_INFO         0x0200

/* VirtIO Status */
#define VIO_SND_S_OK                 0x8000
#define VIO_SND_S_BAD_MSG            0x8001
#define VIO_SND_S_NOT_SUPP           0x8002
#define VIO_SND_S_IO_ERR             0x8003

/* VirtIO Device Status */
#define VIO_STATUS_ACKNOWLEDGE       1
#define VIO_STATUS_DRIVER            2
#define VIO_STATUS_DRIVER_OK         4
#define VIO_STATUS_FEATURES_OK       8

/* VirtQueue Descriptor Flags */
#define VRING_DESC_F_NEXT            1
#define VRING_DESC_F_WRITE           2

/* VirtQueue Indices */
#define VIO_SND_VQ_CONTROL           0
#define VIO_SND_VQ_EVENT             1
#define VIO_SND_VQ_TX                2
#define VIO_SND_VQ_RX                3
#define VIO_SND_VQ_MAX               4

/* VirtIO Sound PCM Formats */
#define VIO_SND_PCM_FMT_U8           4
#define VIO_SND_PCM_FMT_S16          5

/* VirtIO Sound PCM Rates */
#define VIO_SND_PCM_RATE_44100       6
#define VIO_SND_PCM_RATE_48000       7

/* Stream IDs */
#define VIO_SND_STREAM_PLAY          0
#define VIO_SND_STREAM_REC           1

/* Default PCM Configuration */
#define VIO_SND_BUFFER_BYTES         16384
#define VIO_SND_PERIOD_BYTES         8192

/* VirtQueue Configuration */
#define VQ_SIZE                      16
#ifndef PAGE_SHIFT
#define PAGE_SHIFT                   12
#endif

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

struct virtio_snd_hdr {
    uint32_t code;
} __packed;

struct virtio_snd_pcm_set_params {
    struct virtio_snd_hdr hdr;
    uint32_t stream_id;
    uint32_t buffer_bytes;
    uint32_t period_bytes;
    uint32_t features;
    uint8_t channels;
    uint8_t format;
    uint8_t rate;
    uint8_t padding;
} __packed;

struct virtio_snd_pcm_hdr {
    struct virtio_snd_hdr hdr;
    uint32_t stream_id;
} __packed;

struct virtio_snd_pcm_xfer {
    uint32_t stream_id;
} __packed;

struct virtio_snd_pcm_status {
    uint32_t status;
    uint32_t latency_bytes;
} __packed;

struct virtio_snd_query_info {
    struct virtio_snd_hdr hdr;
    uint32_t start_id;
    uint32_t count;
    uint32_t size;
} __packed;

struct vio_audio_vq {
    volatile struct vring_desc* desc;
    volatile struct vring_avail* avail;
    volatile struct vring_used* used;
    uint16_t last_used_idx;
    uint16_t next_free;
};

struct vio_audio_softc {
    device_t dev;
    vaddr_t base;
    int irq;
    irq_t irq_handle;
    struct event ctrl_event;
    struct event tx_event;

    struct vio_audio_vq vqs[VIO_SND_VQ_MAX];

    /* Shared buffers for command responses */
    void *ctrl_req;
    struct virtio_snd_hdr *resp_hdr;
    struct virtio_snd_pcm_status *pcm_status;
    struct virtio_snd_pcm_xfer *xfer;
    
    int pcm_started;
    void (*play_intr)(void *);
};

static int vio_audio_open(void *priv, int mode);
static void vio_audio_close(void *priv);
static int vio_audio_set_params(void *priv, struct audio_params *params);
static int vio_audio_start_output(void *priv, void *block, size_t blksize, void (*intr)(void *));
static int vio_audio_stop_output(void *priv);

static int vio_audio_set_volume(void *priv, uint8_t volume);

static struct audio_hw_if vio_audio_hw_if = {
    vio_audio_open,
    vio_audio_close,
    vio_audio_set_params,
    vio_audio_start_output,
    vio_audio_stop_output,
    NULL, /* start_input */
    NULL, /* stop_input */
    vio_audio_set_volume,
};

static int vio_audio_set_volume(void *priv, uint8_t volume)
{
    return 0;
}

static int vio_audio_isr(void* arg)
{
    struct vio_audio_softc* sc = arg;
    uint32_t status = bus_read_32(sc->base + VIO_MMIO_IRQ_STATUS);
    if (status) {
        bus_write_32(sc->base + VIO_MMIO_IRQ_ACK, status);
        return INT_CONTINUE;
    }
    return INT_DONE;
}

static void vio_audio_ist(void* arg)
{
    struct vio_audio_softc* sc = arg;
    
    /* Check Control VQ */
    if (sc->vqs[VIO_SND_VQ_CONTROL].used->idx != sc->vqs[VIO_SND_VQ_CONTROL].last_used_idx) {
        sc->vqs[VIO_SND_VQ_CONTROL].last_used_idx = sc->vqs[VIO_SND_VQ_CONTROL].used->idx;
        sched_wakeup(&sc->ctrl_event);
    }

    /* Check TX VQ */
    while (sc->vqs[VIO_SND_VQ_TX].used->idx != sc->vqs[VIO_SND_VQ_TX].last_used_idx) {
        sc->vqs[VIO_SND_VQ_TX].last_used_idx++;
        if (sc->play_intr)
            sc->play_intr(device_private(sc->dev));
    }
}

static int vio_audio_send_ctrl(struct vio_audio_softc *sc, void *req, size_t req_size)
{
    struct vio_audio_vq *vq = &sc->vqs[VIO_SND_VQ_CONTROL];

    memcpy(sc->ctrl_req, req, req_size);

    vq->desc[0].addr = (uint64_t)kvtop(sc->ctrl_req);
    vq->desc[0].len = (uint32_t)req_size;
    vq->desc[0].flags = VRING_DESC_F_NEXT;
    vq->desc[0].next = 1;

    vq->desc[1].addr = (uint64_t)kvtop(sc->resp_hdr);
    vq->desc[1].len = 512;
    vq->desc[1].flags = VRING_DESC_F_WRITE;
    vq->desc[1].next = 0;

    vq->avail->ring[vq->avail->idx % VQ_SIZE] = 0;
    __sync_synchronize();
    vq->avail->idx++;
    __sync_synchronize();

    sched_lock();
    bus_write_32(sc->base + VIO_MMIO_QUEUE_NOTIFY, VIO_SND_VQ_CONTROL);
    sched_tsleep(&sc->ctrl_event, 1000);
    sched_unlock();

    if (sc->resp_hdr->code != VIO_SND_S_OK) {
        return EIO;
    }
    return 0;
}

static int vio_audio_open(void *priv, int mode)
{
    struct vio_audio_softc *sc = priv;
    struct virtio_snd_query_info req;

    memset(&req, 0, sizeof(req));
    req.hdr.code = VIO_SND_REQ_PCM_INFO;
    req.start_id = 0;
    req.count = 1;
    req.size = 128;

    return vio_audio_send_ctrl(sc, &req, sizeof(req));
}

static void vio_audio_close(void *priv)
{
    struct vio_audio_softc *sc = priv;
    struct virtio_snd_pcm_hdr req;

    memset(&req, 0, sizeof(req));
    req.hdr.code = VIO_SND_REQ_PCM_RELEASE;
    req.stream_id = VIO_SND_STREAM_PLAY;
    sc->pcm_started = 0;

    vio_audio_send_ctrl(sc, &req, sizeof(req));
}

static int vio_audio_set_params(void *priv, struct audio_params *params)
{
    struct vio_audio_softc *sc = priv;
    struct virtio_snd_pcm_set_params req;

    memset(&req, 0, sizeof(req));
    req.hdr.code = VIO_SND_REQ_PCM_SET_PARAMS;
    req.stream_id = VIO_SND_STREAM_PLAY;
    req.buffer_bytes = VIO_SND_BUFFER_BYTES;
    req.period_bytes = VIO_SND_PERIOD_BYTES;
    req.channels = params->channels;

    if (params->encoding == AUDIO_ENCODING_PCM_S16_LE)
        req.format = VIO_SND_PCM_FMT_S16;
    else
        req.format = VIO_SND_PCM_FMT_U8;

    if (params->sample_rate == AUDIO_SAMP_RATE_44K)
        req.rate = VIO_SND_PCM_RATE_44100;
    else
        req.rate = VIO_SND_PCM_RATE_48000;

    int err = vio_audio_send_ctrl(sc, &req, sizeof(req));
    if (err) return err;

    struct virtio_snd_pcm_hdr prep_req;
    memset(&prep_req, 0, sizeof(prep_req));
    prep_req.hdr.code = VIO_SND_REQ_PCM_PREPARE;
    prep_req.stream_id = VIO_SND_STREAM_PLAY;
    
    return vio_audio_send_ctrl(sc, &prep_req, sizeof(prep_req));
}

static int vio_audio_start_output(void *priv, void *block, size_t blksize, void (*intr)(void *))
{
    struct vio_audio_softc *sc = priv;
    struct vio_audio_vq *vq = &sc->vqs[VIO_SND_VQ_TX];
    struct virtio_snd_pcm_hdr start_req;
    void *kbuf;

    sc->play_intr = intr;

    if (!sc->pcm_started) {
        memset(&start_req, 0, sizeof(start_req));
        start_req.hdr.code = VIO_SND_REQ_PCM_START;
        start_req.stream_id = VIO_SND_STREAM_PLAY;
        vio_audio_send_ctrl(sc, &start_req, sizeof(start_req));
        sc->pcm_started = 1;
    }

    kbuf = kmem_map(block, blksize);
    if (kbuf == NULL)
        return EFAULT;

    int head = vq->next_free;
    sc->xfer->stream_id = VIO_SND_STREAM_PLAY;
    
    vq->desc[head].addr = (uint64_t)kvtop(sc->xfer);
    vq->desc[head].len = sizeof(struct virtio_snd_pcm_xfer);
    vq->desc[head].flags = VRING_DESC_F_NEXT;
    vq->desc[head].next = (head + 1) % VQ_SIZE;

    int d1 = (head + 1) % VQ_SIZE;
    vq->desc[d1].addr = (uint64_t)kvtop(kbuf);
    vq->desc[d1].len = (uint32_t)blksize;
    vq->desc[d1].flags = VRING_DESC_F_NEXT;
    vq->desc[d1].next = (head + 2) % VQ_SIZE;

    int d2 = (head + 2) % VQ_SIZE;
    vq->desc[d2].addr = (uint64_t)kvtop(sc->pcm_status);
    vq->desc[d2].len = sizeof(struct virtio_snd_pcm_status);
    vq->desc[d2].flags = VRING_DESC_F_WRITE;
    vq->desc[d2].next = 0;

    vq->next_free = (head + 3) % VQ_SIZE;

    vq->avail->ring[vq->avail->idx % VQ_SIZE] = head;
    __sync_synchronize();
    vq->avail->idx++;
    __sync_synchronize();

    bus_write_32(sc->base + VIO_MMIO_QUEUE_NOTIFY, VIO_SND_VQ_TX);

    return 0;
}

static int vio_audio_stop_output(void *priv)
{
    struct vio_audio_softc *sc = priv;
    struct virtio_snd_pcm_hdr req;

    if (sc->pcm_started) {
        memset(&req, 0, sizeof(req));
        req.hdr.code = VIO_SND_REQ_PCM_STOP;
        req.stream_id = VIO_SND_STREAM_PLAY;
        sc->pcm_started = 0;
        return vio_audio_send_ctrl(sc, &req, sizeof(req));
    }
    return 0;
}

static int vio_audio_init(struct driver *self)
{
    return 0;
}

struct driver vio_audio_driver = {
    "vio_audio",
    NULL,
    0,
    0,
    NULL,
    vio_audio_init,
    NULL,
};

int vio_audio_attach(vaddr_t base, int irq)
{
    struct vio_audio_softc *sc;
    device_t dev;
    uint32_t status;

    sc = kmem_alloc(sizeof(struct vio_audio_softc));
    if (sc == NULL) return -1;
    memset(sc, 0, sizeof(*sc));
    
    sc->base = base;
    sc->irq = irq;

    dev = audio_attach("audio", &vio_audio_hw_if, sc);
    if (dev == 0) {
        kmem_free(sc);
        return -1;
    }
    sc->dev = dev;

    event_init(&sc->ctrl_event, "vio_audio_ctrl");
    event_init(&sc->tx_event, "vio_audio_tx");

    bus_write_32(base + VIO_MMIO_STATUS, 0);
    status = VIO_STATUS_ACKNOWLEDGE | VIO_STATUS_DRIVER;
    bus_write_32(base + VIO_MMIO_STATUS, status);

    uint32_t f0 = bus_read_32(base + VIO_MMIO_DEV_FEATURE);
    bus_write_32(base + VIO_MMIO_DRV_FEATURE, f0);

    bus_write_32(base + VIO_MMIO_PAGE_SIZE, 4096);
    for (int i = 0; i < VIO_SND_VQ_MAX; i++) {
        bus_write_32(base + VIO_MMIO_QUEUE_SEL, i);
        uint32_t q_max = bus_read_32(base + VIO_MMIO_QUEUE_NUM_MAX);
        if (q_max == 0) continue;

        paddr_t raw_pa = page_alloc(PAGE_SIZE * 2);
        paddr_t vq_pa = raw_pa;
        void *vq_mem = ptokv(vq_pa);
        memset(vq_mem, 0, PAGE_SIZE * 2);
        
        sc->vqs[i].desc = (struct vring_desc*)vq_mem;
        sc->vqs[i].avail = (struct vring_avail*)((char*)vq_mem + VQ_SIZE * sizeof(struct vring_desc));
        sc->vqs[i].used = (struct vring_used*)((char*)vq_mem + PAGE_SIZE);
        sc->vqs[i].last_used_idx = 0;
        sc->vqs[i].next_free = 0;

        bus_write_32(base + VIO_MMIO_QUEUE_SIZE, VQ_SIZE);
        bus_write_32(base + VIO_MMIO_QUEUE_ALIGN, PAGE_SIZE);
        bus_write_32(base + VIO_MMIO_QUEUE_PFN, (uint32_t)(vq_pa >> 12));
    }

    status |= VIO_STATUS_DRIVER_OK;
    bus_write_32(base + VIO_MMIO_STATUS, status);

    sc->irq_handle = irq_attach(irq, IPL_AUDIO, 0, vio_audio_isr, vio_audio_ist, sc);

    paddr_t buf_pa = page_alloc(PAGE_SIZE);
    sc->ctrl_req = ptokv(buf_pa);
    sc->resp_hdr = (struct virtio_snd_hdr*)((char*)sc->ctrl_req + 512);
    sc->pcm_status = (struct virtio_snd_pcm_status*)((char*)sc->ctrl_req + 1024);
    sc->xfer = (struct virtio_snd_pcm_xfer*)((char*)sc->ctrl_req + 1536);
    sc->pcm_started = 0;

    DPRINTF(("VirtIO Audio attached at 0x%lx, irq %d\n", base, irq));
    return 0;
}
