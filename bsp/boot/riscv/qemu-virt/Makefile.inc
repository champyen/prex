#
# Makefile for QEMU RISC-V virt bootloader
#

SRCS:=		riscv/arch/head.S \
		$(call pick_zig_boot_src,riscv/qemu-virt/startup) \
		$(call pick_zig_boot_src,riscv/qemu-virt/debug)
