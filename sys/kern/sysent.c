/*-
 * Copyright (c) 2005-2009 Kohsuke Ohtani
 * Copyright (c) 2026 Champ Yen <champ.yen@gmail.com>
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

/*
 * sysent.c - system call switch table.
 */

#include <kernel.h>
#include <thread.h>
#include <timer.h>
#include <vm.h>
#include <task.h>
#include <exception.h>
#include <ipc.h>
#include <device.h>
#include <sync.h>
#include <system.h>

#include <sys/syscall.h>

typedef register_t (*sysfn_t)(register_t, register_t, register_t, register_t);

#ifdef DEBUG
static void strace_entry(register_t, register_t, register_t, register_t, register_t);
static void strace_return(register_t, register_t);
#endif

struct sysent
{
#ifdef DEBUG
    int sy_narg;   /* number of arguments */
    char* sy_name; /* name string */
#endif
    sysfn_t sy_call; /* handler */
};

/*
 * Sysent initialization macros.
 */
#ifdef DEBUG
#define _SYSENT_DEF(name, narg) { narg, #name, (sysfn_t)name },
#else
#define _SYSENT_DEF(name, narg) { (sysfn_t)name },
#endif

/*
 * This table is the switch used to transfer to the
 * appropriate routine for processing a system call.
 */
static const struct sysent sysent[] = {
    FOR_EACH_SYSCALL(_SYSENT_DEF)
};
#undef _SYSENT_DEF

#define NSYSCALL (int)(sizeof(sysent) / sizeof(sysent[0]))

/*
 * System call dispatcher.
 */
register_t syscall_handler(register_t a1, register_t a2, register_t a3, register_t a4, register_t id)
{
    register_t retval = EINVAL;
    const struct sysent* callp;

#ifdef DEBUG
    strace_entry(a1, a2, a3, a4, id);
#endif

    if (id < NSYSCALL) {
        callp = &sysent[id];
        retval = (*callp->sy_call)(a1, a2, a3, a4);
    }

#ifdef DEBUG
    strace_return(retval, id);
#endif
    return retval;
}

#ifdef DEBUG
/*
 * Show syscall info if the task is being traced.
 */
static void strace_entry(register_t a1, register_t a2, register_t a3, register_t a4, register_t id)
{
    const struct sysent* callp;

    if (curtask->flags & TF_TRACE) {
        if (id >= NSYSCALL) {
            printf("%s: OUT OF RANGE (%d)\n", curtask->name, id);
            return;
        }

        callp = &sysent[id];

        printf("%s: %s(", curtask->name, callp->sy_name);
        switch (callp->sy_narg) {
        case 0:
            printf(")\n");
            break;
        case 1:
            printf("0x%08x)\n", a1);
            break;
        case 2:
            printf("0x%08x, 0x%08x)\n", a1, a2);
            break;
        case 3:
            printf("0x%08x, 0x%08x, 0x%08x)\n", a1, a2, a3);
            break;
        case 4:
            printf("0x%08x, 0x%08x, 0x%08x, 0x%08x)\n", a1, a2, a3, a4);
            break;
        }
    }
}

/*
 * Show status if syscall is failed.
 *
 * We ignore the return code for the function which does
 * not have any arguments, although timer_waitperiod()
 * has valid return code...
 */
static void strace_return(register_t retval, register_t id)
{
    const struct sysent* callp;

    if (curtask->flags & TF_TRACE) {
        if (id >= NSYSCALL)
            return;
        callp = &sysent[id];
        if (callp->sy_narg != 0 && retval != 0)
            printf("%s: !!! %s() = 0x%08x\n", curtask->name, callp->sy_name, retval);
    }
}
#endif /* !DEBUG */
