/*
 * Copyright (c) 1982, 1985, 1986, 1988, 1993, 1994
 *  The Regents of the University of California.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *  This product includes software developed by the University of
 *  California, Berkeley and its contributors.
 * 4. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#ifndef _SYS_SOCKET_H_
#define _SYS_SOCKET_H_

#include <sys/types.h>
#include <sys/cdefs.h>

/*
 * Types
 */
#define SOCK_STREAM     1       /* stream socket */
#define SOCK_DGRAM      2       /* datagram socket */
#define SOCK_RAW        3       /* raw-protocol interface */
#define SOCK_RDM        4       /* reliably-delivered message */
#define SOCK_SEQPACKET  5       /* sequenced packet stream */

/*
 * Address families.
 */
#define AF_UNSPEC       0           /* unspecified */
#define AF_LOCAL        1           /* local to host (pipes, portals) */
#define AF_UNIX         AF_LOCAL    /* backward compatibility */
#define AF_INET         2           /* internetwork: UDP, TCP, etc. */
#define AF_INET6        10          /* IP version 6 */
#define AF_MAX          26

#define PF_UNSPEC       AF_UNSPEC
#define PF_INET         AF_INET
#define PF_INET6        AF_INET6

#define IPPROTO_IP      0
#define IPPROTO_ICMP    1
#define IPPROTO_TCP     6
#define IPPROTO_UDP     17
#define IPPROTO_IPV6    41
#define IPPROTO_UDPLITE 136
#define IPPROTO_RAW     255

#define SIN_ZERO_LEN    8

/* Shutdown options */
#define SHUT_RD         0
#define SHUT_WR         1
#define SHUT_RDWR       2

/*
 * Structure used by kernel to store most addresses.
 */
struct sockaddr {
    u_char  sa_len;             /* total length */
    u_char  sa_family;          /* address family */
    char    sa_data[14];        /* actually longer; address value */
};

typedef uint32_t in_addr_t;
struct in_addr {
    in_addr_t s_addr;
};

struct sockaddr_in {
    u_char          sin_len;
    u_char          sin_family;
    uint16_t        sin_port;
    struct in_addr  sin_addr;
    char            sin_zero[SIN_ZERO_LEN];
};

struct hostent {
    char    *h_name;        /* official name of host */
    char    **h_aliases;    /* alias list */
    int     h_addrtype;     /* host address type */
    int     h_length;       /* length of address */
    char    **h_addr_list;  /* list of addresses */
};
#define h_addr  h_addr_list[0]  /* for backward compatibility */

/* addrinfo flags */
#define AI_PASSIVE      0x00000001
#define AI_CANONNAME    0x00000002
#define AI_NUMERICHOST  0x00000004

/* Error codes for getaddrinfo */
#define EAI_FAMILY      1
#define EAI_MEMORY      2
#define EAI_NONAME      3
#define EAI_SERVICE     4
#define EAI_FAIL        5

#define HOST_NOT_FOUND  1

struct sockaddr_storage {
    u_char      ss_len;         /* total length */
    u_char      ss_family;      /* address family */
    char        __ss_pad1[6];
    int64_t     __ss_pad2;
    char        __ss_pad3[240];
};

struct addrinfo {
    int              ai_flags;      /* AI_PASSIVE, AI_CANONNAME, AI_NUMERICHOST */
    int              ai_family;     /* PF_xxx */
    int              ai_socktype;   /* SOCK_xxx */
    int              ai_protocol;   /* 0 or IPPROTO_xxx for IPv4 and IPv6 */
    socklen_t        ai_addrlen;    /* length of ai_addr */
    char            *ai_canonname;  /* canonical name for hostname */
    struct sockaddr *ai_addr;       /* binary address */
    struct addrinfo *ai_next;       /* next structure in linked list */
};

#define SOL_SOCKET  0xffff      /* options for socket level */

/* Socket options */
#define SO_DEBUG        0x0001
#define SO_ACCEPTCONN   0x0002
#define SO_REUSEADDR    0x0004
#define SO_KEEPALIVE    0x0008
#define SO_DONTROUTE    0x0010
#define SO_BROADCAST    0x0020
#define SO_USELOOPBACK  0x0040
#define SO_LINGER       0x0080
#define SO_OOBINLINE    0x0100
#define SO_REUSEPORT    0x0200
#define SO_SNDBUF       0x1001
#define SO_RCVBUF       0x1002
#define SO_SNDLOWAT     0x1003
#define SO_RCVLOWAT     0x1004
#define SO_SNDTIMEO     0x1005
#define SO_RCVTIMEO     0x1006
#define SO_ERROR        0x1007
#define SO_TYPE         0x1008
#define SO_NO_CHECK     0x100a
#define SO_BINDTODEVICE 0x100b

