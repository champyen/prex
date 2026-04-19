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

int main(int argc, char **argv) {
    sys_sem_t init_sem;
    struct net_msg m;

    sys_log("Network server starting...\n");

    if (object_create(OBJNAME_NETWORK, &net_obj) != 0) {
        fprintf(stderr, "network: failed to create object\n");
        return 1;
    }

    if (sys_sem_new(&init_sem, 0) != ERR_OK) return 1;
    tcpip_init(tcpip_init_done, &init_sem);
    sys_arch_sem_wait(&init_sem, 0);
    sys_sem_free(&init_sem);

    if (netif_add(&prex_netif, NULL, NULL, NULL, NULL, prex_netif_init, tcpip_input) == NULL) {
        fprintf(stderr, "network: failed to add netif\n");
        return 1;
    }
    netif_set_default(&prex_netif);
    netif_set_up(&prex_netif);

    sys_log("Network server initialized\n");

    /* Simple self-test */
    int test_sock = lwip_socket(AF_INET, SOCK_DGRAM, 0);
    char msg[128];
    if (test_sock >= 0) {
        sprintf(msg, "network: self-test UDP socket created successfully (fd=%d)\n", test_sock);
        sys_log(msg);
        lwip_close(test_sock);
    } else {
        sprintf(msg, "network: self-test UDP socket failed (errno=%d)\n", errno);
        sys_log(msg);
    }

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
        case NET_CLOSE:
            m.hdr.status = lwip_close(m.socket);
            if (m.hdr.status < 0) m.hdr.status = errno;
            break;
        default:
            m.hdr.status = EINVAL;
            break;
        }

        msg_reply(net_obj, &m, sizeof(m));
    }

    return 0;
}
