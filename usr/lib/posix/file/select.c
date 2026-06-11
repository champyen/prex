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

#include <sys/prex.h>
#include <sys/select.h>
#include <sys/poll.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>

int select(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, struct timeval *timeout)
{
    struct pollfd fds[32];
    int i, poll_nfds = 0;
    int nready, ready_count = 0;
    int msec;

    if (nfds > FD_SETSIZE) {
        errno = EINVAL;
        return -1;
    }

    for (i = 0; i < nfds; i++) {
        fds[poll_nfds].events = 0;
        if (readfds && FD_ISSET(i, readfds))
            fds[poll_nfds].events |= POLLIN;
        if (writefds && FD_ISSET(i, writefds))
            fds[poll_nfds].events |= POLLOUT;
        if (exceptfds && FD_ISSET(i, exceptfds))
            fds[poll_nfds].events |= POLLPRI;

        if (fds[poll_nfds].events) {
            fds[poll_nfds].fd = i;
            fds[poll_nfds].revents = 0;
            poll_nfds++;
        }
    }

    if (timeout) {
        msec = timeout->tv_sec * 1000 + timeout->tv_usec / 1000;
    } else {
        msec = -1;
    }

    nready = poll(fds, poll_nfds, msec);
    if (nready <= 0)
        return nready;

    if (readfds) FD_ZERO(readfds);
    if (writefds) FD_ZERO(writefds);
    if (exceptfds) FD_ZERO(exceptfds);

    for (i = 0; i < poll_nfds; i++) {
        if (fds[i].revents & POLLIN) {
            if (readfds) FD_SET(fds[i].fd, readfds);
            ready_count++;
        }
        if (fds[i].revents & POLLOUT) {
            if (writefds) FD_SET(fds[i].fd, writefds);
            ready_count++;
        }
        if (fds[i].revents & POLLPRI) {
            if (exceptfds) FD_SET(fds[i].fd, exceptfds);
            ready_count++;
        }
    }

    return ready_count;
}
