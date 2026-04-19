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

#ifndef _NET_H_
#define _NET_H_

#include <sys/types.h>
#include <ddi.h>

/* Ethernet parameters */
#define NET_MAX_FRAME 1518
#define NET_ADDR_LEN  6

/* 
 * Hardware interface callbacks
 */
struct net_hw_if {
    int  (*open)(void *priv);
    void (*close)(void *priv);
    int  (*xmit)(void *priv, void *buf, size_t len);
    int  (*get_addr)(void *priv, uint8_t *addr);
    int  (*set_addr)(void *priv, uint8_t *addr);
    int  (*set_promisc)(void *priv, int on);
};

/*
 * Driver registration
 */
__BEGIN_DECLS
device_t net_attach(const char *name, const struct net_hw_if *hw_if, void *hw_priv);
void     net_rx_complete(device_t dev, void *buf, size_t len);
__END_DECLS

#endif /* !_NET_H_ */
