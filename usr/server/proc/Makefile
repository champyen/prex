include $(SRCDIR)/conf/config.mk

PROG=		proc
ifeq ($(CONFIG_ZIG_USR),y)
SRCS=		proc.zig proc_hash_tables.c
else
SRCS=		main.c proc_hash.c proc_hash_tables.c proc_pid.c proc_fork.c proc_exit.c \
		proc_sig.c proc_tty.c
endif

override ZIG_PIC_FLAGS := -fno-PIC -fno-PIE

#DISASM= 	proc.lst
MAP=	 	proc.map
SYMBOL= 	proc.sym

_CONFIG_MK_:=
include $(SRCDIR)/mk/prog.mk
