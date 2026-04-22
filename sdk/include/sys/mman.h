#ifndef _SYS_MMAN_H_
#define _SYS_MMAN_H_

#include <sys/types.h>

#define PROT_READ   0x01
#define PROT_WRITE  0x02
#define PROT_EXEC   0x04
#define PROT_NONE   0x00

#define MAP_SHARED  0x01
#define MAP_PRIVATE 0x02
#define MAP_FIXED   0x10
#define MAP_ANON    0x20

#define MAP_FAILED  ((void *)-1)

/* Stubs for Prex */
void *mmap(void *, size_t, int, int, int, off_t);
int munmap(void *, size_t);
int mprotect(void *, size_t, int);

#endif
