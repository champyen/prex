#
# Makefile for QEMU ARM virt platform
# Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
#

SRCS:=          arm/arch/armv7-a/locore.S \
                arm/qemu-virt/locore.S \
                arm/arch/div.c \
                arm/arch/armv7-a/cpufunc.c \
                arm/arch/armv7-a/clock.c \
                arm/arch/cpu.c \
                arm/arch/trap.c \
                arm/arch/context.c \
                arm/arch/armv7-a/interrupt.c \
                arm/qemu-virt/machdep.c

ifeq ($(CONFIG_MMU),y)
SRCS+=		arm/arch/armv7-a/mmu.c
endif
ifeq ($(DEBUG),1)
SRCS+=		arm/qemu-virt/diag.c
endif
