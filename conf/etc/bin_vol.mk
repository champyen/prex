#
# Files in /bin (bin.img)
#

BIN_FILES-$(CONFIG_CMD_KILO)+= $(SRCDIR)/usr/posix/kilo/kilo
BIN_FILES-$(CONFIG_CMD_PING)+= $(SRCDIR)/usr/posix/ping/ping
BIN_FILES-$(CONFIG_CMD_NC)+= $(SRCDIR)/usr/posix/nc/nc
BIN_FILES-$(CONFIG_CMD_CP)+= $(SRCDIR)/usr/posix/cp/cp
BIN_FILES-$(CONFIG_CMD_DD)+= $(SRCDIR)/usr/posix/dd/dd
BIN_FILES-$(CONFIG_CMD_FIND)+= $(SRCDIR)/usr/posix/find/find
BIN_FILES-$(CONFIG_CMD_FREE)+= $(SRCDIR)/usr/posix/free/free
BIN_FILES-$(CONFIG_CMD_GREP)+= $(SRCDIR)/usr/posix/grep/grep
BIN_FILES-$(CONFIG_CMD_GZIP)+= $(SRCDIR)/usr/posix/gzip/gzip
BIN_FILES-$(CONFIG_CMD_HEAD)+= $(SRCDIR)/usr/posix/head/head
BIN_FILES-$(CONFIG_CMD_HEXDUMP)+= $(SRCDIR)/usr/posix/hexdump/hexdump
BIN_FILES-$(CONFIG_CMD_HOSTNAME)+= $(SRCDIR)/usr/posix/hostname/hostname
BIN_FILES-$(CONFIG_CMD_MORE)+= $(SRCDIR)/usr/posix/more/more
BIN_FILES-$(CONFIG_CMD_MV)+= $(SRCDIR)/usr/posix/mv/mv
BIN_FILES-$(CONFIG_CMD_NICE)+= $(SRCDIR)/usr/posix/nice/nice
BIN_FILES-$(CONFIG_CMD_PRINTENV)+= $(SRCDIR)/usr/posix/printenv/printenv
BIN_FILES-$(CONFIG_CMD_PWD)+= $(SRCDIR)/usr/posix/pwd/pwd
BIN_FILES-$(CONFIG_CMD_RMDIR)+= $(SRCDIR)/usr/posix/rmdir/rmdir
BIN_FILES-$(CONFIG_CMD_SLEEP)+= $(SRCDIR)/usr/posix/sleep/sleep
BIN_FILES-$(CONFIG_CMD_SORT)+= $(SRCDIR)/usr/posix/sort/sort
BIN_FILES-$(CONFIG_CMD_TAIL)+= $(SRCDIR)/usr/posix/tail/tail
BIN_FILES-$(CONFIG_CMD_TAR)+= $(SRCDIR)/usr/posix/tar/tar
BIN_FILES-$(CONFIG_CMD_TEST)+= $(SRCDIR)/usr/posix/test/test
BIN_FILES-$(CONFIG_CMD_TOUCH)+= $(SRCDIR)/usr/posix/touch/touch
BIN_FILES-$(CONFIG_CMD_UNAME)+= $(SRCDIR)/usr/posix/uname/uname
BIN_FILES-$(CONFIG_CMD_WC)+= $(SRCDIR)/usr/posix/wc/wc
BIN_FILES-$(CONFIG_CMD_XARGS)+= $(SRCDIR)/usr/posix/xargs/xargs
BIN_FILES-$(CONFIG_SNDIO)+= $(SRCDIR)/usr/posix/playwav/playwav
BIN_FILES-$(CONFIG_CMD_DISKUTIL)+= $(SRCDIR)/usr/posix/diskutil/diskutil
BIN_FILES-$(CONFIG_CMD_PMCTRL)+= $(SRCDIR)/usr/posix/pmctrl/pmctrl
BIN_FILES-$(CONFIG_CMD_KTRACE)+= $(SRCDIR)/usr/posix/ktrace/ktrace
BIN_FILES-$(CONFIG_CMD_DEBUG)+= $(SRCDIR)/usr/posix/debug/debug

BIN_FILES= $(BIN_FILES-y)
