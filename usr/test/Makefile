include $(SRCDIR)/mk/own.mk

# Test for kernel
SUBDIR:=	task thread ipc timer exception fault deadlock sem mutex \
		cpufreq ipc_mt kmon attack stack memleak object

# Test for driver
SUBDIR+=	console kbd fdd ramdisk reset time zero

# Test for library
SUBDIR+=	errno malloc stderr environ assert

# Test for servers
SUBDIR+=	fileio fork forkbomb args signal fifo pipe dup creat conf \
		mount umount shutdown truncate_bug

# Test for audio
SUBDIR+=	beep sndio_test hello

include $(SRCDIR)/mk/subdir.mk
