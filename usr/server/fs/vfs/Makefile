include $(SRCDIR)/conf/config.mk

TARGET=		vfscore.o
ifeq ($(CONFIG_ZIG_USR),y)
SRCS=		main.c vfs_conf.zig vfs_task.zig vfs_globals.c vfs_syscalls.zig \
		vfs_mount.zig vfs_bio.zig vfs_vnode.zig vfs_lookup.zig \
		vfs_security.zig vfs_poll.zig
else
SRCS=		main.c vfs_conf.c vfs_task.c vfs_syscalls.c \
		vfs_mount.c vfs_bio.c vfs_vnode.c vfs_lookup.c \
		vfs_security.c vfs_poll.c
endif

_CONFIG_MK_:=
include $(SRCDIR)/mk/obj.mk
