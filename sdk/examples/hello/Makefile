# Prex SDK Example Makefile
include ../../config.mk

TARGET = hello
SRCS = main.c
OBJS = $(SRCS:.c=.o)

all: $(TARGET)

$(TARGET): $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $(CRT0) $(OBJS) $(LIBC) $(PLATFORM_LIBS)
	$(STRIP) $(STRIPFLAG) $@

%.o: %.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c -o $@ $<

clean:
	rm -f $(TARGET) $(OBJS)
