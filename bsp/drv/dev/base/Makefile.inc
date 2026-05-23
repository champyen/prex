
SRCS+=			dev/base/main.c \
			dev/base/init.c \
			dev/base/tty.c

SRCS-$(CONFIG_PM)+=	dev/base/pm.c
SRCS-$(CONFIG_CONS)+=	dev/base/cons.c
SRCS-$(CONFIG_WSCONS)+=	dev/base/wscons.c

ifeq ($(DEBUG),1)
SRCS-$(CONFIG_KD)+=	dev/base/kd.c
endif

SRCS-$(CONFIG_VIO_MMIO)+= dev/base/vio_mmio.c
