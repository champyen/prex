/*
 * thread_load.c - user space wrapper for thread_setup system call
 */
#include <sys/prex.h>

int thread_load(thread_t t, void (*entry)(void), void* stack)
{
    void* gp = NULL;

#if defined(__arm__) && defined(CONFIG_ARMV8M)
    /* Get GOT base from R9 */
    __asm__ volatile("mov %0, r9" : "=r"(gp));
#endif

    return thread_setup(t, entry, stack, gp);
}
