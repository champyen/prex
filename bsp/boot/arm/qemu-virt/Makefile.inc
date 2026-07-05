
SRCS+=		arm/arch/head.S

ifeq ($(CONFIG_ZIG_BOOT),y)
# Startup/debug are built as part of zig/main.zig
else
SRCS+=		arm/qemu-virt/startup.c \
		arm/qemu-virt/debug.c
endif
