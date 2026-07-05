
SRCS:=		arm/arch/armv8-m/head.S

ifeq ($(CONFIG_ZIG_BOOT),y)
# Startup/debug are built as part of zig/main.zig
else
SRCS+=		arm/musca-b1/startup.c \
		arm/musca-b1/debug.c
endif

LDSCRIPT:=	$(CURDIR)/arm/arch/armv8-m/boot.ld
