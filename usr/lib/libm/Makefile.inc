# usr/lib/libm/Makefile.inc
# Main math library orchestrator

# Include the selected implementation's Makefile
include $(SRCDIR)/usr/lib/libm/$(CONFIG_LIBM)/Makefile.inc

# Ensure the correct math.h is found during compilation
INCFLAGS += -I$(SRCDIR)/usr/lib/libm/$(CONFIG_LIBM)
