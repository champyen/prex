# sdk.mk - rules to generate Prex SDK

SDK_DIR = $(SRCDIR)/sdk
SDK_LIB = $(SDK_DIR)/lib
SDK_INC = $(SDK_DIR)/include
SDK_EXAMPLES = $(SDK_DIR)/examples

# Inherit MMU setting from the current build environment (conf/config.mk)
ifeq ($(CONFIG_MMU),y)
    SDK_MMU_DEFAULT = 1
else
    SDK_MMU_DEFAULT = 0
endif

.PHONY: sdk
sdk:
	@echo "Generating Prex SDK (MMU=$(SDK_MMU_DEFAULT))..."
	@mkdir -p $(SDK_LIB) $(SDK_INC) $(SDK_EXAMPLES)
	# Clean old/legacy configs
	rm -f $(SDK_DIR)/config-tcc.mk $(SDK_DIR)/config.mk $(SDK_DIR)/config.*.mk
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
	# Create sdk/share/mk/sys.mk
	mkdir -p $(SDK_DIR)/share/mk
	@echo ".SUFFIXES: .out .a .ln .o .c .cc .C .cpp .p .f .F .r .y .l .s .S .cl .p .h .sh .m4" > $(SDK_DIR)/share/mk/sys.mk
	@printf ".c.o:\n\t\$$(CC) \$$(CFLAGS) \$$(CPPFLAGS) -c -o \$$@ \$$<\n" >> $(SDK_DIR)/share/mk/sys.mk
	@echo "" >> $(SDK_DIR)/share/mk/sys.mk
	# --- The Dispatcher (sdk/config.mk) ---
	@echo "# Prex SDK Main Configuration" > $(SDK_DIR)/config.mk
	@echo "ARCH ?= $(ARCH)" >> $(SDK_DIR)/config.mk
	@echo "MMU ?= $(SDK_MMU_DEFAULT)" >> $(SDK_DIR)/config.mk
	@echo "IS_PREX ?= 0" >> $(SDK_DIR)/config.mk
	@echo "SDK_ROOT_0 := $(abspath $(SDK_DIR))" >> $(SDK_DIR)/config.mk
	@echo "SDK_ROOT_1 := /usr" >> $(SDK_DIR)/config.mk
	@echo "include \$$(SDK_ROOT_\$$(IS_PREX))/config.\$$(IS_PREX).mk" >> $(SDK_DIR)/config.mk
	# --- Host Configuration (sdk/config.0.mk) ---
	@echo "# Host GCC Configuration" > $(SDK_DIR)/config.0.mk
	@echo "CROSS_COMPILE = arm-none-eabi-" >> $(SDK_DIR)/config.0.mk
	@echo "CC = \$$(CROSS_COMPILE)gcc" >> $(SDK_DIR)/config.0.mk
	@echo "LD = \$$(CROSS_COMPILE)gcc" >> $(SDK_DIR)/config.0.mk
	@echo "AS = \$$(CROSS_COMPILE)as" >> $(SDK_DIR)/config.0.mk
	@echo "AR = \$$(CROSS_COMPILE)ar" >> $(SDK_DIR)/config.0.mk
	@echo "STRIP = \$$(CROSS_COMPILE)strip" >> $(SDK_DIR)/config.0.mk
	@echo "SDK_ROOT = $(abspath $(SDK_DIR))" >> $(SDK_DIR)/config.0.mk
	@echo "LDFLAGS_1 = -T \$$(SDK_ROOT)/lib/user.ld" >> $(SDK_DIR)/config.0.mk
	@echo "LDFLAGS_0 = -T \$$(SDK_ROOT)/lib/user-nommu.ld" >> $(SDK_DIR)/config.0.mk
	@echo "LDFLAGS_ENV = \$$(LDFLAGS_\$$(MMU))" >> $(SDK_DIR)/config.0.mk
	@echo "PLATFORM_LIBS =" >> $(SDK_DIR)/config.0.mk
	@echo "include \$$(SDK_ROOT)/config.common.mk" >> $(SDK_DIR)/config.0.mk
	# --- Device Configuration (sdk/config.1.mk) ---
	@echo "# Device TCC Configuration" > $(SDK_DIR)/config.1.mk
	@echo "CC = /usr/bin/tcc -B/usr/lib/tcc" >> $(SDK_DIR)/config.1.mk
	@echo "LD = /usr/bin/tcc -B/usr/lib/tcc" >> $(SDK_DIR)/config.1.mk
	@echo "AS = /usr/bin/tcc -B/usr/lib/tcc -c" >> $(SDK_DIR)/config.1.mk
	@echo "AR = /usr/bin/tcc -B/usr/lib/tcc -ar" >> $(SDK_DIR)/config.1.mk
	@echo "STRIP = strip" >> $(SDK_DIR)/config.1.mk
	@echo "SDK_ROOT = /usr" >> $(SDK_DIR)/config.1.mk
	@echo "LDFLAGS_1 = -Wl,-Ttext=0x10000" >> $(SDK_DIR)/config.1.mk
	@echo "LDFLAGS_0 = -Wl,-Ttext=0x0" >> $(SDK_DIR)/config.1.mk
	@echo "LDFLAGS_ENV = \$$(LDFLAGS_\$$(MMU))" >> $(SDK_DIR)/config.1.mk
	@echo "PLATFORM_LIBS = /usr/lib/tcc/libtcc1.a" >> $(SDK_DIR)/config.1.mk
	@echo "CPPFLAGS += -DPOSIX" >> $(SDK_DIR)/config.1.mk
	@echo "include \$$(SDK_ROOT)/config.common.mk" >> $(SDK_DIR)/config.1.mk
	# --- Common Settings (sdk/config.common.mk) ---
	@echo "SDK_INC = \$$(SDK_ROOT)/include" > $(SDK_DIR)/config.common.mk
	@echo "SDK_LIB = \$$(SDK_ROOT)/lib" >> $(SDK_DIR)/config.common.mk
	@echo "CFLAGS += -nostdinc -g" >> $(SDK_DIR)/config.common.mk
	@echo "CPPFLAGS += -I. -I\$$(SDK_INC) -I\$$(SDK_INC)/ipc -I\$$(SDK_INC)/machine" >> $(SDK_DIR)/config.common.mk
	@echo "LDFLAGS += -static -nostdlib -L\$$(SDK_LIB) \$$(LDFLAGS_ENV)" >> $(SDK_DIR)/config.common.mk
	@echo "CRT0 = \$$(SDK_LIB)/crt0.o" >> $(SDK_DIR)/config.common.mk
	@echo "LIBC = \$$(SDK_LIB)/libc.a" >> $(SDK_DIR)/config.common.mk
	# Create clean example Makefile
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
	@echo "" >> $(SDK_EXAMPLES)/hello/Makefile
	@echo "clean:" >> $(SDK_EXAMPLES)/hello/Makefile
	@echo "	rm -f \$$(TARGET) \$$(OBJS)" >> $(SDK_EXAMPLES)/hello/Makefile
	# Build and copy tinycc to sdk/bin
	make -C usr/sample/tinycc SRCDIR=$(SRCDIR)
	# Build and copy make to sdk/bin
	make -C usr/sample/make SRCDIR=$(SRCDIR)
	mkdir -p $(SDK_DIR)/bin
	cp usr/sample/tinycc/tcc $(SDK_DIR)/bin/tcc
	cp usr/sample/make/make $(SDK_DIR)/bin/make
	# Copy libtcc1.a to sdk/lib/tcc/
	mkdir -p $(SDK_DIR)/lib/tcc/include
	cp ../tinycc/arm-none-eabi-libtcc1.a $(SDK_DIR)/lib/tcc/libtcc1.a
	cp -r ../tinycc/include/* $(SDK_DIR)/lib/tcc/include/
	# Create on-device build script
	@echo "#!/bin/sh" > $(SDK_DIR)/build_hello.sh
	@echo "echo 'Building hello example with make on-device...'" >> $(SDK_DIR)/build_hello.sh
	@echo "cd /usr/examples/hello && /usr/bin/make" >> $(SDK_DIR)/build_hello.sh
	@echo "echo 'Running /usr/examples/hello/hello...'" >> $(SDK_DIR)/build_hello.sh
	@echo "/usr/examples/hello/hello" >> $(SDK_DIR)/build_hello.sh
	@echo "SDK generated at $(SDK_DIR)"

.PHONY: sdk-tcc
sdk-tcc: sdk
	@echo "Generating Prex SDK for TinyCC..."
