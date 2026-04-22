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

#include "lwipopts.h"
#include "lwip/init.h"
#include "lwip/tcpip.h"
#include "lwip/sockets.h"
#include "lwip/netif.h"
#include "lwip/dhcp.h"
#include "lwip/dns.h"
#include "lwip/netdb.h"

#include <sys/prex.h>
#include <ipc/ipc.h>
#include <ipc/network.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern err_t prex_netif_init(struct netif *netif);

static struct netif prex_netif;
static object_t net_obj;

static void tcpip_init_done(void *arg) {
    sys_sem_t *sem = arg;
    sys_sem_signal(sem);
}

static void ip_monitor(void *arg) {
    /* Monitor IP binding */
    for (int i = 0; i < 100; i++) {
        if (!ip4_addr_isany_val(*netif_ip4_addr(&prex_netif))) {
            uint32_t ip = ip4_addr_get_u32(netif_ip4_addr(&prex_netif));
            char log_buf[64];
            sprintf(log_buf, "network: IP bound: %d.%d.%d.%d\n",
                    (int)(ip & 0xff), (int)((ip >> 8) & 0xff),
                    (int)((ip >> 16) & 0xff), (int)((ip >> 24) & 0xff));
            //sys_log(log_buf);

            /* Log DNS servers */
            for (int n = 0; n < DNS_MAX_SERVERS; n++) {
                const ip_addr_t *dns = dns_getserver(n);
                if (!ip_addr_isany(dns)) {
                    uint32_t dns_ip = ip4_addr_get_u32(ip_2_ip4(dns));
                    sprintf(log_buf, "network: DNS server %d: %d.%d.%d.%d\n", n,
                            (int)(dns_ip & 0xff), (int)((dns_ip >> 8) & 0xff),
                            (int)((dns_ip >> 16) & 0xff), (int)((dns_ip >> 24) & 0xff));
                    //sys_log(log_buf);
                }
            }
            break;
        }
        sys_msleep(500);
    }
}

int main(int argc, char **argv) {
    sys_sem_t init_sem;
    struct net_msg m;

    //sys_log("Network server starting...\n");

    if (object_create(OBJNAME_NETWORK, &net_obj) != 0) {
        fprintf(stderr, "network: failed to create object\n");
        return 1;
    }

    if (sys_sem_new(&init_sem, 0) != ERR_OK) return 1;
    tcpip_init(tcpip_init_done, &init_sem);
    sys_arch_sem_wait(&init_sem, 0);
    sys_sem_free(&init_sem);

    if (netif_add(&prex_netif, NULL, NULL, NULL, NULL, prex_netif_init, tcpip_input) == NULL) {
        //sys_log("network: failed to add netif\n");
        return 1;
    }
    netif_set_default(&prex_netif);

    netif_set_up(&prex_netif);

    //sys_log("network: starting DHCP...\n");
    dhcp_start(&prex_netif);

    //sys_log("Network server initialized\n");

    sys_thread_new("ip_monitor", ip_monitor, NULL, 4096, 0);

    for (;;) {
        if (msg_receive(net_obj, &m, sizeof(m)) != 0)
            continue;

        switch (m.hdr.code) {
        case NET_SOCKET:
            m.socket = lwip_socket(m.domain, m.type, m.protocol);
            m.hdr.status = (m.socket < 0) ? errno : 0;
            break;
        case NET_BIND:
            m.hdr.status = lwip_bind(m.socket, &m.addr, m.addrlen);
            if (m.hdr.status < 0) m.hdr.status = errno;
            break;
        case NET_CONNECT:
            m.hdr.status = lwip_connect(m.socket, &m.addr, m.addrlen);
            if (m.hdr.status < 0) m.hdr.status = errno;
            break;
        case NET_SEND:
            m.len = lwip_send(m.socket, m.data, m.len, m.flags);
            m.hdr.status = (m.len < 0) ? errno : 0;
            break;
        case NET_RECV:
            m.len = lwip_recv(m.socket, m.data, m.len, m.flags);
            m.hdr.status = (m.len < 0) ? errno : 0;
            break;
        case NET_SENDTO:
            m.len = lwip_sendto(m.socket, m.data, m.len, m.flags, &m.addr, m.addrlen);
            m.hdr.status = (m.len < 0) ? errno : 0;
            break;
        case NET_RECVFROM:
            m.len = lwip_recvfrom(m.socket, m.data, m.len, m.flags, &m.addr, &m.addrlen);
            m.hdr.status = (m.len < 0) ? errno : 0;
            break;
        case NET_SHUTDOWN:
            m.hdr.status = lwip_shutdown(m.socket, m.flags);
            if (m.hdr.status < 0) m.hdr.status = errno;
            break;
        case NET_CLOSE:
            m.hdr.status = lwip_close(m.socket);
            if (m.hdr.status < 0) m.hdr.status = errno;
            break;
        case NET_GETIFINFO:
            {
                char ifname[16];
                strncpy(ifname, m.data, 15);
                ifname[15] = '\0';

                struct netif *netif = netif_find(ifname);
                if (netif) {
                    struct net_ifinfo *info = (struct net_ifinfo *)m.data;
                    uint32_t ip = ip4_addr_get_u32(netif_ip4_addr(netif));
                    uint32_t nm = ip4_addr_get_u32(netif_ip4_netmask(netif));
                    uint32_t gw = ip4_addr_get_u32(netif_ip4_gw(netif));
                    uint8_t hw[6];
                    memcpy(hw, netif->hwaddr, 6);
                    int flags = netif->flags;

                    memset(info, 0, sizeof(*info));
                    strncpy(info->name, ifname, 15);
                    info->name[15] = '\0';
                    info->ip_addr = ip;
                    info->netmask = nm;
                    info->gateway = gw;
                    memcpy(info->hwaddr, hw, 6);
                    info->flags = flags;
                    m.hdr.status = 0;
                } else {
                    m.hdr.status = ENODEV;
                }
            }
            break;
        case NET_SETIFINFO:
            {
                struct net_ifinfo *info = (struct net_ifinfo *)m.data;
                struct netif *netif = netif_find(info->name);
                if (netif) {
                    ip4_addr_t ip, mask, gw;
                    ip4_addr_set_u32(&ip, info->ip_addr);
                    ip4_addr_set_u32(&mask, info->netmask);
                    ip4_addr_set_u32(&gw, info->gateway);
                    netif_set_addr(netif, &ip, &mask, &gw);
                    m.hdr.status = 0;
                } else {
                    m.hdr.status = ENODEV;
                }
            }
            break;
        case NET_RESOLVE:
            {
                char hostname[256];
                strncpy(hostname, m.data, 255);
                hostname[255] = '\0';
                
                struct hostent *he = lwip_gethostbyname(hostname);
                if (he && he->h_addr_list[0]) {
                    uint32_t *ip_out = (uint32_t *)m.data;
                    memcpy(ip_out, he->h_addr_list[0], 4);
                    m.hdr.status = 0;
                } else {
                    m.hdr.status = EHOSTUNREACH;
                }
            }
            break;
        default:
            m.hdr.status = EINVAL;
            break;
        }

        msg_reply(net_obj, &m, sizeof(m));
    }

    return 0;
}
