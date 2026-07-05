
SRCS:=		arm/arch/head.S \
		$(call pick_zig_boot_src,arm/integrator/startup) \
		$(call pick_zig_boot_src,arm/integrator/debug)

