# Rules to compile kernel

include $(SRCDIR)/mk/own.mk

TARGET:=        prex

_KRNL_:= 1

#MAP:=		prex.map
#DISASM:= 	prex.lst
#SYMBOL:= 	prex.sym

_KERNEL_:=	1
DEFS+=		KERNEL

SRCS+=		$(call select_kernel_src,kern/main) \
		$(call select_kernel_src,kern/sched) \
		$(call select_kernel_src,kern/task) \
		$(call select_kernel_src,kern/thread) \
		$(call select_kernel_src,kern/timer) \
		$(call select_kernel_src,kern/sysent) \
		$(call select_kernel_src,kern/irq) \
		$(call select_kernel_src,kern/device) \
		$(call select_kernel_src,kern/exception) \
		$(call select_kernel_src,kern/system) \
		$(call select_kernel_src,mem/kmem) \
		$(call select_kernel_src,mem/page) \
		$(call select_kernel_src,ipc/msg) \
		$(call select_kernel_src,ipc/object) \
		$(call select_kernel_src,sync/cond) \
		$(call select_kernel_src,sync/mutex) \
		$(call select_kernel_src,sync/sem) \
		$(call select_kernel_src,lib/queue) \
		$(call select_kernel_src,lib/string) \
		lib/vsprintf.c \
		lib/backtrace.c

ifeq ($(CONFIG_ZIG_KRNL),y)
SRCS+=		lib/zig_runtime.zig \
		kern/system_helper.c
endif

ifeq ($(ARCH),riscv)
ifeq ($(CONFIG_ZIG_KRNL),y)
SRCS+=		$(call select_kernel_src,kern/smp)
else
SRCS+=		kern/smp.c
endif
else ifeq ($(CONFIG_SMP),y)
ifeq ($(CONFIG_ZIG_KRNL),y)
SRCS+=		$(call select_kernel_src,kern/smp)
else
SRCS+=		kern/smp.c
endif
endif

ifeq ($(CONFIG_MMU),y)
SRCS+=		$(call select_kernel_src,mem/vm)
else
SRCS+=		$(call select_kernel_src,mem/vm_nommu)
endif

ifeq ($(DEBUG),1)
SRCS+=		kern/debug.c
ifeq ($(CONFIG_KD),y)
SRCS+=		kern/deadlock.c
endif
endif

HAL:=		$(SRCDIR)/bsp/hal/hal.o
LIBSDIR+=	$(SRCDIR)/conf
INCSDIR+=	$(CURDIR)/include $(SRCDIR)/bsp/hal/$(ARCH)/include
ifndef LDSCRIPT
LDSCRIPT_PLAT:=	$(SRCDIR)/bsp/hal/$(ARCH)/$(PLATFORM)/kern.ld
ifneq ($(wildcard $(LDSCRIPT_PLAT)),)
LDSCRIPT:=	$(LDSCRIPT_PLAT)
else
LDSCRIPT:=	$(SRCDIR)/bsp/hal/$(ARCH)/arch/kern.ld
endif
endif

include $(SRCDIR)/mk/common.mk

$(TARGET): $(OBJS) $(HAL) $(LDSCRIPT) $(SRCDIR)/conf/config.ld
	$(call echo-file,LD     ,$@)
	$(LD) $(LDFLAGS) $(OUTPUT_OPTION) $(HAL) $(OBJS) $(PLATFORM_LIBS)
	$(ASMGEN)
	$(SYMGEN)
	#$(STRIP) -s $@
