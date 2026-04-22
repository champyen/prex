#ifndef PREX_SQLITE_PORTING_H
#define PREX_SQLITE_PORTING_H

#include <stdint.h>
#include <sys/types.h>

/* Redefine timespec BEFORE including anything that might use it */
#define timespec _prex_timespec
#include <sys/time.h>
#undef timespec

struct timespec {
    time_t tv_sec;
    long tv_nsec;
};
#define ts_sec tv_sec
#define ts_nsec tv_nsec

#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <math.h>

#ifndef UINT64_C
#define UINT64_C(c) c ## ull
#endif

#ifndef INT64_C
#define INT64_C(c) c ## ll
#endif

#ifndef INFINITY
#define INFINITY (__builtin_inff())
#endif

#ifndef NAN
#define NAN (__builtin_nanf(""))
#endif

#ifndef ENOLCK
#define ENOLCK 41
#endif

/* Prex libc has strtoq/strtouq but may need declaration */
long long strtoq(const char *, char **, int);
unsigned long long strtouq(const char *, char **, int);
void usleep(unsigned int);

#ifndef strtoll
#define strtoll strtoq
#endif

#ifndef strtoull
#define strtoull strtouq
#endif

static inline int symlink(const char *path1, const char *path2)
{
    (void)path1;
    (void)path2;
    errno = ENOSYS;
    return -1;
}

/* rusage stubs for shell.c */
struct rusage {
    struct timeval ru_utime;
    struct timeval ru_stime;
};
#ifndef RUSAGE_SELF
#define RUSAGE_SELF 0
#endif
static inline int getrusage(int who, struct rusage *usage)
{
    (void)who;
    if (usage) {
        usage->ru_utime.tv_sec = 0;
        usage->ru_utime.tv_usec = 0;
        usage->ru_stime.tv_sec = 0;
        usage->ru_stime.tv_usec = 0;
    }
    return 0;
}

/* Prex missing declarations */
struct timeval;
int chmod(const char *path, mode_t mode);
int fchmod(int fd, mode_t mode);
int fchown(int fd, uid_t owner, gid_t group);
int utimes(const char *path, const struct timeval *tvp);
int system(const char *command);
int raise(int sig);
double strtod(const char *nptr, char **endptr);
double ceil(double x);

static inline int nanosleep(const struct timespec *req, struct timespec *rem)
{
    if (req) {
        usleep(req->tv_sec * 1000000 + req->tv_nsec / 1000);
    }
    return 0;
}

/* SQLite configuration */
#define SQLITE_OS_OTHER 0
#define SQLITE_OS_UNIX 1
#define SQLITE_OS_WIN 0
#define SQLITE_OS_KV 0

#define SQLITE_THREADSAFE 0
#define SQLITE_MUTEX_NOOP 1
#define SQLITE_OMIT_WAL 1
#define SQLITE_OMIT_LOAD_EXTENSION 1
#define SQLITE_OMIT_POPEN 1

#define SQLITE_BYTEORDER 1234

/* Bypassing pwd.h in shell.c without triggering vxWorks.h in sqlite3.c */
#define SQLITE_WASI 1

#endif /* PREX_SQLITE_PORTING_H */
