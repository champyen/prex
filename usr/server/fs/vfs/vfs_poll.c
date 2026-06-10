/*
 * Copyright (c) 2026, Champ Yen (champ.yen@gmail.com)
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the author nor the names of any co-contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

/*
 * vfs_poll.c - I/O multiplexing support
 */

#include <sys/prex.h>
#include <sys/list.h>
#include <sys/vnode.h>
#include <sys/file.h>
#include <sys/mount.h>
#include <sys/poll.h>
#include <ipc/fs.h>

#include <limits.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>

#include "vfs.h"

/*
 * List of all active poll listeners in the VFS server.
 */
static struct list poll_list = LIST_INIT(poll_list);

int sys_poll_register(struct task* t, sem_t sem, int nfds, struct poll_entry* fds)
{
    struct poll_listener* pl;
    file_t fp;
    vnode_t vp;
    int i;

    for (i = 0; i < nfds; i++) {
        fp = task_getfp(t, fds[i].fd);
        if (fp == NULL)
            return EBADF;

        if (!(pl = malloc(sizeof(struct poll_listener))))
            return ENOMEM;

        pl->sem = sem;
        pl->events = fds[i].events;
        pl->vp = fp->f_vnode;
        list_init(&pl->link);
        list_init(&pl->g_link);

        vp = fp->f_vnode;
        vnode_poll_register(vp, pl);
        
        /* Add to global poll list for cleanup */
        list_insert(&poll_list, &pl->g_link);
    }
    return 0;
}

int sys_poll_deregister(struct task* t, sem_t sem)
{
    list_t n, next;
    struct poll_listener* pl;

    for (n = list_first(&poll_list); n != &poll_list; n = next) {
        next = list_next(n);
        pl = list_entry(n, struct poll_listener, g_link);
        if (pl->sem == sem) {
            vnode_poll_deregister(pl->vp, pl);
            list_remove(&pl->g_link);
            free(pl);
        }
    }
    return 0;
}

int sys_poll_query(struct task* t, int nfds, struct poll_entry* fds)
{
    file_t fp;
    vnode_t vp;
    int i, ready = 0;
    short revents;

    for (i = 0; i < nfds; i++) {
        fp = task_getfp(t, fds[i].fd);
        if (fp == NULL) {
            fds[i].revents = POLLNVAL;
            ready++;
            continue;
        }

        vp = fp->f_vnode;
        revents = 0;

        /* 
         * Check readiness via VOP_IOCTL or a new VOP_POLL.
         * For now, we use a simplified check.
         * VOP_IOCTL with FIONREAD could be used for POLLIN.
         */
        if (fds[i].events & POLLIN) {
            /* 
             * For now, we'll need to call into the actual FS driver.
             * But since we don't have VOP_POLL yet, we might use VOP_IOCTL or similar.
             * As a placeholder, we'll assume not ready if it's a device/pipe we know.
             */
            if (vp->v_type == VFIFO || vp->v_type == VCHR) {
                /* Will be implemented in Stage 3/4 */
                revents = 0; 
            } else {
                revents |= POLLIN; /* Regular files are usually always "ready" */
            }
        }
        
        if (revents) {
            fds[i].revents = revents;
            ready++;
        } else {
            fds[i].revents = 0;
        }
    }
    return ready;
}
