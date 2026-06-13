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
    ZIGFLAGS += -mcpu $(ZIG_CPU)
  endif
else ifeq ($(ARCH),x86)
ZIG_TARGET:=	x86-freestanding-none
ZIGFLAGS+=	-mcpu i386-sse-sse2-sse3-ssse3-sse4_1-sse4_2-avx-avx2
else ifeq ($(ARCH),riscv)
ZIG_TARGET:=	riscv32-freestanding-none
ZIGFLAGS+=	-mcpu generic_rv32+m+a
endif

ifeq ($(CONFIG_SIZE_OPT),y)
ZIG_OPT:=	-O ReleaseSmall
else
ZIG_OPT:=	-O ReleaseSafe
endif

ZIGFLAGS+=	-target $(ZIG_TARGET) $(ZIG_OPT) -fno-stack-check -fno-PIC -fno-PIE --cache-dir $(SRCDIR)/.zig-cache \
		$(addprefix -I,$(INCSDIR)) $(DEFINES)

# Add driver-specific import path if compiling a driver
ifeq ($(_DRV_),1)
  ZIG_MODULES = --dep dki -Mroot=$< $(ZIGFLAGS) -Mdki=$(SRCDIR)/bsp/drv/zig/dki.zig $(ZIGFLAGS)
else
  ZIG_MODULES = -Mroot=$< $(ZIGFLAGS)
endif

endif # !_ZIG_MK_
