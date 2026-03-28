# usr/bin/tcc/Makefile
# Makefile for TinyCC on Prex

SRCDIR= ../../..
include $(SRCDIR)/mk/own.mk

PROG:=	tcc
SRCS:=	tcc.c prex_stubs.c

# TCC needs many of its internal files included via #include in tcc.c
# or linked together. For simplicity in Prex, we'll follow TCC's 
# "one big object" style or its libtcc style.

VPATH:=	$(SRCDIR)/external/tcc

# Prex specific paths for the target
DEFS+= CONFIG_SYSROOT="\"/boot\""
DEFS+= CONFIG_TCCDIR="\"/boot/usr/lib/tcc\""
DEFS+= TCC_VERSION="\"0.9.27\""
DEFS+= ONE_SOURCE=1
DEFS+= CONFIG_TCC_STATIC=1
DEFS+= __prex__=1

# TCC source requires some standard headers and defines
# Include the selected libm implementation for math.h
INCSDIR+= $(SRCDIR)/external/tcc $(SRCDIR)/usr/lib/libm/$(CONFIG_LIBM)

# Prex libc now includes libm
LIBS:= $(SRCDIR)/usr/lib/libc.a

include $(SRCDIR)/mk/prog.mk
