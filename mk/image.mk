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
	if [ "$(PLATFORM)" = "musca-b1" ]; then \
		dd if=$(LOADER) of=$(1).dir/padded_loader ibs=131004 conv=sync status=none; \
		$(CAT) $(1).dir/padded_loader $(1).dir/tmp.a > $(1); \
		$(OBJCOPY) -I binary -O elf32-littlearm --change-section-address .data=0x10000000 $(1) $(1).dir/raw_elf; \
		$(LD) -Ttext=0x10000000 -o $(1:.bin=.elf) $(1).dir/raw_elf; \
	else \
		$(CAT) $(LOADER) $(1).dir/tmp.a > $(1); \
	fi
	@rm -rf $(1).dir
endef

$(TARGET_SLIM): $(SUBDIR)
	@$(call create-image,$@,$(FILES))
	$(call sysgen)

$(TARGET_FULL): $(SUBDIR)
	@$(call create-image,$@,$(FILES) $(sort $(BIN_FILES)))
	@$(MAKE) size-report

.PHONY: size-report
size-report:
	@echo ""
	@echo "==============================================================================="
	@echo "                         Prex+ Component Size Report"
	@echo "==============================================================================="
	@printf "%-18s | %8s | %8s | %8s | %8s | %8s\n" "Component" "Text" "Data" "BSS" "Total" "Bin Size"
	@echo "-------------------|----------|----------|----------|----------|-----------"
	@if [ -f $(LOADER).elf ]; then \
		$(SIZE) $(LOADER).elf | tail -n 1 | awk '{printf "%-18s | %8d | %8d | %8d | %8d | %8s\n", "Bootloader", $$1, $$2, $$3, $$4, "-"}' ; \
	elif [ -f $(LOADER) ]; then \
		$(SIZE) $(LOADER) 2>/dev/null | tail -n 1 | awk '{if ($$1 ~ /^[0-9]+$$/) printf "%-18s | %8d | %8d | %8d | %8d | %8s\n", "Bootloader", $$1, $$2, $$3, $$4, "-"}' ; \
	fi
	@if [ -f $(KERNEL) ]; then \
		$(SIZE) $(KERNEL) | tail -n 1 | awk '{printf "%-18s | %8d | %8d | %8d | %8d | %8s\n", "Kernel", $$1, $$2, $$3, $$4, "-"}' ; \
	fi
	@if [ -f $(DRIVER) ]; then \
		$(SIZE) $(DRIVER) | tail -n 1 | awk '{printf "%-18s | %8d | %8d | %8d | %8d | %8s\n", "Driver (drv.ko)", $$1, $$2, $$3, $$4, "-"}' ; \
	fi
	@if [ -f $(TARGET_SLIM) ]; then \
		size=$$(ls -l $(TARGET_SLIM) | awk '{print $$5}'); \
		awk -v s=$$size 'BEGIN {printf "%-18s | %8s | %8s | %8s | %8s | %9.1fK\n", "PrexOS bin", "-", "-", "-", "-", s/1024}' ; \
	fi
	@if [ -f $(TARGET_FULL) ]; then \
		size=$$(ls -l $(TARGET_FULL) | awk '{print $$5}'); \
		awk -v s=$$size 'BEGIN {printf "%-18s | %8s | %8s | %8s | %8s | %9.1fK\n", "PrexOS full bin", "-", "-", "-", "-", s/1024}' ; \
	fi
	@echo "==============================================================================="
	@echo 'Done.'
