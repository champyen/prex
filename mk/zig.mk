# zig specifc flags

ifndef _ZIG_MK_
_ZIG_MK_:=	1

# Zig Target Configuration
ifeq ($(ARCH),arm)
  # Default target
  ZIG_TARGET := arm-freestanding-eabi

  # Enable Thumb mode dynamically depending on active component and configuration
  ifeq ($(CONFIG_THUMB),y)
    ifeq ($(_DRV_),1)
      ifeq ($(CONFIG_DRV_THUMB),y)
        ZIG_TARGET := thumb-freestanding-eabi
      endif
    else
      ifeq ($(CONFIG_USR_THUMB),y)
        # Future-proofing: Zig user-space applications
        ZIG_TARGET := thumb-freestanding-eabi
      endif
    endif
  endif

  # Extract CPU target from CFLAGS / GCCFLAGS
  ifneq ($(filter -mcpu=%,$(CFLAGS) $(GCCFLAGS)),)
    RAW_CPU := $(firstword $(patsubst -mcpu=%,%,$(filter -mcpu=%,$(CFLAGS) $(GCCFLAGS))))
    ZIG_CPU := $(subst -,_,$(RAW_CPU))
    # Detect mno-unaligned-access
    ifneq ($(filter -mno-unaligned-access,$(CFLAGS) $(GCCFLAGS)),)
      ZIG_CPU := $(ZIG_CPU)+strict_align
    endif
    ZIGFLAGS += -mcpu $(ZIG_CPU)
  endif
else ifeq ($(ARCH),x86)
  ZIG_TARGET := x86-freestanding-none
  ZIGFLAGS += -mcpu i386
else ifeq ($(ARCH),riscv)
  ZIG_TARGET := riscv32-freestanding-none
  ZIGFLAGS += -mcpu generic_rv32+m+a
endif

ifeq ($(CONFIG_SIZE_OPT),y)
ZIG_OPT:=	-O ReleaseSmall
else
ZIG_OPT:=	-O ReleaseSafe
endif

# PIC/PIE Configuration: Default to no-PIC for better Prex loader compatibility,
# but allow override for XIP targets like Musca-B1.
ZIG_PIC_FLAGS := -fno-PIC -fno-PIE
ifneq ($(filter -fpic -fPIC,$(CFLAGS) $(GCCFLAGS)),)
  ZIG_PIC_FLAGS := -fPIC
endif

ZIGFLAGS+=	-target $(ZIG_TARGET) $(ZIG_OPT) -fno-stack-check -fno-unwind-tables $(ZIG_PIC_FLAGS) --cache-dir $(SRCDIR)/.zig-cache \
		$(addprefix -I,$(INCSDIR)) $(DEFINES)

# Add driver-specific or user-space modules
ifeq ($(_DRV_),1)
  ZIG_MODULES = --dep dki -Mroot=$< $(ZIGFLAGS) -Mdki=$(SRCDIR)/bsp/drv/zig/dki.zig $(ZIGFLAGS)
else
  ifeq ($(filter _STANDALONE,$(DEFS)),_STANDALONE)
    ZIG_MODULES = --dep prex -Mroot=$< $(ZIGFLAGS) -Mprex=$(SRCDIR)/usr/zig/prex.zig $(ZIGFLAGS)
  else
    ZIG_MODULES = --dep posix -Mroot=$< $(ZIGFLAGS) -Mposix=$(SRCDIR)/usr/zig/posix.zig $(ZIGFLAGS)
  endif
endif

endif # !_ZIG_MK_
