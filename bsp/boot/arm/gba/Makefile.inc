
SRCS+=		arm/gba/head.S

ifeq ($(CONFIG_ZIG_BOOT),y)
# Startup/debug are built as part of zig_main.zig
else
SRCS+=		arm/gba/startup.c \
		arm/gba/debug.c
endif

