#ifndef PREX_UTIME_H
#define PREX_UTIME_H

#include <sys/types.h>

struct utimbuf {
    time_t actime;
    time_t modtime;
};

static inline int utime(const char *filename, const struct utimbuf *times)
{
    (void)filename;
    (void)times;
    return 0;
}

#endif
