# Device TCC Configuration
CC = /usr/bin/tcc -B/usr/lib/tcc
LD = /usr/bin/tcc -B/usr/lib/tcc
AS = /usr/bin/tcc -B/usr/lib/tcc -c
AR = /usr/bin/tcc -B/usr/lib/tcc -ar
STRIP = strip
SDK_ROOT = /usr
LDFLAGS_1 = -Wl,-Ttext=0x10000
LDFLAGS_0 = -Wl,-Ttext=0x0
LDFLAGS_ENV = $(LDFLAGS_$(MMU))
PLATFORM_LIBS = /usr/lib/tcc/libtcc1.a
CPPFLAGS += -DPOSIX
include $(SDK_ROOT)/config.common.mk
