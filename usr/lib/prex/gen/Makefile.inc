VPATH:=	$(SRCDIR)/usr/lib/prex/gen:$(VPATH)

SRCS+=	panic.c dprintf.c dassert.c backtrace.c

ifeq ($(ARCH),arm)
ifneq ($(CONFIG_ARMV7A),y)
SRCS+=	div.c
endif
endif