/* IP options */
#define IP_TOS          1
#define IP_TTL          2

/* TCP options */
#define TCP_NODELAY     0x01
#define TCP_KEEPALIVE   0x02
#define TCP_KEEPIDLE    0x03
#define TCP_KEEPINTVL   0x04
#define TCP_KEEPCNT     0x05

/* ioctl */
#define FIONREAD        0x541B
#define FIONBIO         0x5421

/* ifreq for SO_BINDTODEVICE */
#define IFNAMSIZ        16
struct ifreq {
    char ifr_name[IFNAMSIZ];
    union {
        struct sockaddr ifru_addr;
        struct sockaddr ifru_dstaddr;
        struct sockaddr ifru_broadaddr;
        short           ifru_flags;
        int             ifru_metric;
        int             ifru_mtu;
        char            ifru_data[1];
    } ifr_ifru;
};

#define ifr_addr      ifr_ifru.ifru_addr      /* address */
#define ifr_dstaddr   ifr_ifru.ifru_dstaddr   /* P-P address */
#define ifr_broadaddr ifr_ifru.ifru_broadaddr /* broadcast address */
#define ifr_flags     ifr_ifru.ifru_flags     /* flags */
#define ifr_metric    ifr_ifru.ifru_metric    /* metric */
#define ifr_mtu       ifr_ifru.ifru_mtu       /* mtu */

struct ifconf {
    int ifc_len;              /* size of buffer */
    union {
        char *ifcu_buf;
        struct ifreq *ifcu_req;
    } ifc_ifcu;
};
#define ifc_buf ifc_ifcu.ifcu_buf /* buffer address */
#define ifc_req ifc_ifcu.ifcu_req /* array of structures */

#define IFF_UP          0x1     /* interface is up */
#define IFF_BROADCAST   0x2     /* broadcast address valid */
#define IFF_DEBUG       0x4     /* turn on debugging */
#define IFF_LOOPBACK    0x8     /* is a loopback net */
#define IFF_POINTOPOINT 0x10    /* interface is point-to-point link */
#define IFF_RUNNING     0x40    /* resources allocated */
#define IFF_NOARP       0x80    /* no address resolution protocol */
#define IFF_PROMISC     0x100   /* receive all packets */

#define SIOCGIFCONF     0x8912
#define SIOCGIFFLAGS    0x8913
#define SIOCSIFFLAGS    0x8914
#define SIOCGIFADDR     0x8915
#define SIOCSIFADDR     0x8916
#define SIOCGIFNETMASK  0x891b
#define SIOCSIFNETMASK  0x891c
#define SIOCGIFHWADDR   0x8927
#define SIOCSIFHWADDR   0x8924

#define IOV_MAX         1024

/* Message flags */
#define MSG_OOB         0x0001
#define MSG_PEEK        0x0002
#define MSG_DONTROUTE   0x0004
#define MSG_EOR         0x0008
#define MSG_TRUNC       0x0010
#define MSG_CTRUNC      0x0020
#define MSG_WAITALL     0x0040
#define MSG_DONTWAIT    0x0080
#define MSG_EOF         0x0100
#define MSG_MORE        0x0200
#define MSG_NOSIGNAL    0x0400

typedef int msg_iovlen_t;

__BEGIN_DECLS
int accept(int, struct sockaddr *, socklen_t *);
int bind(int, const struct sockaddr *, socklen_t);
int connect(int, const struct sockaddr *, socklen_t);
int getpeername(int, struct sockaddr *, socklen_t *);
int getsockname(int, struct sockaddr *, socklen_t *);
int getsockopt(int, int, int, void *, socklen_t *);
int listen(int, int);
ssize_t recv(int, void *, size_t, int);
ssize_t recvfrom(int, void *, size_t, int, struct sockaddr *, socklen_t *);
ssize_t send(int, const void *, size_t, int);
ssize_t sendto(int, const void *, size_t, int, const struct sockaddr *, socklen_t);
int setsockopt(int, int, int, const void *, socklen_t);
int shutdown(int, int);
int socket(int, int, int);
struct hostent *gethostbyname(const char *);
__END_DECLS

#endif /* !_SYS_SOCKET_H_ */
