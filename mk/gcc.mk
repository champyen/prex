# gcc specifc flags

ifndef _GCC_MK_
_GCC_MK_:=	1

OUTPUT_OPTION=	-o $@

DEFINES=	$(addprefix -D,$(DEFS))

EXTRA_CFLAGS=	-Wno-unused-but-set-variable -Wno-nonnull-compare -Wno-attributes -Wno-sizeof-pointer-memaccess -Wno-pedantic
CFLAGS+=	-std=c11 -c -O3 -pedantic -Wall -Wundef -Wstrict-prototypes -Wpointer-arith -nostdinc \
		-fno-reorder-functions -fno-reorder-blocks -fno-tree-loop-distribute-patterns -fno-strict-aliasing $(GCCFLAGS) $(EXTRA_CFLAGS)
CPPFLAGS+=	$(DEFINES) -I. $(addprefix -I,$(INCSDIR))
ACPPFLAGS+=	-D__ASSEMBLY__
LDFLAGS+=	-static -nostdlib $(addprefix -L,$(LIBSDIR))

ifeq ($(_DEBUG_),1)
CFLAGS+=	-fno-omit-frame-pointer -g
else
CFLAGS+=	-fomit-frame-pointer
endif

ifeq ($(_KERNEL_),1)
CFLAGS+=	-fno-builtin
endif

ifeq ($(_STRICT_),1)
CFLAGS+=	-Werror
endif

ifdef LDSCRIPT
LDFLAGS+=	-T $(LDSCRIPT)
endif

ifdef MAP
LDFLAGS+=	-Map $(MAP)
endif

ifeq ($(_RELOC_OBJ_),1)
LDFLAGS_S:=	$(LDFLAGS) --error-unresolved-symbols
LDFLAGS+=	-r -d
endif

ifndef LIBGCC_PATH
LIBGCC_PATH := $(dir $(shell $(RAWCC) -print-libgcc-file-name))
export LIBGCC_PATH
endif
PLATFORM_LIBS+=	-L$(LIBGCC_PATH) -lgcc

endif # !_GCC_MK_
