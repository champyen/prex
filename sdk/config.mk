# Prex SDK Main Configuration
ARCH ?= arm
MMU ?= 1
IS_PREX ?= 0
SDK_ROOT_0 := /home/champ/workspace/gemini_playground/prex/sdk
SDK_ROOT_1 := /usr
include $(SDK_ROOT_$(IS_PREX))/config.$(IS_PREX).mk
