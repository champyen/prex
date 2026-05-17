#
# Makefile for QEMU RISC-V virt platform
#

SRCS:=          riscv/arch/locore.S \
                riscv/arch/cpufunc.c \
                riscv/arch/cpu.c \
                riscv/arch/trap.c \
                riscv/arch/context.c \
                riscv/arch/clock.c \
                riscv/arch/interrupt.c \
                riscv/qemu-virt/machdep.c \
                riscv/qemu-virt/diag.c

ifeq ($(CONFIG_MMU),y)
SRCS+=		riscv/arch/mmu.c
endif
