/*
 * _systrap.S - system call stubs for RISC-V
 */

#include <machine/systrap.h>
#include <sys/syscall.h>

/* 
 * The FOR_EACH_SYSCALL macro passes (name, narg) to the DO macro.
 * We need to use SYS_##name to get the actual syscall ID.
 */
#define _DO_STUB(name, narg) SYSCALL_STUB(name, SYS_##name) ;

FOR_EACH_SYSCALL(_DO_STUB)

.section .note.GNU-stack,"",%progbits
