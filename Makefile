SUBDIR:=	bsp sys usr
SRCDIR:=	$(CURDIR)
export SRCDIR

include $(SRCDIR)/mk/image.mk
include $(SRCDIR)/mk/sdk.mk

#
# Parallel build dependencies
#
sys: bsp
usr: sys
$(TARGET): bsp $(SUBDIR)

ifeq ($(CONFIG_SDK),y)
all: sdk
endif
