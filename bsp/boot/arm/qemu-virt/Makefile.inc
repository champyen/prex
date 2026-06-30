
SRCS+=		arm/arch/head.S \
		$(call pick_zig_boot_src,arm/qemu-virt/startup) \
		arm/qemu-virt/debug.c
