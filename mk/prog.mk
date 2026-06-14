# Rules to compile a POSIX executable file

include $(SRCDIR)/mk/own.mk

INCSDIR+=	$(SRCDIR)/usr/include
LIBSDIR+=	$(SRCDIR)/usr/lib
CRT0:=		$(SRCDIR)/usr/lib/crt0.o
LIBC:=		$(SRCDIR)/usr/lib/libc.a

ifeq ($(CONFIG_MMU),y)
LDSCRIPT:=	$(SRCDIR)/usr/arch/$(ARCH)/user.ld
STRIPFLAG:=	-s
else
STRIPFLAG:=	--strip-debug --strip-unneeded
ifeq ($(CONFIG_ARMV8M),y)
LDSCRIPT:=	$(SRCDIR)/usr/arch/$(ARCH)/user-nommu-v8m.ld
_RELOC_OBJ_:=
else
LDSCRIPT:=	$(SRCDIR)/usr/arch/$(ARCH)/user-nommu.ld
_RELOC_OBJ_:=	1
endif
endif

ifdef PROG
TARGET?=	$(PROG)
ifndef SRCS
SRCS:=		$(call select_usr_src,$(basename $(PROG)))
endif
endif

include $(SRCDIR)/mk/common.mk

$(TARGET): $(LIBS) $(OBJS) $(LIBC) $(CRT0)
	$(call echo-file,LD     ,$@)
	$(LD) $(LDFLAGS) $(OUTPUT_OPTION) $(CRT0) $(OBJS) $(LIBS) $(LIBC) $(PLATFORM_LIBS)
	$(ASMGEN)
	$(SYMGEN)
	$(STRIP) $(STRIPFLAG) $@
