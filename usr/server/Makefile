include $(SRCDIR)/mk/own.mk

SUBDIR:=	fs boot proc exec pow

ifeq ($(CONFIG_SNDIO),y)
SUBDIR+=	sndio
endif

include $(SRCDIR)/mk/subdir.mk
