# usr/server/network/Makefile
include $(SRCDIR)/mk/own.mk

TARGET= network

SRCS=	port/main.c \
	port/sys_arch.c \
	port/netif.c \
	port/sys.c \
	port/common.c \
	port/sockets.c

# lwIP Core
LWIPDIR= lwip/src
SRCS+=	$(LWIPDIR)/core/init.c \
	$(LWIPDIR)/core/def.c \
	$(LWIPDIR)/core/dns.c \
	$(LWIPDIR)/core/inet_chksum.c \
	$(LWIPDIR)/core/ip.c \
	$(LWIPDIR)/core/mem.c \
	$(LWIPDIR)/core/memp.c \
	$(LWIPDIR)/core/netif.c \
	$(LWIPDIR)/core/pbuf.c \
	$(LWIPDIR)/core/raw.c \
	$(LWIPDIR)/core/stats.c \
	$(LWIPDIR)/core/sys.c \
	$(LWIPDIR)/core/tcp.c \
	$(LWIPDIR)/core/tcp_in.c \
	$(LWIPDIR)/core/tcp_out.c \
	$(LWIPDIR)/core/timeouts.c \
	$(LWIPDIR)/core/udp.c

# lwIP IPv4
SRCS+=	$(LWIPDIR)/core/ipv4/acd.c \
	$(LWIPDIR)/core/ipv4/autoip.c \
	$(LWIPDIR)/core/ipv4/dhcp.c \
	$(LWIPDIR)/core/ipv4/etharp.c \
	$(LWIPDIR)/core/ipv4/icmp.c \
	$(LWIPDIR)/core/ipv4/igmp.c \
	$(LWIPDIR)/core/ipv4/ip4.c \
	$(LWIPDIR)/core/ipv4/ip4_addr.c \
	$(LWIPDIR)/core/ipv4/ip4_frag.c

# lwIP API
SRCS+=	$(LWIPDIR)/api/api_lib.c \
	$(LWIPDIR)/api/api_msg.c \
	$(LWIPDIR)/api/err.c \
	$(LWIPDIR)/api/if_api.c \
	$(LWIPDIR)/api/netbuf.c \
	$(LWIPDIR)/api/netdb.c \
	$(LWIPDIR)/api/netifapi.c \
	$(LWIPDIR)/api/sockets.c \
	$(LWIPDIR)/api/tcpip.c

# lwIP Netifs
SRCS+=	$(LWIPDIR)/netif/ethernet.c

DEFS+= PHOENIX POSIX
INCSDIR+= $(SRCDIR)/usr/server/network/include $(SRCDIR)/usr/server/network/lwip/src/include $(SRCDIR)/usr/include

include $(SRCDIR)/mk/prog.mk
