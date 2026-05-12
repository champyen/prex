
SRCS+=		arm/arch/elf_reloc.c

ifneq ($(CONFIG_ARMV7A),y)
SRCS+=		arm/arch/div.c
endif
