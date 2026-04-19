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
 * net.c - Machine-Independent Network Driver
 */

#include <driver.h>
#include <net.h>

#define SIOCGIFHWADDR   0x8927

struct net_ifreq {
    char name[16];
    char hwaddr[14];
};

#define NET_BUF_SIZE (64 * 1024)

struct net_softc {
    device_t            dev;
    const struct net_hw_if *hw_if;
    void                *hw_priv;
    int                 opened;
    
    char                *rx_buf;
    size_t              rx_head;
    size_t              rx_tail;
    size_t              rx_len;
    struct event        rx_event;
};

static int net_open(device_t dev, int mode);
static int net_close(device_t dev);
static int net_read(device_t dev, char *buf, size_t *nbyte, int blkno);
static int net_write(device_t dev, char *buf, size_t *nbyte, int blkno);
static int net_ioctl(device_t dev, u_long cmd, void *arg);

static struct devops net_devops = {
    net_open,
    net_close,
    net_read,
    net_write,
    net_ioctl,
    no_devctl,
};

static struct driver net_dev_driver = {
    "net-device",
    &net_devops,
    sizeof(struct net_softc),
    0,
    NULL,
    NULL,
    NULL,
};

static int net_open(device_t dev, int mode) {
    struct net_softc *sc = device_private(dev);

    if (sc->opened)
        return EBUSY;

    if (sc->hw_if->open) {
        int err = sc->hw_if->open(sc->hw_priv);
        if (err) return err;
    }

    sc->opened = 1;
    sc->rx_head = 0;
    sc->rx_tail = 0;
    sc->rx_len = 0;

    return 0;
}

static int net_close(device_t dev) {
    struct net_softc *sc = device_private(dev);

    if (sc->hw_if->close)
        sc->hw_if->close(sc->hw_priv);

    sc->opened = 0;
    return 0;
}

static int net_read(device_t dev, char *buf, size_t *nbyte, int blkno) {
    struct net_softc *sc = device_private(dev);
    size_t len = 0;

    sched_lock();
    while (sc->rx_len == 0) {
        if (sched_tsleep(&sc->rx_event, 0) == EINTR) {
            sched_unlock();
            return EINTR;
        }
    }
    
    /* Simplified read: In real implementation, read one packet or from ring buffer */
    len = (*nbyte < sc->rx_len) ? *nbyte : sc->rx_len;
    memcpy(buf, sc->rx_buf + sc->rx_head, len);
    sc->rx_head = (sc->rx_head + len) % NET_BUF_SIZE;
    sc->rx_len -= len;
    
    sched_unlock();

    *nbyte = len;
    return 0;
}

static int net_write(device_t dev, char *buf, size_t *nbyte, int blkno) {
    struct net_softc *sc = device_private(dev);
    int err;

    if (*nbyte > NET_MAX_FRAME)
        return EINVAL;

    err = sc->hw_if->xmit(sc->hw_priv, buf, *nbyte);
    return err;
}

static int net_ioctl(device_t dev, u_long cmd, void *arg) {
    struct net_softc *sc = device_private(dev);
    struct net_ifreq *ifr = arg;
    
    switch(cmd) {
    case SIOCGIFHWADDR:
        if (sc->hw_if->get_addr) {
            return sc->hw_if->get_addr(sc->hw_priv, (uint8_t *)ifr->hwaddr);
        }
        return ENOSYS;
    default:
        return EINVAL;
    }
}

/* 
 * Called by MD layer when a packet is received 
 */
void net_rx_complete(device_t dev, void *buf, size_t len) {
    struct net_softc *sc = device_private(dev);

    sched_lock();
    if (sc->rx_len + len <= NET_BUF_SIZE) {
        /* Simplified copy to buffer */
        memcpy(sc->rx_buf + sc->rx_tail, buf, len);
        sc->rx_tail = (sc->rx_tail + len) % NET_BUF_SIZE;
        sc->rx_len += len;
        sched_wakeup(&sc->rx_event);
    }
    sched_unlock();
}

device_t net_attach(const char *name, const struct net_hw_if *hw_if, void *hw_priv) {
    device_t dev;
    struct net_softc *sc;

    dev = device_create(&net_dev_driver, name, D_CHR);
    if (dev == 0)
        return 0;

    sc = device_private(dev);
    sc->dev = dev;
    sc->hw_if = hw_if;
    sc->hw_priv = hw_priv;
    sc->opened = 0;
    
    sc->rx_buf = kmem_alloc(NET_BUF_SIZE);
    if (sc->rx_buf == NULL)
        return 0;

    event_init(&sc->rx_event, "net-rx");

    return dev;
}
