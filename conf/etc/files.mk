#
# Files in /boot
#

ifeq ($(CONFIG_POSIX),y)

FILES+= 	$(SRCDIR)/usr/sbin/init/init
FILES+= 	$(SRCDIR)/conf/etc/rc
FILES+= 	$(SRCDIR)/conf/etc/fstab

ifeq ($(CONFIG_CMDBOX),y)
FILES+= 	$(SRCDIR)/usr/bin/cmdbox/cmdbox
endif

#FILES+= 	$(SRCDIR)/usr/bin/tcc/tcc

ifeq ($(CONFIG_CMD_KTRACE),y)
FILES+= 	$(SRCDIR)/usr/sbin/ktrace/ktrace
endif

ifeq ($(CONFIG_CMD_DISKUTIL),y)
FILES+= 	$(SRCDIR)/usr/sbin/diskutil/diskutil
endif

ifeq ($(CONFIG_CMD_INSTALL),y)
FILES+= 	$(SRCDIR)/usr/sbin/install/install
endif

ifeq ($(CONFIG_CMD_PMCTRL),y)
FILES+= 	$(SRCDIR)/usr/sbin/pmctrl/pmctrl
endif

ifeq ($(CONFIG_CMD_LOCK),y)
FILES+= 	$(SRCDIR)/usr/sbin/lock/lock
endif

ifeq ($(CONFIG_CMD_DEBUG),y)
FILES+= 	$(SRCDIR)/usr/sbin/debug/debug
endif

ifeq ($(CONFIG_SNDIO),y)
FILES+=		$(SRCDIR)/usr/server/sndio/sndiod
#FILES+=		$(SRCDIR)/usr/sample/beep/beep
FILES+=		$(SRCDIR)/usr/sample/sndio_test/sndio_test
FILES+=		$(SRCDIR)/usr/sample/playwav/playwav
endif

ifneq ($(_QUICK_),1)
ifneq ($(CONFIG_TINY),y)
FILES+=		$(SRCDIR)/usr/sample/hello/hello
FILES+=		$(SRCDIR)/usr/sample/tetris/tetris
endif
endif

#FILES+= 	$(SRCDIR)/usr/test/args/args
#FILES+= 	$(SRCDIR)/usr/test/attack/attack
#FILES+= 	$(SRCDIR)/usr/test/conf/conf
#FILES+= 	$(SRCDIR)/usr/test/creat/creat
#FILES+= 	$(SRCDIR)/usr/test/debug/debug
#FILES+= 	$(SRCDIR)/usr/test/dup/dup
#FILES+= 	$(SRCDIR)/usr/test/environ/environ
#FILES+= 	$(SRCDIR)/usr/test/fifo/fifo
#FILES+= 	$(SRCDIR)/usr/test/fork/fork
#FILES+= 	$(SRCDIR)/usr/test/forkbomb/forkbomb
#FILES+= 	$(SRCDIR)/usr/test/memleak/memleak
#FILES+= 	$(SRCDIR)/usr/test/mount/mount
#FILES+= 	$(SRCDIR)/usr/test/object/object
#FILES+= 	$(SRCDIR)/usr/test/pipe/pipe
#FILES+= 	$(SRCDIR)/usr/test/script/hello.sh
#FILES+= 	$(SRCDIR)/usr/test/signal/signal
#FILES+= 	$(SRCDIR)/usr/test/stack/stack
#FILES+= 	$(SRCDIR)/usr/test/stderr/stderr
#FILES+= 	$(SRCDIR)/usr/test/umount/umount

FILES+=		$(SRCDIR)/doc/LICENSE

endif	# !CONFIG_POSIX
