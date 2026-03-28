include $(SRCDIR)/mk/own.mk

SUBDIR:=	lib server bin sbin

ifneq ($(_QUICK_),1)
SUBDIR+=	sample test
endif

include $(SRCDIR)/mk/subdir.mk

#
# Parallel build dependencies
#
server bin sbin sample test: lib
