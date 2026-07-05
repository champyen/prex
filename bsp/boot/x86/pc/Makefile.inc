
SRCS:=		x86/pc/head.S

ifeq ($(CONFIG_ZIG_BOOT),y)
# Startup/debug are built as part of zig/main.zig
else
SRCS+=		x86/pc/startup.c \
		x86/pc/debug.c
endif
