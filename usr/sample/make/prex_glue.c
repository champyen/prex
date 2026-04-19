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

#include <sys/types.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include <errno.h>
#include <math.h>

int utimes(const char *path, const struct timeval *times) {
    /* Stub: just return success for now */
    return 0;
}

int sigblock(int mask) {
    sigset_t oldset, newset;
    newset = (sigset_t)mask;
    if (sigprocmask(SIG_BLOCK, &newset, &oldset) < 0)
        return -1;
    return (int)oldset;
}

int sigsetmask(int mask) {
    sigset_t oldset, newset;
    newset = (sigset_t)mask;
    if (sigprocmask(SIG_SETMASK, &newset, &oldset) < 0)
        return -1;
    return (int)oldset;
}

int select(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, struct timeval *timeout) {
    int i, count = 0;
    if (readfds) {
        for (i = 0; i < nfds; i++) {
            if (FD_ISSET(i, readfds)) {
                count++;
            }
        }
    }
    /* Note: this might cause blocking if pipes are empty. 
       But Prex doesn't have a real select. */
    return count;
}

pid_t wait3(int *status, int options, struct rusage *rusage) {
    return waitpid(-1, status, options);
}

/* Missing libc functions */
float strtof(const char *nptr, char **endptr) { return (float)atof(nptr); }
double strtod(const char *nptr, char **endptr) { return atof(nptr); }
long double strtold(const char *nptr, char **endptr) { return (long double)atof(nptr); }

long double ldexpl(long double d, int exp) {
    while (exp > 0) { d *= 2.0; exp--; }
    while (exp < 0) { d /= 2.0; exp++; }
    return d;
}
