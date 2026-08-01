include $(SRCDIR)/conf/config.mk

PROG:=		exec
ifeq ($(CONFIG_ZIG_USR),y)
SRCS:=		main.zig exec_execve.zig exec_elf.zig exec_script.zig exec_cap.zig \
		exec_globals.c $(SRCDIR)/usr/arch/$(ARCH)/elf_reloc.c
else
SRCS:=		main.c exec_execve.c exec_conf.c exec_cap.c \
		exec_elf.c exec_script.c \
		$(SRCDIR)/usr/arch/$(ARCH)/elf_reloc.c
endif

override ZIG_PIC_FLAGS := -fno-PIC -fno-PIE

MAP:=		exec.map
DISASM:= 	exec.lst
SYMBOL:= 	exec.sym

_CONFIG_MK_:=
include $(SRCDIR)/mk/prog.mk

