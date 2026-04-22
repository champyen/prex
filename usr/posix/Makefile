include $(SRCDIR)/mk/own.mk

# Standalone tools (always built as standalone if enabled)
SUBDIR-$(CONFIG_CMD_KILO)+=	kilo
SUBDIR-$(CONFIG_CMD_PING)+=	ping
SUBDIR-$(CONFIG_CMD_NC)+=	nc
SUBDIR-$(CONFIG_CMD_CP)+=	cp
SUBDIR-$(CONFIG_CMD_DD)+=	dd
SUBDIR-$(CONFIG_CMD_FIND)+=	find
SUBDIR-$(CONFIG_CMD_FREE)+=	free
SUBDIR-$(CONFIG_CMD_GREP)+=	grep
SUBDIR-$(CONFIG_CMD_GZIP)+=	gzip
SUBDIR-$(CONFIG_CMD_HEAD)+=	head
SUBDIR-$(CONFIG_CMD_HEXDUMP)+=	hexdump
SUBDIR-$(CONFIG_CMD_HOSTNAME)+=	hostname
SUBDIR-$(CONFIG_CMD_MORE)+=	more
SUBDIR-$(CONFIG_CMD_MV)+=	mv
SUBDIR-$(CONFIG_CMD_NICE)+=	nice
SUBDIR-$(CONFIG_CMD_PRINTENV)+=	printenv
SUBDIR-$(CONFIG_CMD_PWD)+=	pwd
SUBDIR-$(CONFIG_CMD_RMDIR)+=	rmdir
SUBDIR-$(CONFIG_CMD_SLEEP)+=	sleep
SUBDIR-$(CONFIG_CMD_SORT)+=	sort
SUBDIR-$(CONFIG_CMD_TAIL)+=	tail
SUBDIR-$(CONFIG_CMD_TAR)+=	tar
SUBDIR-$(CONFIG_CMD_TEST)+=	test
SUBDIR-$(CONFIG_CMD_TOUCH)+=	touch
SUBDIR-$(CONFIG_CMD_UNAME)+=	uname
SUBDIR-$(CONFIG_CMD_WC)+=	wc
SUBDIR-$(CONFIG_CMD_XARGS)+=	xargs
SUBDIR-$(CONFIG_NET)+=		ifconfig
SUBDIR-$(CONFIG_SQLITE)+=	sqlite3
SUBDIR-$(CONFIG_SNDIO)+=	helixmp3 playwav
SUBDIR-$(CONFIG_SDK)+=		make tinycc
SUBDIR-$(CONFIG_CMD_TETRIS)+=	tetris
SUBDIR-$(CONFIG_CMD_INIT)+=	init
SUBDIR-$(CONFIG_CMD_PMCTRL)+=	pmctrl
SUBDIR-$(CONFIG_CMD_DISKUTIL)+=	diskutil
SUBDIR-$(CONFIG_CMD_KTRACE)+=	ktrace
SUBDIR-$(CONFIG_CMD_DEBUG)+=	debug

# cmdbox is always built if CONFIG_CMDBOX=y
SUBDIR-$(CONFIG_CMDBOX)+=	cmdbox

# Final SUBDIR list - use sort to remove duplicates if any
SUBDIR=		$(sort $(SUBDIR-y))

include $(SRCDIR)/mk/subdir.mk
