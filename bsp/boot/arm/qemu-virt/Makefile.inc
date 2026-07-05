
SRCS+=		arm/arch/head.S \
		$(call pick_zig_boot_src,arm/qemu-virt/startup) \
		$(call pick_zig_boot_src,arm/qemu-virt/debug)
