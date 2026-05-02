#
# Files in /boot
#

ifeq ($(CONFIG_POSIX),y)

FILES+= 	$(SRCDIR)/usr/posix/init/init
FILES+= 	$(SRCDIR)/conf/etc/rc
FILES+= 	$(SRCDIR)/conf/etc/fstab

ifeq ($(CONFIG_CMDBOX),y)
FILES+= 	$(SRCDIR)/usr/posix/cmdbox/cmdbox/cmdbox
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
#FILES+= 	$(SRCDIR)/usr/test/fault/fault
#FILES+= 	$(SRCDIR)/usr/test/assert/assert_test

FILES+=		$(SRCDIR)/doc/LICENSE

endif	# !CONFIG_POSIX
