
SRCS:=		arm/arch/armv8-m/head.S \
		arm/musca-b1/startup.c \
		arm/musca-b1/debug.c

LDSCRIPT:=	$(CURDIR)/arm/arch/armv8-m/boot.ld
