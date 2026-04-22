SDK_INC = $(SDK_ROOT)/include
SDK_LIB = $(SDK_ROOT)/lib
CFLAGS += -nostdinc -g
CPPFLAGS += -I. -I$(SDK_INC) -I$(SDK_INC)/ipc -I$(SDK_INC)/machine
LDFLAGS += -static -nostdlib -L$(SDK_LIB) $(LDFLAGS_ENV)
CRT0 = $(SDK_LIB)/crt0.o
LIBC = $(SDK_LIB)/libc.a
