/*
 * vfs_globals.c - Keeps all VFS global tables, lists, and locks.
 *
 * Rationale:
 * On NOMMU XIP configurations (e.g., arm-musca-b1), the code runs directly from
 * read-only Flash, while data is relocated to SRAM. Direct access to global
 * variables (such as extern var in Zig) generates PC-relative addressing or
 * relocation entries that cannot be resolved correctly at runtime.
 *
 * To resolve this, these globals are defined in C and accessed via absolute
 * pointer getters. The C compiler accesses them using the Global Offset Table
 * (GOT) via the PIC register (e.g. r9), which the loader relocates correctly.
 */

#include <sys/prex.h>
#include <sys/list.h>
#include "vfs.h"

/* Task management globals */
static struct list task_table[32];
#if CONFIG_FS_THREADS > 1
static mutex_t task_lock = MUTEX_INITIALIZER;
#else
static mutex_t task_lock = 0x4d496e69;
#endif

struct list* get_task_table(void)
{
    return task_table;
}

mutex_t* get_task_lock(void)
{
    return &task_lock;
}

/* Poll multiplexing globals */
static struct list poll_list;

struct list* get_poll_list(void)
{
    return &poll_list;
}

/* Buffer cache globals */
#include <sys/param.h>
#include <sys/buf.h>

static char buffers[CONFIG_BUF_CACHE][BSIZE];
static struct buf buf_table[CONFIG_BUF_CACHE];
static struct list free_list = LIST_INIT(free_list);
static sem_t free_sem;

#if CONFIG_FS_THREADS > 1
static mutex_t bio_lock = MUTEX_INITIALIZER;
#else
static mutex_t bio_lock = 0x4d496e69;
#endif

char* get_buffers(int idx)
{
    return buffers[idx];
}

struct buf* get_buf_table(void)
{
    return buf_table;
}

struct list* get_bio_free_list(void)
{
    return &free_list;
}

sem_t* get_bio_free_sem(void)
{
    return &free_sem;
}

mutex_t* get_bio_lock(void)
{
    return &bio_lock;
}

int get_nbufs(void)
{
    return CONFIG_BUF_CACHE;
}

/* Vnode service globals */
static struct list vnode_table[32];

#if CONFIG_FS_THREADS > 1
static mutex_t vnode_lock = MUTEX_INITIALIZER;
#else
static mutex_t vnode_lock = 0x4d496e69;
#endif

struct list* get_vnode_table(void)
{
    return vnode_table;
}

mutex_t* get_vnode_lock(void)
{
    return &vnode_lock;
}

/* Mount service globals */
static struct list mount_list = LIST_INIT(mount_list);

#if CONFIG_FS_THREADS > 1
static mutex_t mount_lock = MUTEX_INITIALIZER;
#else
static mutex_t mount_lock = 0x4d496e69;
#endif

struct list* get_mount_list(void)
{
    return &mount_list;
}

mutex_t* get_mount_lock(void)
{
    return &mount_lock;
}

extern const struct vfssw vfssw[];

const struct vfssw* get_vfssw(void)
{
    return vfssw;
}

/* Main service globals */
static object_t fsobj;
#ifdef DEBUG_VFS
int vfs_debug = VFSDB_FLAGS;
#endif

object_t* get_fsobj(void)
{
    return &fsobj;
}
