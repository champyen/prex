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

#include <sys/prex.h>
#include <ipc/ipc.h>
#include <ipc/network.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

static void print_ip(uint32_t ip) {
    printf("%d.%d.%d.%d", 
        (int)(ip & 0xff), 
        (int)((ip >> 8) & 0xff), 
        (int)((ip >> 16) & 0xff), 
        (int)((ip >> 24) & 0xff));
}

static uint32_t parse_ip(const char *s) {
    int a, b, c, d;
    if (sscanf(s, "%d.%d.%d.%d", &a, &b, &c, &d) != 4) return 0;
    return (uint32_t)((a & 0xff) | ((b & 0xff) << 8) | ((c & 0xff) << 16) | ((d & 0xff) << 24));
}

int main(int argc, char *argv[]) {
    object_t net_obj;
    struct net_msg m;
    struct net_ifinfo *info;

    if (object_lookup(OBJNAME_NETWORK, &net_obj) != 0) {
        fprintf(stderr, "ifconfig: network server not found\n");
        return 1;
    }

    if (argc < 2) {
        /* List all interfaces? For now just try common names */
        const char *ifaces[] = {"et0", "et1", "lo0", NULL};
        int i;
        for (i = 0; ifaces[i]; i++) {
            memset(&m, 0, sizeof(m));
            m.hdr.code = NET_GETIFINFO;
            strncpy(m.data, ifaces[i], 15);
            if (msg_send(net_obj, &m, sizeof(m)) == 0 && m.hdr.status == 0) {
                info = (struct net_ifinfo *)m.data;
                printf("%s: flags=%x\n", info->name, info->flags);
                printf("        inet "); print_ip(info->ip_addr);
                printf("  netmask "); print_ip(info->netmask);
                printf("  gateway "); print_ip(info->gateway);
                printf("\n        ether %02x:%02x:%02x:%02x:%02x:%02x\n",
                    info->hwaddr[0], info->hwaddr[1], info->hwaddr[2],
                    info->hwaddr[3], info->hwaddr[4], info->hwaddr[5]);
            }
        }
        return 0;
    }

    if (argc == 2) {
        memset(&m, 0, sizeof(m));
        m.hdr.code = NET_GETIFINFO;
        strncpy(m.data, argv[1], 15);
        if (msg_send(net_obj, &m, sizeof(m)) != 0 || m.hdr.status != 0) {
            fprintf(stderr, "ifconfig: failed to get info for %s\n", argv[1]);
            return 1;
        }
        info = (struct net_ifinfo *)m.data;
        printf("%s: flags=%x\n", info->name, info->flags);
        printf("        inet "); print_ip(info->ip_addr);
        printf("  netmask "); print_ip(info->netmask);
        printf("  gateway "); print_ip(info->gateway);
        printf("\n        ether %02x:%02x:%02x:%02x:%02x:%02x\n",
            info->hwaddr[0], info->hwaddr[1], info->hwaddr[2],
            info->hwaddr[3], info->hwaddr[4], info->hwaddr[5]);
        return 0;
    }

    /* Set info - very basic implementation: ifconfig <if> <ip> <netmask> <gw> */
    if (argc < 5) {
        fprintf(stderr, "usage: ifconfig <ifname> <ip> <netmask> <gw>\n");
        return 1;
    }
    memset(&m, 0, sizeof(m));
    info = (struct net_ifinfo *)m.data;
    strncpy(info->name, argv[1], 15);
    info->ip_addr = parse_ip(argv[2]);
    info->netmask = parse_ip(argv[3]);
    info->gateway = parse_ip(argv[4]);
    
    m.hdr.code = NET_SETIFINFO;
    if (msg_send(net_obj, &m, sizeof(m)) != 0 || m.hdr.status != 0) {
        fprintf(stderr, "ifconfig: failed to set info for %s\n", info->name);
        return 1;
    }

    return 0;
}
