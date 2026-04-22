PROG=		gzip
SRCS=		gzip.c \
		libz/adler32.c \
		libz/crc32.c \
		libz/deflate.c \
		libz/inflate.c \
		libz/inffast.c \
		libz/inftrees.c \
		libz/trees.c \
		libz/zutil.c \
		libz/gzio.c
CFLAGS+=	-I$(CURDIR)/libz
include $(SRCDIR)/mk/prog.mk
