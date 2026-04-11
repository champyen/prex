/*
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
 * audio.c - Machine-Independent Audio Driver
 */

#include <driver.h>
#include <audio.h>
#include <sys/audioio.h>

/* Default parameters */
#define AU_DEFAULT_RATE      AUDIO_SAMP_RATE_44K
#define AU_DEFAULT_CHANNELS  2
#define AU_DEFAULT_ENCODING  AUDIO_ENCODING_PCM_S16_LE

/* Circular buffer size */
#define AU_BUF_SIZE (32 * 1024)

struct aucb {
    char    *buf;
    size_t  size;
    size_t  head;
    size_t  tail;
    size_t  used;
    int     active;
    struct event event;
};

struct audio_softc {
    device_t            dev;
    const struct audio_hw_if *hw_if;
    void                *hw_priv;
    int                 flags;
    struct audio_info   info;
    struct aucb         play_cb;
    struct aucb         record_cb;
    int                 opened;
};

static int audio_open(device_t dev, int mode);
static int audio_close(device_t dev);
static int audio_read(device_t dev, char *buf, size_t *nbyte, int blkno);
static int audio_write(device_t dev, char *buf, size_t *nbyte, int blkno);
static int audio_ioctl(device_t dev, u_long cmd, void *arg);
static int audio_init(struct driver *self);

static struct devops audio_devops = {
    audio_open,
    audio_close,
    audio_read,
    audio_write,
    audio_ioctl,
    no_devctl,
};

/* 
 * The Class Driver: 
 * Used for kernel registration via drvtab.h.
 */
struct driver audio_driver = {
    "audio",
    NULL,
    0,
    0,
    NULL,
    audio_init,
    NULL,
};

/* 
 * The Instance Driver: 
 * Used by audio_attach to create /dev/audio instances.
 */
static struct driver audio_dev_driver = {
    "audio-device",
    &audio_devops,
    sizeof(struct audio_softc),
    0,
    NULL,
    NULL,
    NULL,
};

/* Driver initialization */
static int audio_init(struct driver *self) {
    return 0;
}

/* Buffer management */
static int aucb_init(struct aucb *cb, size_t size) {
    cb->buf = kmem_alloc(size);
    if (cb->buf == NULL)
        return ENOMEM;
    cb->size = size;
    cb->head = 0;
    cb->tail = 0;
    cb->used = 0;
    event_init(&cb->event, "audio");
    return 0;
}

static void audio_play_intr(void *priv) {
    struct audio_softc *sc = priv;
    struct aucb *cb = &sc->play_cb;
    
    /* Hardware finished a chunk */
    cb->active = 0;
    sched_wakeup(&cb->event);
}

static void audio_record_intr(void *priv) {
    struct audio_softc *sc = priv;
    struct aucb *cb = &sc->record_cb;
    
    /* Hardware filled a chunk */
    cb->active = 0;
    sched_wakeup(&cb->event);
}

static int audio_open(device_t dev, int mode) {
    struct audio_softc *sc = device_private(dev);

    if (sc->opened)
        return EBUSY;

    if (sc->hw_if->open) {
        int err = sc->hw_if->open(sc->hw_priv, mode);
        if (err) return err;
    }

    sc->opened = 1;
    
    /* Reset Playback buffer */
    sc->play_cb.head = 0;
    sc->play_cb.tail = 0;
    sc->play_cb.used = 0;
    sc->play_cb.active = 0;
    
    /* Reset Record buffer */
    sc->record_cb.head = 0;
    sc->record_cb.tail = 0;
    sc->record_cb.used = 0;
    sc->record_cb.active = 0;
    
    return 0;
}

static int audio_close(device_t dev) {
    struct audio_softc *sc = device_private(dev);

    if (sc->hw_if->close)
        sc->hw_if->close(sc->hw_priv);

    sc->opened = 0;
    return 0;
}

static int audio_write(device_t dev, char *buf, size_t *nbyte, int blkno) {
    struct audio_softc *sc = device_private(dev);
    struct aucb *cb = &sc->play_cb;

    if (*nbyte == 0) return 0;

    /* 
     * Start hardware output and wait for completion.
     * We use a loop and an 'active' flag to prevent the lost wakeup problem.
     */
    sched_lock();
    cb->active = 1;
    sc->hw_if->start_output(sc->hw_priv, buf, *nbyte, audio_play_intr);
    
    while (cb->active) {
        sched_sleep(&cb->event);
    }
    sched_unlock();

    /* We assume the hardware finished the whole chunk */
    return 0;
}

