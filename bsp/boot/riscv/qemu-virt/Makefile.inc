#
# Makefile for QEMU RISC-V virt bootloader
#

SRCS:=		riscv/arch/head.S

ifeq ($(CONFIG_ZIG_BOOT),y)
# Startup/debug are built as part of zig/main.zig
else
SRCS+=		riscv/qemu-virt/startup.c \
		riscv/qemu-virt/debug.c
endif
