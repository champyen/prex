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
#include <sys/socket.h>
#include <ipc/network.h>
#include <ipc/ipc.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>

static object_t net_obj = 0;

static int get_net_obj(void) {
    if (net_obj == 0) {
        if (object_lookup(OBJNAME_NETWORK, &net_obj) != 0)
            return -1;
    }
    return 0;
}

int socket(int domain, int type, int protocol) {
    struct net_msg m;
    if (get_net_obj() != 0) return -1;

    m.hdr.code = NET_SOCKET;
    m.domain = domain;
    m.type = type;
    m.protocol = protocol;

    if (msg_send(net_obj, &m, sizeof(m)) != 0) return -1;
    if (m.hdr.status != 0) {
        errno = m.hdr.status;
        return -1;
    }
    return m.socket;
}

int bind(int s, const struct sockaddr *name, socklen_t namelen) {
    struct net_msg m;
    if (get_net_obj() != 0) return -1;

    m.hdr.code = NET_BIND;
    m.socket = s;
    memcpy(&m.addr, name, namelen);
    m.addrlen = namelen;

    if (msg_send(net_obj, &m, sizeof(m)) != 0) return -1;
    if (m.hdr.status != 0) {
        errno = m.hdr.status;
        return -1;
    }
    return 0;
}

int connect(int s, const struct sockaddr *name, socklen_t namelen) {
    struct net_msg m;
    if (get_net_obj() != 0) return -1;

    m.hdr.code = NET_CONNECT;
    m.socket = s;
    memcpy(&m.addr, name, namelen);
    m.addrlen = namelen;

    if (msg_send(net_obj, &m, sizeof(m)) != 0) return -1;
    if (m.hdr.status != 0) {
        errno = m.hdr.status;
        return -1;
    }
    return 0;
}

ssize_t send(int s, const void *msg, size_t len, int flags) {
    struct net_msg m;
    if (get_net_obj() != 0) return -1;

    m.hdr.code = NET_SEND;
    m.socket = s;
    m.flags = flags;
    m.len = (len > 2048) ? 2048 : len;
    memcpy(m.data, msg, m.len);

    if (msg_send(net_obj, &m, sizeof(m)) != 0) return -1;
    if (m.hdr.status != 0) {
        errno = m.hdr.status;
        return -1;
    }
    return (ssize_t)m.len;
}

ssize_t recv(int s, void *buf, size_t len, int flags) {
    struct net_msg m;
    if (get_net_obj() != 0) return -1;

    m.hdr.code = NET_RECV;
    m.socket = s;
    m.flags = flags;
    m.len = (len > 2048) ? 2048 : len;

    if (msg_send(net_obj, &m, sizeof(m)) != 0) return -1;
    if (m.hdr.status != 0) {
        errno = m.hdr.status;
        return -1;
    }
    memcpy(buf, m.data, m.len);
    return (ssize_t)m.len;
}

int listen(int s, int backlog) {
    struct net_msg m;
    if (get_net_obj() != 0) return -1;

    m.hdr.code = NET_LISTEN;
    m.socket = s;
    m.backlog = backlog;

    if (msg_send(net_obj, &m, sizeof(m)) != 0) return -1;
    if (m.hdr.status != 0) {
        errno = m.hdr.status;
        return -1;
    }
    return 0;
}
