/*
 * Copyright 2018 Phoenix Systems
 * Copyright (c) 2026, Champ Yen (champ.yen@gmail.com)
 * Author: Michał Mirosław
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */
#ifndef PHOENIX_LWIP_CC_H_
#define PHOENIX_LWIP_CC_H_

#include <sys/types.h>
#include <stddef.h>
typedef long ptrdiff_t;
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/time.h>
#include <sys/prex.h>
#include <sys/socket.h>
#include <errno.h>

#define inet_addr_from_ip4addr(target_inaddr, source_ipaddr) ((target_inaddr)->s_addr = ip4_addr_get_u32(source_ipaddr))
#define inet_addr_to_ip4addr(target_ipaddr, source_inaddr)   ip4_addr_set_u32(target_ipaddr, (source_inaddr)->s_addr)

struct iovec {
    void  *iov_base;
    size_t iov_len;
};

struct msghdr {
    void         *msg_name;
    socklen_t     msg_namelen;
    struct iovec *msg_iov;
    int           msg_iovlen;
    void         *msg_control;
    socklen_t     msg_controllen;
    int           msg_flags;
};

struct pollfd {
    int fd;
    short events;
    short revents;
};

#define POLLIN      0x0001
#define POLLPRI     0x0002
#define POLLOUT     0x0004
#define POLLERR     0x0008
#define POLLHUP     0x0010
#define POLLNVAL    0x0020

/* types used by LwIP */
#define X8_F  "02x"
#define U16_F "u"
#define S16_F "d"
#define X16_F "x"
#define U32_F "u"
#define S32_F "d"
#define X32_F "x"
#define SZT_F "zu"
#define SOCKLEN_T_DEFINED 1

#include <machine/endian.h>

/* host endianness */
#ifndef BYTE_ORDER
#define BYTE_ORDER _BYTE_ORDER
#endif
#ifndef LITTLE_ENDIAN
#define LITTLE_ENDIAN _LITTLE_ENDIAN
#endif
#ifndef BIG_ENDIAN
#define BIG_ENDIAN _BIG_ENDIAN
#endif

#define LWIP_CHKSUM_ALGORITHM 2

/* diagnostics */
void bail(const char *format, ...);
void errout(int err, const char *format, ...);
void lwip_diag(const char *format, ...);

extern int h_errno;

#define LWIP_PLATFORM_DIAG(x)	lwip_diag x
#define LWIP_PLATFORM_ASSERT	bail

/* initialization */
#define __constructor__(o)

/* randomness */
#define LWIP_RAND() ((u32_t)rand())

#endif /* PHOENIX_LWIP_CC_H_ */
