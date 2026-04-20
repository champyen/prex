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
#include <stdio.h>

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

static int is_ip_address(const char *s) {
    int a, b, c, d;
    if (sscanf(s, "%d.%d.%d.%d", &a, &b, &c, &d) != 4) return 0;
    return 1;
}

struct hostent *gethostbyname(const char *name) {
    static struct hostent he;
    static struct in_addr addr;
    static char *addr_list[2];
    struct net_msg m;

    if (is_ip_address(name)) {
        int a, b, c, d;
        sscanf(name, "%d.%d.%d.%d", &a, &b, &c, &d);
        addr.s_addr = (uint32_t)((a & 0xff) | ((b & 0xff) << 8) | ((c & 0xff) << 16) | ((d & 0xff) << 24));
    } else {
        if (get_net_obj() != 0) return NULL;

        m.hdr.code = NET_RESOLVE;
        strncpy(m.data, name, 255);
        m.data[255] = '\0';

        if (msg_send(net_obj, &m, sizeof(m)) != 0) return NULL;
        if (m.hdr.status != 0) {
            errno = m.hdr.status;
            return NULL;
        }
        memcpy(&addr.s_addr, m.data, 4);
    }

    he.h_name = (char *)name;
    he.h_addrtype = AF_INET;
    he.h_length = 4;
    addr_list[0] = (char *)&addr;
    addr_list[1] = NULL;
    he.h_addr_list = addr_list;

    return &he;
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

ssize_t sendto(int s, const void *msg, size_t len, int flags, const struct sockaddr *to, socklen_t tolen) {
    struct net_msg m;
    if (get_net_obj() != 0) return -1;

    m.hdr.code = NET_SENDTO;
    m.socket = s;
    m.flags = flags;
    m.len = (len > 2048) ? 2048 : len;
    memcpy(m.data, msg, m.len);
    memcpy(&m.addr, to, tolen);
    m.addrlen = tolen;

    if (msg_send(net_obj, &m, sizeof(m)) != 0) return -1;
    if (m.hdr.status != 0) {
        errno = m.hdr.status;
        return -1;
    }
    return (ssize_t)m.len;
}

ssize_t recvfrom(int s, void *buf, size_t len, int flags, struct sockaddr *from, socklen_t *fromlen) {
    struct net_msg m;
    if (get_net_obj() != 0) return -1;

    m.hdr.code = NET_RECVFROM;
    m.socket = s;
    m.flags = flags;
    m.len = (len > 2048) ? 2048 : len;
    if (fromlen) m.addrlen = *fromlen;

    if (msg_send(net_obj, &m, sizeof(m)) != 0) return -1;
    if (m.hdr.status != 0) {
        errno = m.hdr.status;
        return -1;
    }
    memcpy(buf, m.data, m.len);
    if (from && fromlen) {
        memcpy(from, &m.addr, m.addrlen);
        *fromlen = m.addrlen;
    }
    return (ssize_t)m.len;
}

int shutdown(int s, int how) {
    struct net_msg m;
    if (get_net_obj() != 0) return -1;

    m.hdr.code = NET_SHUTDOWN;
    m.socket = s;
    m.flags = how;

    if (msg_send(net_obj, &m, sizeof(m)) != 0) return -1;
    if (m.hdr.status != 0) {
        errno = m.hdr.status;
        return -1;
    }
    return 0;
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
