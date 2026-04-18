#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <sys/prex.h>
#include <sys/posix.h>
#include <ipc/fs.h>
#include <errno.h>
#include <stdio.h>

long long strtoll(const char *nptr, char **endptr, int base) {
    return (long long)strtol(nptr, endptr, base);
}

unsigned long long strtoull(const char *nptr, char **endptr, int base) {
    return (unsigned long long)strtoul(nptr, endptr, base);
}

float strtof(const char *nptr, char **endptr) { return (float)atof(nptr); }
double strtod(const char *nptr, char **endptr) { return atof(nptr); }
long double strtold(const char *nptr, char **endptr) { return (long double)atof(nptr); }

long double ldexpl(long double d, int exp) {
    while (exp > 0) { d *= 2.0; exp--; }
    while (exp < 0) { d /= 2.0; exp++; }
    return d;
}

extern object_t __fs_obj;
extern int __posix_call(object_t obj, void *msg, size_t size, int mock);

static ssize_t real_read(int fd, void* buf, size_t len)
{
    struct io_msg m;
    m.hdr.code = FS_READ;
    m.fd = fd;
    m.buf = buf;
    m.size = len;
    if (__posix_call(__fs_obj, &m, sizeof(m), 0) != 0)
        return -1;
    return (ssize_t)m.size;
}

static ssize_t real_write(int fd, const void* buf, size_t len)
{
    struct io_msg m;
    m.hdr.code = FS_WRITE;
    m.fd = fd;
    m.buf = (void *)buf;
    m.size = len;
    if (__posix_call(__fs_obj, &m, sizeof(m), 0) != 0)
        return -1;
    return (ssize_t)m.size;
}

#define IO_BUF_SIZE 4096
static char io_buf[IO_BUF_SIZE] __attribute__((aligned(4096)));

ssize_t read(int fd, void *buf, size_t count) {
    size_t total = 0;
    char *p = (char *)buf;
    while (count > 0) {
        size_t chunk = (count > IO_BUF_SIZE) ? IO_BUF_SIZE : count;
        ssize_t n = real_read(fd, io_buf, chunk);
        if (n < 0) return (total > 0) ? (ssize_t)total : -1;
        if (n == 0) return (ssize_t)total;
        memcpy(p, io_buf, n);
        total += n;
        p += n;
        count -= n;
    }
    return (ssize_t)total;
}

ssize_t write(int fd, const void *buf, size_t count) {
    size_t total = 0;
    const char *p = (const char *)buf;
    while (count > 0) {
        size_t chunk = (count > IO_BUF_SIZE) ? IO_BUF_SIZE : count;
        memcpy(io_buf, p, chunk);
        ssize_t n = real_write(fd, io_buf, chunk);
        if (n < 0) return (total > 0) ? (ssize_t)total : -1;
        if (n == 0) return (ssize_t)total;
        total += n;
        p += n;
        count -= n;
    }
    return (ssize_t)total;
}

void *dlopen(const char *filename, int flag) { return NULL; }
void dlclose(void *p) {}
void *dlsym(void *handle, const char *symbol) { return NULL; }
const char *dlerror(void) { return NULL; }
int tcc_run(void *s, int argc, char **argv) { return -1; }
void tcc_run_free(void *s) {}
