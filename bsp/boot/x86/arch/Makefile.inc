
ifeq ($(CONFIG_ZIG_BOOT),y)
# reloc is built as part of zig/main.zig
else
SRCS+=		x86/arch/elf_reloc.c
endif
