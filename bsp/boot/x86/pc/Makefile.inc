
SRCS:=		x86/pc/head.S \
		$(call pick_zig_boot_src,x86/pc/startup) \
		$(call pick_zig_boot_src,x86/pc/debug)
