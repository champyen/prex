SUBDIR:=	bsp sys usr
SRCDIR:=	$(CURDIR)
export SRCDIR

include $(SRCDIR)/mk/image.mk

#
# Parallel build dependencies
#
sys: bsp
usr: sys
$(TARGET): $(SUBDIR)
