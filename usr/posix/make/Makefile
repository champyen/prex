include $(SRCDIR)/mk/own.mk

PROG=	make
SRCS=	arch.c buf.c compat.c cond.c dir.c for.c hash.c job.c main.c \
	make.c parse.c str.c suff.c targ.c var.c prex_glue.c \
	lst.lib/lstAppend.c lst.lib/lstAtEnd.c lst.lib/lstAtFront.c \
	lst.lib/lstClose.c lst.lib/lstConcat.c lst.lib/lstDatum.c \
	lst.lib/lstDeQueue.c lst.lib/lstDestroy.c lst.lib/lstDupl.c \
	lst.lib/lstEnQueue.c lst.lib/lstFind.c lst.lib/lstFindFrom.c \
	lst.lib/lstFirst.c lst.lib/lstForEach.c lst.lib/lstForEachFrom.c \
	lst.lib/lstInit.c lst.lib/lstInsert.c lst.lib/lstIsAtEnd.c \
	lst.lib/lstIsEmpty.c lst.lib/lstLast.c lst.lib/lstMember.c \
	lst.lib/lstNext.c lst.lib/lstOpen.c lst.lib/lstRemove.c \
	lst.lib/lstReplace.c lst.lib/lstSucc.c

DEFS+=	POSIX _PATH_DEFSHELL=\"/boot/sh\"
INCSDIR+= $(SRCDIR)/usr/posix/make $(SRCDIR)/usr/posix/make/lst.lib $(SRCDIR)/usr/lib/libm/fdlibm
CFLAGS+= -Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration -Wno-error=old-style-definition -Wno-old-style-definition -Wno-strict-prototypes -std=gnu89

include $(SRCDIR)/mk/prog.mk
