# usr/lib/libm/fdlibm/Makefile.inc

LIBM_DIR := $(SRCDIR)/usr/lib/libm/fdlibm

SRCS += $(LIBM_DIR)/s_sin.c \
        $(LIBM_DIR)/s_cos.c \
        $(LIBM_DIR)/s_fabs.c \
        $(LIBM_DIR)/e_sqrt.c \
        $(LIBM_DIR)/k_sin.c \
        $(LIBM_DIR)/k_cos.c \
        $(LIBM_DIR)/k_tan.c \
        $(LIBM_DIR)/e_rem_pio2.c \
        $(LIBM_DIR)/k_rem_pio2.c \
        $(LIBM_DIR)/s_ldexp.c \
        $(LIBM_DIR)/s_scalbn.c \
        $(LIBM_DIR)/s_finite.c \
        $(LIBM_DIR)/s_copysign.c \
        $(LIBM_DIR)/s_floor.c
