
SRCS:=		arm/arch/locore.S \
		arm/beagle/locore_beagle.S \
		arm/arch/cpufunc.S \
		arm/arch/cpu.c \
		arm/arch/trap.c \
		arm/arch/context.c \
		arm/beagle/interrupt.c \
		arm/beagle/clock.c \
		arm/beagle/machdep.c

ifeq ($(CONFIG_MMU),y)
SRCS+=		arm/arch/mmu.c
endif
ifeq ($(DEBUG),1)
SRCS+=		arm/beagle/diag.c
endif
