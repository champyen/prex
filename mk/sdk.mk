# sdk.mk - rules to generate Prex SDK

SDK_DIR = $(SRCDIR)/sdk
SDK_LIB = $(SDK_DIR)/lib
SDK_INC = $(SDK_DIR)/include
SDK_EXAMPLES = $(SDK_DIR)/examples

.PHONY: sdk
sdk:
	@echo "Generating Prex SDK..."
	@mkdir -p $(SDK_LIB) $(SDK_INC) $(SDK_EXAMPLES)
	# Copy linker scripts
	cp $(SRCDIR)/usr/arch/$(ARCH)/user.ld $(SDK_LIB)/
	cp $(SRCDIR)/usr/arch/$(ARCH)/user-nommu.ld $(SDK_LIB)/
	# Copy libraries and CRT
	cp $(SRCDIR)/usr/lib/libc.a $(SDK_LIB)/
	cp $(SRCDIR)/usr/lib/crt0.o $(SDK_LIB)/
	[ -f $(SRCDIR)/usr/lib/crt/crt1.o ] && cp $(SRCDIR)/usr/lib/crt/crt1.o $(SDK_LIB)/ || true
	# Copy headers
	cp -rn $(SRCDIR)/include/* $(SDK_INC)/
	cp -rn $(SRCDIR)/usr/include/* $(SDK_INC)/
	mkdir -p $(SDK_INC)/conf && cp $(SRCDIR)/conf/config.h $(SDK_INC)/conf/
	# Copy examples
	mkdir -p $(SDK_EXAMPLES)/hello
	cp $(SRCDIR)/usr/sample/hello/hello.c $(SDK_EXAMPLES)/hello/main.c
	# Create sdk/config.mk
	@echo "# Prex SDK Configuration" > $(SDK_DIR)/config.mk
	@echo "ARCH ?= $(ARCH)" >> $(SDK_DIR)/config.mk
	@echo "CROSS_COMPILE ?= $(subst gcc,,$(CC))" >> $(SDK_DIR)/config.mk
	@echo "CC = \$$(CROSS_COMPILE)gcc" >> $(SDK_DIR)/config.mk
	@echo "CPP = \$$(CROSS_COMPILE)cpp" >> $(SDK_DIR)/config.mk
	@echo "AS = \$$(CROSS_COMPILE)as" >> $(SDK_DIR)/config.mk
	@echo "LD = \$$(CROSS_COMPILE)ld" >> $(SDK_DIR)/config.mk
	@echo "AR = \$$(CROSS_COMPILE)ar" >> $(SDK_DIR)/config.mk
	@echo "STRIP = \$$(CROSS_COMPILE)strip" >> $(SDK_DIR)/config.mk
	@echo "" >> $(SDK_DIR)/config.mk
	@echo "SDK_DIR := \$$(abspath \$$(dir \$$(lastword \$$(MAKEFILE_LIST))))" >> $(SDK_DIR)/config.mk
	@echo "SDK_INC = \$$(SDK_DIR)/include" >> $(SDK_DIR)/config.mk
	@echo "SDK_LIB = \$$(SDK_DIR)/lib" >> $(SDK_DIR)/config.mk
	@echo "" >> $(SDK_DIR)/config.mk
	@echo "CONFIG_MMU ?= $(CONFIG_MMU)" >> $(SDK_DIR)/config.mk
	@echo "" >> $(SDK_DIR)/config.mk
	@echo "CFLAGS += $(CFLAGS) -nostdinc" | sed 's/-I[^ ]*//g' >> $(SDK_DIR)/config.mk
	@echo "CPPFLAGS += -I. -I\$$(SDK_INC) -I\$$(SDK_INC)/ipc -I\$$(SDK_INC)/machine" >> $(SDK_DIR)/config.mk
	@echo "LDFLAGS += -static -nostdlib -z noexecstack --no-warn-rwx-segments -L\$$(SDK_LIB)" >> $(SDK_DIR)/config.mk
	@echo "" >> $(SDK_DIR)/config.mk
	@echo "ifeq (\$$(CONFIG_MMU),y)" >> $(SDK_DIR)/config.mk
	@echo "LDSCRIPT = \$$(SDK_LIB)/user.ld" >> $(SDK_DIR)/config.mk
	@echo "STRIPFLAG = -s" >> $(SDK_DIR)/config.mk
	@echo "else" >> $(SDK_DIR)/config.mk
	@echo "LDSCRIPT = \$$(SDK_LIB)/user-nommu.ld" >> $(SDK_DIR)/config.mk
	@echo "STRIPFLAG = --strip-debug --strip-unneeded" >> $(SDK_DIR)/config.mk
	@echo "LDFLAGS += -r -d" >> $(SDK_DIR)/config.mk
	@echo "endif" >> $(SDK_DIR)/config.mk
	@echo "" >> $(SDK_DIR)/config.mk
	@echo "LDFLAGS += -T \$$(LDSCRIPT)" >> $(SDK_DIR)/config.mk
	@echo "CRT0 = \$$(SDK_LIB)/crt0.o" >> $(SDK_DIR)/config.mk
	@echo "LIBC = \$$(SDK_LIB)/libc.a" >> $(SDK_DIR)/config.mk
	@echo "" >> $(SDK_DIR)/config.mk
	@echo "LIBGCC_PATH := \$$(dir \$$(shell \$$(CC) $(CFLAGS) -print-libgcc-file-name))" | sed 's/-I[^ ]*//g' >> $(SDK_DIR)/config.mk
	@echo "PLATFORM_LIBS = -L\$$(LIBGCC_PATH) -lgcc" >> $(SDK_DIR)/config.mk
	# Create example Makefile
	@echo "# Prex SDK Example Makefile" > $(SDK_EXAMPLES)/hello/Makefile
	@echo "include ../../config.mk" >> $(SDK_EXAMPLES)/hello/Makefile
	@echo "" >> $(SDK_EXAMPLES)/hello/Makefile
	@echo "TARGET = hello" >> $(SDK_EXAMPLES)/hello/Makefile
	@echo "SRCS = main.c" >> $(SDK_EXAMPLES)/hello/Makefile
	@echo "OBJS = \$$(SRCS:.c=.o)" >> $(SDK_EXAMPLES)/hello/Makefile
	@echo "" >> $(SDK_EXAMPLES)/hello/Makefile
	@echo "all: \$$(TARGET)" >> $(SDK_EXAMPLES)/hello/Makefile
	@echo "" >> $(SDK_EXAMPLES)/hello/Makefile
	@echo "\$$(TARGET): \$$(OBJS)" >> $(SDK_EXAMPLES)/hello/Makefile
	@echo "	\$$(LD) \$$(LDFLAGS) -o \$$@ \$$(CRT0) \$$(OBJS) \$$(LIBC) \$$(PLATFORM_LIBS)" >> $(SDK_EXAMPLES)/hello/Makefile
	@echo "	\$$(STRIP) \$$(STRIPFLAG) \$$@" >> $(SDK_EXAMPLES)/hello/Makefile
	@echo "" >> $(SDK_EXAMPLES)/hello/Makefile
	@echo "%.o: %.c" >> $(SDK_EXAMPLES)/hello/Makefile
	@echo "	\$$(CC) \$$(CFLAGS) \$$(CPPFLAGS) -c -o \$$@ \$$<" >> $(SDK_EXAMPLES)/hello/Makefile
	@echo "" >> $(SDK_EXAMPLES)/hello/Makefile
	@echo "clean:" >> $(SDK_EXAMPLES)/hello/Makefile
	@echo "	rm -f \$$(TARGET) \$$(OBJS)" >> $(SDK_EXAMPLES)/hello/Makefile
	@echo "SDK generated at $(SDK_DIR)"
