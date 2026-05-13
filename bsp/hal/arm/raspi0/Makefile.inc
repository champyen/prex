
SRCS:=          arm/arch/locore.S \
                arm/arch/div.c \
                arm/arch/cpufunc.c \
                arm/arch/cpu.c \
                arm/arch/trap.c \
                arm/arch/context.c \
                arm/raspi0/locore.S \
                arm/raspi0/interrupt.c \
                arm/raspi0/clock.c \
                arm/raspi0/machdep.c

ifeq ($(CONFIG_MMU),y)
SRCS+=		arm/arch/mmu.c
endif
ifeq ($(DEBUG),1)
SRCS+=		arm/raspi0/diag.c
endif
