
# bsp/boot/common/Makefile.inc — sources for the common/ boot directory.
#
# Each .c source is potentially shadowed by a .zig sibling in the same
# directory. When CONFIG_ZIG_BOOT=y and a .zig file exists, pick_zig_boot_src
# selects the .zig; otherwise the .c. This mirrors the select_src mechanism
# used by bsp/drv/dev/serial/Makefile.inc:4.
#
# The zig/runtime.zig entry is unconditional (no .c fallback) because it
# provides AEABI runtime helpers for Zig-compiled bootloaders. When the
# bootloader is built entirely from C, runtime.zig is a no-op file (no
# exports) and adds no symbols.

SRCS+=		$(call pick_zig_boot_src,common/main) \
		$(call pick_zig_boot_src,common/bootinfo) \
		$(call pick_zig_boot_src,common/load) \
		$(call pick_zig_boot_src,common/elf) \
		$(call pick_zig_boot_src,common/splash) \
		$(call pick_zig_boot_src,common/string) \
		$(call pick_zig_boot_src,common/printf) \
		common/jump_entry.c \
		zig/runtime.zig
