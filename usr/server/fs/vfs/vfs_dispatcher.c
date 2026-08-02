/*
 * vfs_dispatcher.c - IPC dispatcher and msg_map table for FS server
 *
 * All individual fs_*() handlers live in main.zig (Zig-exported).
 * This file owns only the dispatch table and the per-thread loop.
 */

#include <sys/prex.h>
#include <sys/capability.h>
#include <sys/param.h>
#include <ipc/fs.h>
#include <ipc/proc.h>
#include <ipc/exec.h>
#include <ipc/ipc.h>
#include <sys/list.h>
#include <sys/stat.h>
#include <sys/vnode.h>
#include <sys/mount.h>
#include <sys/buf.h>
#include <sys/file.h>

#include <limits.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#include "vfs.h"

/* Zig-exported IPC handlers (see main.zig). */
extern int fs_sync(struct task*, struct msg*);
extern int fs_getcwd(struct task*, struct path_msg*);
extern int fs_isatty(struct task*, struct msg*);
extern int fs_lseek(struct task*, struct msg*);
extern int fs_readdir(struct task*, struct dir_msg*);
extern int fs_rewinddir(struct task*, struct msg*);
extern int fs_seekdir(struct task*, struct msg*);
extern int fs_telldir(struct task*, struct msg*);
extern int fs_close(struct task*, struct msg*);
extern int fs_mknod(struct task*, struct open_msg*);
extern int fs_mkdir(struct task*, struct open_msg*);
extern int fs_rmdir(struct task*, struct path_msg*);
extern int fs_link(struct task*, struct msg*);
extern int fs_unlink(struct task*, struct path_msg*);
extern int fs_stat(struct task*, struct stat_msg*);
extern int fs_access(struct task*, struct path_msg*);
extern int fs_truncate(struct task*, struct path_msg*);
extern int fs_ioctl(struct task*, struct ioctl_msg*);
extern int fs_fsync(struct task*, struct msg*);
extern int fs_fstat(struct task*, struct stat_msg*);
extern int fs_closedir(struct task*, struct msg*);
extern int fs_opendir(struct task*, struct open_msg*);
extern int fs_open(struct task*, struct open_msg*);
extern int fs_read(struct task*, struct io_msg*);
extern int fs_write(struct task*, struct io_msg*);
extern int fs_chdir(struct task*, struct path_msg*);
extern int fs_fchdir(struct task*, struct msg*);
extern int fs_rename(struct task*, struct path_msg*);
extern int fs_dup(struct task*, struct msg*);
extern int fs_dup2(struct task*, struct msg*);
extern int fs_fcntl(struct task*, struct fcntl_msg*);
extern int fs_pipe(struct task*, struct msg*);
extern int fs_register(struct task*, struct msg*);
extern int fs_fork(struct task*, struct msg*);
extern int fs_exec(struct task*, struct msg*);
extern int fs_exit(struct task*, struct msg*);
extern int fs_poll_register(struct task*, struct fs_poll_msg*);
extern int fs_poll_deregister(struct task*, struct fs_poll_msg*);
extern int fs_poll_query(struct task*, struct fs_poll_msg*);
extern int fs_ftruncate(struct task*, struct msg*);
extern int fs_mount(struct task*, struct mount_msg*);
extern int fs_umount(struct task*, struct path_msg*);
extern int fs_boot(struct task*, struct msg*);
extern int fs_shutdown(struct task*, struct msg*);
#ifdef DEBUG_VFS
extern int fs_debug(struct task*, struct msg*);
#endif

struct msg_map
{
    int code;
    int (*func)(struct task*, struct msg*);
};

#define MSGMAP(code, fn)                                                                                               \
    {                                                                                                                  \
        code, (int (*)(struct task*, struct msg*))fn                                                                   \
    }

/* object for file service - stored in vfs_globals.c, accessed via get_fsobj() */
extern object_t* get_fsobj(void);

/*
 * Message mapping
 */
