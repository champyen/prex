VPATH:=	$(SRCDIR)/usr/lib/prex/syscalls:$(VPATH)

SRCS+=	$(SRCDIR)/usr/arch/$(ARCH)/_systrap.S \
	syscall_stubs.S \
	thread_getpri.c \
	thread_setpri.c \
	thread_getpolicy.c \
	thread_setpolicy.c \
	timer_waitperiod.c \
	cond_wait.c \
	mutex_lock.c \
	sem_wait.c
