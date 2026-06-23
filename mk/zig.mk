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
    else ifeq ($(_KRNL_),1)
      ifeq ($(CONFIG_KERNEL_THUMB),y)
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

# Add driver-specific, kernel-specific, or user-space modules
ifeq ($(_KRNL_),1)
  # Choose vm module based on CONFIG_MMU
  ifeq ($(CONFIG_MMU),y)
    VM_MODULE = -Mvm_mod=$(SRCDIR)/sys/mem/vm.zig
  else
    VM_MODULE = -Mvm_mod=$(SRCDIR)/sys/mem/vm_nommu.zig
  endif
  # Main kernel: single root at sys/kern/main.zig, with other kernel
  # modules provided as additional module dependencies so they can be
  # @imported by main.zig.
  # All modules share the same cimport root and ffi alias module.
  COMMON_DEPS = --dep c --dep ffi
  COMMON_MODS = -Mc=$(SRCDIR)/sys/c.zig $(ZIGFLAGS) --dep c -Mffi=$(SRCDIR)/sys/ffi.zig $(ZIGFLAGS)

  ZIG_MODULES = $(COMMON_DEPS) \
    --dep device_mod --dep exception_mod --dep irq_mod \
    --dep sched_mod --dep smp_mod --dep sysent_mod --dep system_mod \
    --dep task_mod --dep thread_mod --dep timer_mod \
    --dep object_mod --dep msg_mod \
    --dep cond_mod --dep mutex_mod --dep sem_mod \
    --dep kmem_mod --dep page_mod --dep vm_mod \
    -Mroot=$< $(ZIGFLAGS) \
    $(COMMON_MODS) \
    $(COMMON_DEPS) -Mdevice_mod=$(SRCDIR)/sys/kern/device.zig $(ZIGFLAGS) \
    $(COMMON_DEPS) -Mexception_mod=$(SRCDIR)/sys/kern/exception.zig $(ZIGFLAGS) \
    $(COMMON_DEPS) -Mirq_mod=$(SRCDIR)/sys/kern/irq.zig $(ZIGFLAGS) \
    $(COMMON_DEPS) -Msched_mod=$(SRCDIR)/sys/kern/sched.zig $(ZIGFLAGS) \
    $(COMMON_DEPS) -Msmp_mod=$(SRCDIR)/sys/kern/smp.zig $(ZIGFLAGS) \
    $(COMMON_DEPS) -Msysent_mod=$(SRCDIR)/sys/kern/sysent.zig $(ZIGFLAGS) \
    $(COMMON_DEPS) -Msystem_mod=$(SRCDIR)/sys/kern/system.zig $(ZIGFLAGS) \
    $(COMMON_DEPS) -Mtask_mod=$(SRCDIR)/sys/kern/task.zig $(ZIGFLAGS) \
    $(COMMON_DEPS) -Mthread_mod=$(SRCDIR)/sys/kern/thread.zig $(ZIGFLAGS) \
    $(COMMON_DEPS) -Mtimer_mod=$(SRCDIR)/sys/kern/timer.zig $(ZIGFLAGS) \
    $(COMMON_DEPS) -Mobject_mod=$(SRCDIR)/sys/ipc/object.zig $(ZIGFLAGS) \
    $(COMMON_DEPS) -Mmsg_mod=$(SRCDIR)/sys/ipc/msg.zig $(ZIGFLAGS) \
    $(COMMON_DEPS) -Mcond_mod=$(SRCDIR)/sys/sync/cond.zig $(ZIGFLAGS) \
    $(COMMON_DEPS) -Mmutex_mod=$(SRCDIR)/sys/sync/mutex.zig $(ZIGFLAGS) \
    $(COMMON_DEPS) -Msem_mod=$(SRCDIR)/sys/sync/sem.zig $(ZIGFLAGS) \
    $(COMMON_DEPS) -Mkmem_mod=$(SRCDIR)/sys/mem/kmem.zig $(ZIGFLAGS) \
    $(COMMON_DEPS) -Mpage_mod=$(SRCDIR)/sys/mem/page.zig $(ZIGFLAGS) \
    $(COMMON_DEPS) $(VM_MODULE)
else ifeq ($(_DRV_),1)
  ZIG_MODULES = --dep dki -Mroot=$< $(ZIGFLAGS) -Mdki=$(SRCDIR)/bsp/drv/zig/dki.zig $(ZIGFLAGS)
else
  ifeq ($(filter _STANDALONE,$(DEFS)),_STANDALONE)
    ZIG_MODULES = --dep prex -Mroot=$< $(ZIGFLAGS) -Mprex=$(SRCDIR)/usr/zig/prex.zig $(ZIGFLAGS)
  else
    ZIG_MODULES = --dep posix -Mroot=$< $(ZIGFLAGS) -Mposix=$(SRCDIR)/usr/zig/posix.zig $(ZIGFLAGS)
  endif
endif

endif # !_ZIG_MK_
