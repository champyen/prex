include $(SRCDIR)/mk/own.mk

SUBDIR:=        alarm balls cpumon bench hello ipc mutex sem task thread \
                tetris

ifeq ($(CONFIG_SQLITE),y)
SUBDIR+=	sqlite
endif

ifeq ($(CONFIG_SDK),y)
SUBDIR+=	tinycc make
endif

ifeq ($(CONFIG_SNDIO),y)
SUBDIR+=	beep sndio_test playwav helixmp3
endif

include $(SRCDIR)/mk/subdir.mk
