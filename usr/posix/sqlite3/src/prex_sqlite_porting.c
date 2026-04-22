#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>

int chmod(const char *path, mode_t mode)
{
    (void)path;
    (void)mode;
    return 0;
}

int fchmod(int fd, mode_t mode)
{
    (void)fd;
    (void)mode;
    return 0;
}

int fchown(int fd, uid_t owner, gid_t group)
{
    (void)fd;
    (void)owner;
    (void)group;
    return 0;
}

int utimes(const char *path, const struct timeval *tvp)
{
    (void)path;
    (void)tvp;
    return 0;
}

int system(const char *command)
{
    (void)command;
    return 0;
}

int raise(int sig)
{
    (void)sig;
    return 0;
}

double strtod(const char *nptr, char **endptr)
{
    if (endptr) *endptr = (char *)nptr;
    return 0.0;
}

double ceil(double x)
{
    int i = (int)x;
    return (double)(x > i ? i + 1 : i);
}

/* Prex has timer_sleep but no usleep in libc.a */
int timer_sleep(u_long, u_long*);
void usleep(unsigned int usec)
{
    u_long remain;
    timer_sleep(usec / 1000, &remain);
}

/* Fallback to long versions if long long versions are missing */
long long strtoq(const char *nptr, char **endptr, int base)
{
    return (long long)strtol(nptr, endptr, base);
}

unsigned long long strtouq(const char *nptr, char **endptr, int base)
{
    return (unsigned long long)strtoul(nptr, endptr, base);
}

/* Prex mmap stubs */
void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset)
{
    (void)addr;
    (void)length;
    (void)prot;
    (void)flags;
    (void)fd;
    (void)offset;
    errno = ENOSYS;
    return (void *)-1;
}

int munmap(void *addr, size_t length)
{
    (void)addr;
    (void)length;
    errno = ENOSYS;
    return -1;
}

int mprotect(void *addr, size_t length, int prot)
{
    (void)addr;
    (void)length;
    (void)prot;
    errno = ENOSYS;
    return -1;
}
