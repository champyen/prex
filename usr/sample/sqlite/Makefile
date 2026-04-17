NDEBUG=1
include $(SRCDIR)/mk/own.mk

INCSDIR+= $(SRCDIR)/usr/sample/sqlite/src $(SRCDIR)/usr/sample/sqlite/src/sqlite3 $(SRCDIR)/usr/lib/libm/fdlibm
DEFS+= HAVE_LOCALTIME_R=1 HAVE_GMTIME_R=1 SQLITE_SHELL_IS_UTF8=1

CFLAGS+= -include prex_sqlite_porting.h

PROG=	sqlite3
SRCS=	src/sqlite3/sqlite3.c src/sqlite3/shell.c src/prex_sqlite_porting.c src/main_prex.c

include $(SRCDIR)/mk/prog.mk
