#
# Makefile for ARM Musca-B1 platform
#

SRCS:=          arm/arch/armv8-m/locore.S \
                arm/musca-b1/machdep.c \
                arm/arch/armv8-m/interrupt.c \
                arm/arch/armv8-m/clock.c \
                arm/arch/armv8-m/cpufunc.c \
                arm/arch/armv8-m/context.c \
                arm/arch/armv8-m/trap.c \
                arm/arch/cpu.c

ifeq ($(DEBUG),1)
SRCS+=		arm/musca-b1/diag.c
endif
