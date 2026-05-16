/*-
 * Copyright (c) 2007, Kohsuke Ohtani
 * All rights reserved.
 * Copyright (c) 2026, Champ Yen <champ.yen@gmail.com>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * ...
 */

#ifndef _RISCV_ELF_H
#define _RISCV_ELF_H

/*
 * Relocation type
 */
#define R_RISCV_NONE 0
#define R_RISCV_32 1
#define R_RISCV_64 2
#define R_RISCV_RELATIVE 3
#define R_RISCV_COPY 4
#define R_RISCV_JUMP_SLOT 5
#define R_RISCV_BRANCH 16
#define R_RISCV_JAL 17
#define R_RISCV_CALL 18
#define R_RISCV_CALL_PLT 19
#define R_RISCV_GOT_HI20 20
#define R_RISCV_PCREL_HI20 23
#define R_RISCV_PCREL_LO12_I 24
#define R_RISCV_PCREL_LO12_S 25
#define R_RISCV_HI20 26
#define R_RISCV_LO12_I 27
#define R_RISCV_LO12_S 28
#define R_RISCV_RELAX 51
#define R_RISCV_ALIGN 52

#endif /* !_RISCV_ELF_H */
