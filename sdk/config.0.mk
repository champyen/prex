# Host GCC Configuration
CROSS_COMPILE = arm-none-eabi-
CC = $(CROSS_COMPILE)gcc
LD = $(CROSS_COMPILE)gcc
AS = $(CROSS_COMPILE)as
AR = $(CROSS_COMPILE)ar
STRIP = $(CROSS_COMPILE)strip
SDK_ROOT = /home/champ/workspace/gemini_playground/prex/sdk
LDFLAGS_1 = -T $(SDK_ROOT)/lib/user.ld
LDFLAGS_0 = -T $(SDK_ROOT)/lib/user-nommu.ld
LDFLAGS_ENV = $(LDFLAGS_$(MMU))
PLATFORM_LIBS =
include $(SDK_ROOT)/config.common.mk
