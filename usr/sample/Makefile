include $(SRCDIR)/mk/own.mk

SUBDIR:=	alarm balls cpumon bench hello ipc mutex sem task thread \
		tetris

ifeq ($(CONFIG_SNDIO),y)
SUBDIR+=	beep sndio_test playwav
endif

include $(SRCDIR)/mk/subdir.mk
