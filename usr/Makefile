include $(SRCDIR)/mk/own.mk

SUBDIR:=	lib server posix task

ifneq ($(_QUICK_),1)
SUBDIR+=	test
endif

include $(SRCDIR)/mk/subdir.mk

#
# Parallel build dependencies
#
server posix task test: lib
