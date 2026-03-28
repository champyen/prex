include $(SRCDIR)/mk/own.mk

SUBDIR:=	boot hal drv

include $(SRCDIR)/mk/subdir.mk

#
# Parallel build dependencies
#
hal: boot
drv: hal
