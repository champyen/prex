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
#include <sys/time.h>
#include <sys/endian.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

/* ICMP types */
#define ICMP_ECHOREPLY  0
#define ICMP_ECHO       8

struct icmp_hdr {
    uint8_t  type;
    uint8_t  code;
    uint16_t chksum;
    uint16_t id;
    uint16_t seq;
} __attribute__((packed));

struct ip_hdr {
    uint8_t  v_hl;
    uint8_t  tos;
    uint16_t len;
    uint16_t id;
    uint16_t off;
    uint8_t  ttl;
    uint8_t  proto;
    uint16_t chksum;
    uint32_t src;
    uint32_t dest;
} __attribute__((packed));

static uint16_t in_cksum(uint16_t *addr, int len) {
    int nleft = len;
    uint32_t sum = 0;
    uint16_t *w = addr;
    uint16_t answer = 0;

    while (nleft > 1) {
        sum += *w++;
        nleft -= 2;
    }
    if (nleft == 1) {
        *(uint8_t *)(&answer) = *(uint8_t *)w;
        sum += answer;
    }
    sum = (sum >> 16) + (sum & 0xffff);
    sum += (sum >> 16);
    answer = ~sum;
    return answer;
}

static char *local_inet_ntoa(struct in_addr in) {
    static char buf[16];
    unsigned char *bytes = (unsigned char *)&in.s_addr;
    sprintf(buf, "%d.%d.%d.%d", bytes[0], bytes[1], bytes[2], bytes[3]);
    return buf;
}

int ping_main(int argc, char *argv[]) {
    int s;
    struct sockaddr_in to;
    struct icmp_hdr *icmp;
    char packet[64];
    char recv_buf[128];
    struct hostent *he;
    int i, count = 4;
    struct timeval tv_start, tv_end;
    long rtt;

    if (argc < 2) {
        printf("usage: ping <hostname>\n");
        return 1;
    }

    he = gethostbyname(argv[1]);
    if (he == NULL) {
        printf("ping: unknown host %s\n", argv[1]);
        return 1;
    }

    s = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP);
    if (s < 0) {
        perror("ping: socket");
        return 1;
    }

    memset(&to, 0, sizeof(to));
    to.sin_family = AF_INET;
    memcpy(&to.sin_addr.s_addr, he->h_addr, 4);

    printf("PING %s (%s): 56 data bytes\n", argv[1], local_inet_ntoa(to.sin_addr));

    for (i = 0; i < count; i++) {
        memset(packet, 0, sizeof(packet));
        icmp = (struct icmp_hdr *)packet;
        icmp->type = ICMP_ECHO;
        icmp->code = 0;
        icmp->id = htons(getpid() & 0xFFFF);
        icmp->seq = htons(i);
        memset(packet + sizeof(struct icmp_hdr), 0xa5, 56 - sizeof(struct icmp_hdr));
        icmp->chksum = in_cksum((uint16_t *)packet, 56);

        gettimeofday(&tv_start, NULL);
        if (sendto(s, packet, 56, 0, (struct sockaddr *)&to, sizeof(to)) < 0) {
            perror("ping: sendto");
            break;
        }

        struct sockaddr_in from;
        socklen_t fromlen = sizeof(from);
        int n = recvfrom(s, recv_buf, sizeof(recv_buf), 0, (struct sockaddr *)&from, &fromlen);
        gettimeofday(&tv_end, NULL);

        if (n < 0) {
            if (errno == EINTR) continue;
            perror("ping: recvfrom");
            continue;
        }

        struct ip_hdr *ip = (struct ip_hdr *)recv_buf;
        int hlen = (ip->v_hl & 0x0f) << 2;
        struct icmp_hdr *icmp_reply = (struct icmp_hdr *)(recv_buf + hlen);

        if (icmp_reply->type == ICMP_ECHOREPLY) {
            if (ntohs(icmp_reply->id) == (getpid() & 0xFFFF)) {
                rtt = (tv_end.tv_sec - tv_start.tv_sec) * 1000 + (tv_end.tv_usec - tv_start.tv_usec) / 1000;
                printf("64 bytes from %s: icmp_seq=%d ttl=%d time=%ld ms\n",
                       local_inet_ntoa(from.sin_addr), ntohs(icmp_reply->seq), ip->ttl, rtt);
            } else {
                /* Not our packet */
                i--; 
                continue;
            }
        } else {
            printf("Got ICMP message type %d from %s\n", icmp_reply->type, local_inet_ntoa(from.sin_addr));
        }

        sleep(1);
    }

    close(s);
    return 0;
}
