#
# Makefile for audio drivers
#
SRCS-$(CONFIG_AUDIO) += dev/audio/audio.c
SRCS-$(CONFIG_VIO_AUDIO) += dev/audio/vio_audio.c

#CFLAGS += -DDEBUG_VIO_AUDIO
