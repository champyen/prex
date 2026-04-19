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
