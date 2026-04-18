include $(SRCDIR)/mk/own.mk

PROG=	tcc
SRCS=	tcc.c prex_glue.c

ifeq ($(ARCH),arm)
TCC_TARGET=TCC_TARGET_ARM=1
else ifeq ($(ARCH),x86)
TCC_TARGET=TCC_TARGET_I386=1
endif

DEFS+=	$(TCC_TARGET) TCC_VERSION=\"0.9.28rc\" CONFIG_TCCDIR=\"/usr/lib/tcc\" ONE_SOURCE=1 CONFIG_TCC_STATIC=1 CONFIG_TCC_SEMLOCK=0 CONFIG_TCC_BACKTRACE=0
CFLAGS+= -UTCC_IS_NATIVE
INCSDIR+= $(SRCDIR)/usr/sample/tinycc $(SRCDIR)/usr/lib/libm/fdlibm

include $(SRCDIR)/mk/prog.mk
