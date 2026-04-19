#ifndef PREX_GLUE_H
#define PREX_GLUE_H

#include <sys/types.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <signal.h>
#include <unistd.h>
#include <sys/fcntl.h>
#include <stdio.h>
#include <paths.h>

#ifndef L_SET
#define L_SET SEEK_SET
#endif
#ifndef L_INCR
#define L_INCR SEEK_CUR
#endif
#ifndef L_XTND
#define L_XTND SEEK_END
#endif

int utimes(const char *path, const struct timeval *times);
int sigblock(int mask);
int sigsetmask(int mask);
int select(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, struct timeval *timeout);

struct rusage; /* forward declaration */
pid_t wait3(int *status, int options, struct rusage *rusage);

#endif /* PREX_GLUE_H */
