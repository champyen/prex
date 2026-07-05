
SRCS:=  arm/arch/head.S \
		$(call pick_zig_boot_src,arm/raspi0/startup) \
		$(call pick_zig_boot_src,arm/raspi0/debug)

