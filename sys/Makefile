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
		$(call select_kernel_src,lib/queue) \
		$(call select_kernel_src,lib/string) \
		lib/vsprintf.c \
		lib/backtrace.c

ifeq ($(CONFIG_ZIG_KRNL),y)
SRCS+=		lib/zig_runtime.zig \
		kern/system_helper.c
else
SRCS+=		kern/sched.c \
		kern/task.c \
		kern/thread.c \
		kern/timer.c \
		kern/irq.c \
		kern/exception.c \
		kern/system.c \
		kern/sysent.c \
		kern/device.c \
		mem/page.c \
		mem/kmem.c \
		ipc/msg.c \
		ipc/object.c \
		sync/mutex.c \
		sync/cond.c \
		sync/sem.c

ifeq ($(CONFIG_MMU),y)
SRCS+=		mem/vm.c
else
SRCS+=		mem/vm_nommu.c
endif

SRCS+=		kern/smp.c
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
