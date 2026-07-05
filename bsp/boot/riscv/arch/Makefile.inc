#
# Makefile for RISC-V generic bootloader code
#

ifeq ($(CONFIG_ZIG_BOOT),y)
# reloc is built as part of zig/main.zig
else
SRCS+=		riscv/arch/elf_reloc.c
endif
