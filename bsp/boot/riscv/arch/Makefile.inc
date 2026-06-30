#
# Makefile for RISC-V generic bootloader code
#

SRCS+=		$(call pick_zig_boot_src,riscv/arch/elf_reloc)