static const struct msg_map fsmsg_map[] = {
    MSGMAP(FS_MOUNT, fs_mount),
    MSGMAP(FS_UMOUNT, fs_umount),
    MSGMAP(FS_SYNC, fs_sync),
    MSGMAP(FS_OPEN, fs_open),
    MSGMAP(FS_CLOSE, fs_close),
    MSGMAP(FS_MKNOD, fs_mknod),
    MSGMAP(FS_LSEEK, fs_lseek),
    MSGMAP(FS_READ, fs_read),
    MSGMAP(FS_WRITE, fs_write),
    MSGMAP(FS_IOCTL, fs_ioctl),
    MSGMAP(FS_FSYNC, fs_fsync),
    MSGMAP(FS_FSTAT, fs_fstat),
    MSGMAP(FS_OPENDIR, fs_opendir),
    MSGMAP(FS_CLOSEDIR, fs_closedir),
    MSGMAP(FS_READDIR, fs_readdir),
    MSGMAP(FS_REWINDDIR, fs_rewinddir),
    MSGMAP(FS_SEEKDIR, fs_seekdir),
    MSGMAP(FS_TELLDIR, fs_telldir),
    MSGMAP(FS_MKDIR, fs_mkdir),
    MSGMAP(FS_RMDIR, fs_rmdir),
    MSGMAP(FS_RENAME, fs_rename),
    MSGMAP(FS_CHDIR, fs_chdir),
    MSGMAP(FS_LINK, fs_link),
    MSGMAP(FS_UNLINK, fs_unlink),
    MSGMAP(FS_STAT, fs_stat),
    MSGMAP(FS_GETCWD, fs_getcwd),
    MSGMAP(FS_DUP, fs_dup),
    MSGMAP(FS_DUP2, fs_dup2),
    MSGMAP(FS_FCNTL, fs_fcntl),
    MSGMAP(FS_ACCESS, fs_access),
    MSGMAP(FS_FORK, fs_fork),
    MSGMAP(FS_EXEC, fs_exec),
    MSGMAP(FS_EXIT, fs_exit),
    MSGMAP(FS_REGISTER, fs_register),
    MSGMAP(FS_PIPE, fs_pipe),
    MSGMAP(FS_ISATTY, fs_isatty),
    MSGMAP(FS_TRUNCATE, fs_truncate),
    MSGMAP(FS_FTRUNCATE, fs_ftruncate),
    MSGMAP(FS_FCHDIR, fs_fchdir),
    MSGMAP(FS_POLL_REGISTER, fs_poll_register),
    MSGMAP(FS_POLL_DEREGISTER, fs_poll_deregister),
    MSGMAP(FS_POLL_QUERY, fs_poll_query),
    MSGMAP(STD_BOOT, fs_boot),
    MSGMAP(STD_SHUTDOWN, fs_shutdown),
#ifdef DEBUG_VFS
    MSGMAP(STD_DEBUG, fs_debug),
#endif
    MSGMAP(0, NULL),
};

/*
 * File system thread.
 */
void fs_thread(void)
{
    struct msg* msg;
    const struct msg_map* map;
    struct task* t;
    object_t fsobj;
    int error;
    size_t msg_size = 1024; /* Enough for struct path_msg and others */

    msg = malloc(msg_size);
    fsobj = *get_fsobj();

    /*
     * Message loop
     */
    for (;;) {
        /*
         * Wait for an incoming request.
         */
        if ((error = msg_receive(fsobj, msg, msg_size)) != 0)
            continue;

        error = EINVAL;
        map = &fsmsg_map[0];
        while (map->code != 0) {
            if (map->code == msg->hdr.code) {
                /*
                 * Handle messages by non-registerd tasks
                 */
                if (map->code == STD_BOOT) {
                    error = fs_boot(NULL, msg);
                    break;
                }
                if (map->code == FS_REGISTER) {
                    error = fs_register(NULL, msg);
                    break;
                }

                /* Lookup and lock task */
                t = task_lookup(msg->hdr.task);
                if (t == NULL)
                    break;

                /* Dispatch request */
                error = (*map->func)(t, msg);
                if (map->code != FS_EXIT)
                    task_unlock(t);
                break;
            }
            map++;
        }
#ifdef DEBUG_VFS
        if (error)
            dprintf("VFS: task=%x code=%x error=%d\n", msg->hdr.task, map->code, error);
#endif
        /*
         * Reply to the client.
         */
        msg->hdr.status = error;
        msg_reply(fsobj, msg, MAX_FSMSG);
    }
}
