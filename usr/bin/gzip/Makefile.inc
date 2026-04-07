GZIP_DIR:= gzip
LIBZ_DIR:= gzip/libz

SRCS-$(CONFIG_CMD_GZIP)+=	$(GZIP_DIR)/gzip.c \
				$(LIBZ_DIR)/adler32.c \
				$(LIBZ_DIR)/crc32.c \
				$(LIBZ_DIR)/deflate.c \
				$(LIBZ_DIR)/inflate.c \
				$(LIBZ_DIR)/inffast.c \
				$(LIBZ_DIR)/inftrees.c \
				$(LIBZ_DIR)/trees.c \
				$(LIBZ_DIR)/zutil.c \
				$(LIBZ_DIR)/gzio.c

DEFS-$(CONFIG_CMD_GZIP)+=	-I$(CURDIR)/$(LIBZ_DIR)
