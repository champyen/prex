include $(SRCDIR)/mk/own.mk

SUBDIR:=        alarm balls cpumon bench hello ipc mutex sem task thread \
                tetris helixmp3 sqlite tinycc

ifeq ($(CONFIG_SNDIO),y)
SUBDIR+=	beep sndio_test playwav
endif

include $(SRCDIR)/mk/subdir.mk
