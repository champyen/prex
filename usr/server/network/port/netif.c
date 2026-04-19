/*
 * Copyright 2018 Phoenix Systems
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

#include "lwip/opt.h"
#include "lwip/def.h"
#include "lwip/mem.h"
#include "lwip/pbuf.h"
#include "lwip/stats.h"
#include "lwip/snmp.h"
#include "lwip/etharp.h"
#include "lwip/sys.h"
#include "netif/etharp.h"

#include <sys/prex.h>
#include <stdlib.h>
#include <string.h>

#define IFNAME0 'e'
#define IFNAME1 't'

struct prex_netif {
    device_t dev;
};

static err_t low_level_output(struct netif *netif, struct pbuf *p) {
    struct prex_netif *px = netif->state;
    size_t len = p->tot_len;
    void *buf = malloc(len);
    if (!buf) return ERR_MEM;
    
    pbuf_copy_partial(p, buf, len, 0);
    device_write(px->dev, buf, &len, 0);
    free(buf);
    
    return ERR_OK;
}

static void input_thread(void *arg) {
    struct netif *netif = arg;
    struct prex_netif *px = netif->state;
    size_t len;
    struct pbuf *p;
    char *rx_buf = malloc(2048);

    if (!rx_buf) return;

    for (;;) {
        len = 2048;
        if (device_read(px->dev, rx_buf, &len, 0) == 0 && len > 0) {
            p = pbuf_alloc(PBUF_RAW, len, PBUF_POOL);
            if (p) {
                pbuf_take(p, rx_buf, len);
                if (netif->input(p, netif) != ERR_OK) {
                    pbuf_free(p);
                }
            }
        }
    }
}

err_t prex_netif_init(struct netif *netif) {
    struct prex_netif *px;
    device_t dev;

    if (device_open("eth0", 0, &dev) != 0)
        return ERR_IF;

    px = malloc(sizeof(struct prex_netif));
    if (!px) {
        device_close(dev);
        return ERR_MEM;
    }
    px->dev = dev;

    netif->state = px;
    netif->name[0] = IFNAME0;
    netif->name[1] = IFNAME1;
    netif->output = etharp_output;
    netif->linkoutput = low_level_output;
    netif->hwaddr_len = ETHARP_HWADDR_LEN;
    
    struct ifreq ifr;
    memset(&ifr, 0, sizeof(ifr));
    if (device_ioctl(dev, SIOCGIFHWADDR, &ifr) == 0) {
        memcpy(netif->hwaddr, ifr.ifr_ifru.ifru_data, ETHARP_HWADDR_LEN);
    } else {
        memset(netif->hwaddr, 0, ETHARP_HWADDR_LEN);
    }
    
    netif->mtu = 1500;
    netif->flags = NETIF_FLAG_BROADCAST | NETIF_FLAG_ETHARP | NETIF_FLAG_LINK_UP;

    sys_thread_new("netif_input", input_thread, netif, 4096, 4);

    return ERR_OK;
}
