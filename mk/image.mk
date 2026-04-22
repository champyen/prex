# Rules to create OS image

include $(SRCDIR)/mk/own.mk

TARGET_SLIM:=	$(SRCDIR)/prexos.bin
TARGET_FULL:=	$(SRCDIR)/prexos_full.bin
TARGET:=	$(TARGET_SLIM) $(TARGET_FULL)

LOADER:=	$(SRCDIR)/bsp/boot/bootldr
DRIVER:=	$(SRCDIR)/bsp/drv/drv.ko
KERNEL:=	$(SRCDIR)/sys/prex

include $(SRCDIR)/conf/etc/tasks.mk
include $(SRCDIR)/conf/etc/files.mk
include $(SRCDIR)/conf/etc/bin_vol.mk
include $(SRCDIR)/mk/common.mk
-include $(SRCDIR)/bsp/boot/$(ARCH)/$(PLATFORM)/Makefile.sysgen

# Define a macro for image creation
# $(1): Target image name
# $(2): List of files to include in bootdisk.a
define create-image
	$(call echo-file,PACK   ,$(1))
	@mkdir -p $(1).dir
	@cp $(2) $(1).dir/ 2>/dev/null || true
	# Use relative paths for AR to avoid including absolute paths if possible
	# But Prex files.mk uses absolute paths. AR rcS handles them.
	$(AR) rcS $(1).dir/bootdisk.a $(2)
	$(AR) rcS $(1).dir/tmp.a $(KERNEL) $(DRIVER) $(TASKS) $(1).dir/bootdisk.a
	# Prex loader expects "bootdisk.a" member name. 
	# Nested archive member names in AR usually don't include path.
	$(CAT) $(LOADER) $(1).dir/tmp.a > $(1)
	@rm -rf $(1).dir
endef

$(TARGET_SLIM): $(SUBDIR)
	@$(call create-image,$@,$(FILES))
	$(call sysgen)

$(TARGET_FULL): $(SUBDIR)
	@$(call create-image,$@,$(FILES) $(sort $(BIN_FILES)))
	@echo 'Done.'
