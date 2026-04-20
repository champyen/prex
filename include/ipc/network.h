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

#ifndef _IPC_NETWORK_H_
#define _IPC_NETWORK_H_

#include <sys/types.h>
#include <sys/socket.h>
#include <ipc/ipc.h>

/*
 * Object name
 */
#define OBJNAME_NETWORK "/serv/network"

/*
 * Message types
 */
#define NET_SOCKET      0x601
#define NET_BIND        0x602
#define NET_CONNECT     0x603
#define NET_LISTEN      0x604
#define NET_ACCEPT      0x605
#define NET_SEND        0x606
#define NET_RECV        0x607
#define NET_SENDTO      0x60c
#define NET_RECVFROM    0x60d
#define NET_SHUTDOWN    0x608
#define NET_CLOSE       0x609
#define NET_GETIFINFO   0x60a
#define NET_SETIFINFO   0x60b
#define NET_RESOLVE     0x60e

struct net_ifinfo {
    char name[16];
    uint32_t ip_addr;
    uint32_t netmask;
    uint32_t gateway;
    uint8_t  hwaddr[6];
    int      flags;
    int      index;
};

struct net_msg {
    struct msg_header hdr;
    int domain;
    int type;
    int protocol;
    int socket;
    int backlog;
    int flags;
    size_t len;
    struct sockaddr addr;
    socklen_t addrlen;
    char data[2048];
};

#endif /* !_IPC_NETWORK_H_ */
