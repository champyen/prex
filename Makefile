SUBDIR:=	bsp sys usr
SRCDIR:=	$(CURDIR)
export SRCDIR

include $(SRCDIR)/mk/image.mk
include $(SRCDIR)/mk/sdk.mk
include $(SRCDIR)/mk/volumes.mk

#
# Parallel build dependencies
#
sys: bsp
usr: sys
$(TARGET): bsp $(SUBDIR)

all: $(BIN_IMG) $(DISK_IMG)

# Add volume artifacts to clean list
CLEANFILES+= $(BIN_IMG) $(DISK_IMG)

clean: clean-volumes

.PHONY: clean-volumes
clean-volumes:
	rm -rf $(BIN_ROOT) $(USR_ROOT)
	rm -f $(BIN_IMG) $(DISK_IMG)

