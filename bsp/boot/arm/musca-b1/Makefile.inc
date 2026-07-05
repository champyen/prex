
SRCS:=		arm/arch/armv8-m/head.S \
		$(call pick_zig_boot_src,arm/musca-b1/startup) \
		$(call pick_zig_boot_src,arm/musca-b1/debug)

LDSCRIPT:=	$(CURDIR)/arm/arch/armv8-m/boot.ld
