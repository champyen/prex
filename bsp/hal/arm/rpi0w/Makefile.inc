
SRCS:=		arm/arch/locore.S \
		arm/arch/cpufunc.S \
		arm/arch/cpu.c \
		arm/arch/trap.c \
		arm/arch/context.c \
		arm/rpi0w/locore.S \
		arm/rpi0w/interrupt.c \
		arm/rpi0w/clock.c \
		arm/rpi0w/machdep.c

ifeq ($(CONFIG_MMU),y)
SRCS+=		arm/arch/mmu.c
endif
ifeq ($(DEBUG),1)
SRCS+=		arm/rpi0w/diag.c
endif
