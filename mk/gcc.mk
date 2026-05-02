# gcc specifc flags

ifndef _GCC_MK_
_GCC_MK_:=	1

OUTPUT_OPTION=	-o $@

DEFINES=	$(addprefix -D,$(DEFS))

EXTRA_CFLAGS=	-Wno-unused-but-set-variable -Wno-nonnull-compare -Wno-attributes -Wno-sizeof-pointer-memaccess -Wno-pedantic -fno-asynchronous-unwind-tables
ifeq ($(CONFIG_SIZE_OPT),y)
OPT_LEVEL=      -Os
else
OPT_LEVEL=      -O3
endif

CFLAGS+=        -std=c23 -c $(OPT_LEVEL) -pedantic -Wall -Wundef -Wstrict-prototypes -Wpointer-arith -nostdinc \
                -fno-reorder-functions -fno-reorder-blocks -fno-tree-loop-distribute-patterns -fno-strict-aliasing -fno-stack-protector $(GCCFLAGS) $(EXTRA_CFLAGS)
CPPFLAGS+=	$(DEFINES) -I. $(addprefix -I,$(INCSDIR))
ACPPFLAGS+=	-D__ASSEMBLY__
ifneq ($(filter -m32,$(GCCFLAGS)),)
ASFLAGS+=	--32
endif
LDFLAGS+=	-static -nostdlib -z noexecstack --no-warn-rwx-segments $(addprefix -L,$(LIBSDIR))

# 1. Default code layout: Optimize for performance/register usage
CFLAGS+=	-fomit-frame-pointer

# 2. Debug features (Only when _DEBUG_ is enabled)
ifeq ($(_DEBUG_),1)

# Debug symbols: Only for GDB usage
ifeq ($(CONFIG_GDB),y)
CFLAGS+=	-g
endif

# User-space backtrace support
ifeq ($(CONFIG_USR_BACKTRACE),y)
ifeq ($(ARCH),arm)
# ARM Strategy: Table-driven (EABI). Frame pointer is NOT required.
CFLAGS+=	-funwind-tables -mpoke-function-name
LDFLAGS+=	--no-merge-exidx-entries
else
# x86/RISC-V Strategy: Frame-pointer driven.
# Must override the default -fomit-frame-pointer.
CFLAGS:=	$(filter-out -fomit-frame-pointer,$(CFLAGS))
CFLAGS+=	-fno-omit-frame-pointer
endif
endif

# Kernel backtrace support
ifeq ($(CONFIG_KERNEL_BACKTRACE),y)
ifeq ($(ARCH),arm)
# ARM Strategy: Table-driven (EABI). Frame pointer is NOT required.
CFLAGS+=	-funwind-tables -mpoke-function-name
LDFLAGS+=	--no-merge-exidx-entries
else
# x86/RISC-V Strategy: Frame-pointer driven.
# Must override the default -fomit-frame-pointer.
CFLAGS:=	$(filter-out -fomit-frame-pointer,$(CFLAGS))
CFLAGS+=	-fno-omit-frame-pointer
endif
endif

endif # _DEBUG_

# 3. Kernel-specific flags
ifeq ($(_KERNEL_),1)
CFLAGS+=	-fno-builtin
endif

# 4. Strict mode
ifeq ($(_STRICT_),1)
CFLAGS+=	-Werror
endif

ifeq ($(ARCH),arm)
ifeq ($(CONFIG_THUMB),y)
ifneq ($(_KERNEL_),1)
ifeq ($(CONFIG_USR_THUMB),y)
CFLAGS+=	-mthumb
ASFLAGS+=	-mthumb
endif
endif
ifeq ($(_DRV_),1)
ifeq ($(CONFIG_DRV_THUMB),y)
CFLAGS+=	-mthumb
ASFLAGS+=	-mthumb
DEFS+=		CONFIG_DRV_THUMB
endif
else ifeq ($(_KERNEL_),1)
ifeq ($(CONFIG_KERNEL_THUMB),y)
CFLAGS+=	-mthumb
ASFLAGS+=	-mthumb
DEFS+=		CONFIG_KERNEL_THUMB
endif
endif
endif
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
LIBGCC_PATH := $(dir $(shell $(RAWCC) $(GCCFLAGS) -print-libgcc-file-name))
export LIBGCC_PATH
endif
ifneq ($(_KERNEL_),1)
PLATFORM_LIBS+= -L$(LIBGCC_PATH) -lgcc
endif

endif # !_GCC_MK_

