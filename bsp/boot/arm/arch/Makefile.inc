
ifeq ($(CONFIG_ZIG_BOOT),y)
# reloc is built as part of zig/main.zig
else
SRCS+=		arm/arch/elf_reloc.c
endif

