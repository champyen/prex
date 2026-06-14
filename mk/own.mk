ifndef _OWN_MK_
_OWN_MK_:=	1

# Build flavor
_DEBUG_:=	1
#_QUICK_:=	1
#_STRICT_:=	1
#_SILENT_:=	1

# Clean the slate
CFLAGS=
CPPFLAGS=
LDFLAGS=
ASFLAGS=
STRIPFLAG=

ifndef _CONFIG_MK_
-include $(SRCDIR)/conf/config.mk
export SRCDIR
endif

LINT:=		splint
#LINT:=		lint
RM:=            rm -f
CAT:=           cat
MV:=            mv
CP:=            cp

ifdef SHELL_PATH
SHELL:=		$(SHELL_PATH)
endif

# We assume GNU make...
MAKEFLAGS+=	-rR --no-print-directory

ifeq ($(LINT),splint)
LINTFLAGS:=	-D__lint__ -weak -nolib -retvalother -fcnuse
else
LINTFLAGS:=	-D__lint__ -x -u
endif

INCSDIR:=	$(SRCDIR) $(SRCDIR)/include
DEFS+=		__$(ARCH)__ __$(subst -,_,$(PLATFORM))__ _REENTRANT

ifneq ($(NDEBUG),1)
ifeq ($(_DEBUG_),1)
DEFS+=		DEBUG
DEBUG:=		1
endif
endif

RAWCC:=		$(CC)
SIZE:=		$(subst gcc,size,$(CC))
RAWZIG:=	zig
ZIG:=		$(RAWZIG)
ifeq ($(_SILENT_),1)
CC:=		@$(CC)
CPP:=		@$(CPP)
AS:=		@$(AS)
LD:=		@$(LD)
AR:=		@$(AR)
ZIG:=		@$(ZIG)
STRIP:=		@$(STRIP)
OBJCOPY:=	@$(OBJCOPY)
OBJDUMP:=	@$(OBJDUMP)
RM:=		@$(RM)
CAT:=		@$(CAT)
endif

# Helper to automatically select the Zig version of a driver if available and enabled, otherwise fallback to C
ifeq ($(CONFIG_ZIG_DRV),y)
  select_src = $(if $(wildcard $(SRCDIR)/bsp/drv/$(1).zig),$(info [DEBUG] Found Zig source for $(1))$(1).zig,$(1).c)
else
  select_src = $(1).c
endif

# Automatically select the Zig version of a user task/program if available and Zig user-space is enabled
ifeq ($(CONFIG_ZIG_USR),y)
  select_usr_src = $(if $(wildcard $(1).zig),$(1).zig,$(1).c)
else
  select_usr_src = $(1).c
endif

endif # !_OWN_MK_
