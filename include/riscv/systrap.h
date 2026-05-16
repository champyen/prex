/*-
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * ...
 */

#ifndef _RISCV_SYSTRAP_H
#define _RISCV_SYSTRAP_H

#ifdef __ASSEMBLY__

#define SYSCALL_STUB(name, id) \
    .global name; \
    .type name, @function; \
    name: \
        li a7, id; \
        ecall; \
        ret

#else /* !__ASSEMBLY__ */

#define __SYSCALL_BODY(id)                                                                                             \
    "li a7, " #id ";\n"                                                                                                \
    "ecall;\n"                                                                                                         \
    "ret"

#define SYSCALL_STUB(name, id)                                                                                         \
    void name(void);                                                                                                   \
    __asm__(                                                                                                           \
        ".global " #name ";\n"                                                                                         \
        ".type " #name ", @function;\n"                                                                                \
        #name ":\n"                                                                                                    \
        __SYSCALL_BODY(id)                                                                                             \
    )

#endif /* !__ASSEMBLY__ */

#endif /* _RISCV_SYSTRAP_H */
