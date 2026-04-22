include $(SRCDIR)/mk/own.mk

include $(CURDIR)/cmdbox/Makefile.inc

ifeq ($(CONFIG_CMD_CAT),y)
include $(CURDIR)/cat/Makefile.inc
endif
ifeq ($(CONFIG_CMD_CLEAR),y)
include $(CURDIR)/clear/Makefile.inc
endif
ifeq ($(CONFIG_CMD_DATE),y)
include $(CURDIR)/date/Makefile.inc
endif
ifeq ($(CONFIG_CMD_DMESG),y)
include $(CURDIR)/dmesg/Makefile.inc
endif
ifeq ($(CONFIG_CMD_ECHO),y)
include $(CURDIR)/echo/Makefile.inc
endif
ifeq ($(CONFIG_CMD_KILL),y)
include $(CURDIR)/kill/Makefile.inc
endif
ifeq ($(CONFIG_CMD_LS),y)
include $(CURDIR)/ls/Makefile.inc
endif
ifeq ($(CONFIG_CMD_MKDIR),y)
include $(CURDIR)/mkdir/Makefile.inc
endif
ifeq ($(CONFIG_CMD_PS),y)
include $(CURDIR)/ps/Makefile.inc
endif
ifeq ($(CONFIG_CMD_RM),y)
include $(CURDIR)/rm/Makefile.inc
endif
ifeq ($(CONFIG_CMD_SH),y)
include $(CURDIR)/sh/Makefile.inc
endif
ifeq ($(CONFIG_CMD_SYNC),y)
include $(CURDIR)/sync/Makefile.inc
endif

include $(SRCDIR)/mk/prog.mk
