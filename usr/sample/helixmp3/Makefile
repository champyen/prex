#
# Makefile for helixmp3
#

include $(SRCDIR)/mk/own.mk

PROG=	helixmp3
SRCS=	main.c \
	helix_mp3.c \
	libhelix/mp3dec.c \
	libhelix/mp3tabs.c \
	libhelix/real/hufftabs.c \
	libhelix/real/subband.c \
	libhelix/real/dct32.c \
	libhelix/real/imdct.c \
	libhelix/real/polyphase.c \
	libhelix/real/bitstream.c \
	libhelix/real/dequant.c \
	libhelix/real/stproc.c \
	libhelix/real/trigtabs.c \
	libhelix/real/huffman.c \
	libhelix/real/dqchan.c \
	libhelix/real/buffers.c \
	libhelix/real/scalfact.c

INCSDIR+= $(SRCDIR)/usr/sample/helixmp3/libhelix/pub \
	$(SRCDIR)/usr/lib/libm/fdlibm

# Option to use runtime initialized tables (for verification)
DEFS += __IEEE_LITTLE_ENDIAN

include $(SRCDIR)/mk/prog.mk
