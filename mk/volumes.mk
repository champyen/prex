include $(SRCDIR)/mk/own.mk
include $(SRCDIR)/conf/etc/bin_vol.mk
include $(SRCDIR)/conf/etc/usr_vol.mk

BIN_IMG=	$(SRCDIR)/bin.img
DISK_IMG=	$(SRCDIR)/disk.img
BIN_ROOT=	$(SRCDIR)/bin_root
USR_ROOT=	$(SRCDIR)/usr_root

# Tools
MKFS_VFAT=	mkfs.vfat
MCOPY=		mcopy

all: $(BIN_IMG) $(DISK_IMG)

# Depend on usr target to ensure binaries are built
$(BIN_IMG): usr
	@echo "Creating $@ (ARFS)"
	@rm -rf $(BIN_ROOT)
	@mkdir -p $(BIN_ROOT)/bin
	@cp $(sort $(BIN_FILES)) $(BIN_ROOT)/bin/
	@cd $(BIN_ROOT) && $(AR) rcS $(BIN_IMG) bin/*

$(DISK_IMG): usr sdk
	@echo "Creating $@ (FATFS)"
	@rm -rf $(USR_ROOT)
	@mkdir -p $(USR_ROOT)/bin
	# Copy SDK content to usr_root if enabled
ifeq ($(CONFIG_SDK),y)
	@cp -a $(SDK_ROOT)/* $(USR_ROOT)/
endif
	# Copy additional binaries to usr_root/bin
	@for f in $(USR_BIN_FILES); do \
		if [ -f $$f ]; then cp $$f $(USR_ROOT)/bin/; fi; \
	done
	@rm -f $@
	@$(MKFS_VFAT) -C $@ 65536
	@$(MCOPY) -s -D o -i $@ $(USR_ROOT)/* ::/

clean-volumes:
	rm -f $(BIN_IMG) $(DISK_IMG)
	rm -rf $(BIN_ROOT) $(USR_ROOT)

.PHONY: all clean-volumes