static int audio_read(device_t dev, char *buf, size_t *nbyte, int blkno) {
    struct audio_softc *sc = device_private(dev);
    struct aucb *cb = &sc->record_cb;
    size_t requested = *nbyte;
    size_t copied = 0;

    sched_lock();
    while (copied < requested) {
        size_t avail = cb->used;
        if (avail == 0) {
            /* Buffer empty, start hardware if not already active */
            if (!cb->active) {
                cb->active = 1;
                sc->hw_if->start_input(sc->hw_priv, cb->buf, cb->size, audio_record_intr);
            }
            sched_sleep(&cb->event);
            continue;
        }
        
        size_t chunk = requested - copied;
        if (chunk > avail) chunk = avail;

        /* Linear copy from circular buffer */
        size_t to_end = cb->size - cb->head;
        if (chunk > to_end) {
            memcpy(buf + copied, cb->buf + cb->head, to_end);
            memcpy(buf + copied + to_end, cb->buf, chunk - to_end);
        } else {
            memcpy(buf + copied, cb->buf + cb->head, chunk);
        }

        cb->head = (cb->head + chunk) % cb->size;
        cb->used -= chunk;
        copied += chunk;
    }
    sched_unlock();

    *nbyte = copied;
    return 0;
}

static int audio_ioctl(device_t dev, u_long cmd, void *arg) {
    struct audio_softc *sc = device_private(dev);
    struct audio_info *info;

    switch (cmd) {
    case AUDIO_GETINFO:
        memcpy(arg, &sc->info, sizeof(struct audio_info));
        return 0;

    case AUDIO_SETINFO:
        info = arg;
        
        /* Playback configuration */
        if (info->play.encoding != (u_int)-1) {
            struct audio_params params;
            params.sample_rate = info->play.sample_rate;
            params.channels = info->play.channels;
            params.encoding = info->play.encoding;
            
            if (sc->hw_if->set_params) {
                int err = sc->hw_if->set_params(sc->hw_priv, &params);
                if (err) return err;
            }
            
            sc->info.play.sample_rate = info->play.sample_rate;
            sc->info.play.channels = info->play.channels;
            sc->info.play.encoding = info->play.encoding;
        }

        /* Record configuration */
        if (info->record.encoding != (u_int)-1) {
             /* Reuse params structure or similar */
             /* Note: Some hardware has independent record/play params */
        }
        
        return 0;

    case AUDIO_DRAIN:
        while (sc->play_cb.used > 0) {
            sched_sleep(&sc->play_cb.event);
        }
        return 0;

    case AUDIO_FLUSH:
        sc->play_cb.head = 0;
        sc->play_cb.tail = 0;
        sc->play_cb.used = 0;
        sc->record_cb.head = 0;
        sc->record_cb.tail = 0;
        sc->record_cb.used = 0;
        if (sc->hw_if->stop_output)
            sc->hw_if->stop_output(sc->hw_priv);
        if (sc->hw_if->stop_input)
            sc->hw_if->stop_input(sc->hw_priv);
        sc->info.play.active = 0;
        sc->info.record.active = 0;
        return 0;

    default:
        return EINVAL;
    }
}

device_t audio_attach(const char *name, struct audio_hw_if *hw_if, void *hw_priv) {
    device_t dev;
    struct audio_softc *sc;

    dev = device_create(&audio_dev_driver, name, D_CHR);
    if (dev == 0)
        return 0;

    sc = device_private(dev);
    sc->dev = dev;
    sc->hw_if = hw_if;
    sc->hw_priv = hw_priv;
    sc->opened = 0;

    /* Initialize default info */
    memset(&sc->info, 0, sizeof(struct audio_info));
    sc->info.play.sample_rate = AU_DEFAULT_RATE;
    sc->info.play.channels = AU_DEFAULT_CHANNELS;
    sc->info.play.encoding = AU_DEFAULT_ENCODING;
    
    sc->info.record.sample_rate = AU_DEFAULT_RATE;
    sc->info.record.channels = AU_DEFAULT_CHANNELS;
    sc->info.record.encoding = AU_DEFAULT_ENCODING;
    
    sc->info.blocksize = AU_BUF_SIZE / 2;

    /* Initialize buffers */
    if (aucb_init(&sc->play_cb, AU_BUF_SIZE) != 0) {
        return 0;
    }
    if (aucb_init(&sc->record_cb, AU_BUF_SIZE) != 0) {
        return 0;
    }

    return dev;
}
