/*-
 * Copyright (c) 2006, Kohsuke Ohtani
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

#include <sys/param.h>
#include <sys/elf.h>
#include <boot.h>

int relocate_rel(Elf32_Rel* rel, Elf32_Addr sym_val, char* target_sect)
{
    Elf32_Addr *where, tmp;
    Elf32_Sword addend;

    where = (Elf32_Addr*)(target_sect + rel->r_offset);
    switch (ELF32_R_TYPE(rel->r_info)) {
    case R_ARM_NONE:
        break;
    case R_ARM_ABS32:
        *where += (vaddr_t)ptokv(sym_val);
        break;
    case R_ARM_MOVW_ABS_NC:
        addend = *where;
        addend = ((addend & 0xf0000) >> 4) | (addend & 0xfff);
        tmp = (vaddr_t)ptokv(sym_val) + addend;
        *where = (*where & 0xfff0f000) | ((tmp & 0xf000) << 4) | (tmp & 0xfff);
        break;
    case R_ARM_MOVT_ABS:
        addend = *where;
        addend = ((addend & 0xf0000) >> 4) | (addend & 0xfff);
        tmp = (vaddr_t)ptokv(sym_val) + addend;
        tmp >>= 16;
        *where = (*where & 0xfff0f000) | ((tmp & 0xf000) << 4) | (tmp & 0xfff);
        break;
    case R_ARM_THM_MOVW_ABS_NC:
    case R_ARM_THM_MOVT_ABS: {
        uint16_t upper_insn = *(uint16_t*)where;
        uint16_t lower_insn = *(uint16_t*)((char*)where + 2);

        addend = ((upper_insn & 0x000f) << 12) | ((upper_insn & 0x0400) << 1) | ((lower_insn & 0x7000) >> 4) |
                 (lower_insn & 0x00ff);

        tmp = (vaddr_t)ptokv(sym_val) + addend;

        if (ELF32_R_TYPE(rel->r_info) == R_ARM_THM_MOVT_ABS)
            tmp >>= 16;

        *(uint16_t*)where = (uint16_t)((upper_insn & 0xfbf0) | ((tmp & 0xf000) >> 12) | ((tmp & 0x0800) >> 1));
        *(uint16_t*)((char*)where + 2) = (uint16_t)((lower_insn & 0x8f00) | ((tmp & 0x0700) << 4) | (tmp & 0x00ff));
        break;
    }
    case R_ARM_THM_CALL:
    case R_ARM_THM_JUMP24: {
        uint16_t* w = (uint16_t*)where;
        uint32_t upper = w[0];
        uint32_t lower = w[1];
        uint32_t s = (upper >> 10) & 1;
        uint32_t j1 = (lower >> 13) & 1;
        uint32_t j2 = (lower >> 11) & 1;
        uint32_t i1 = !(j1 ^ s);
        uint32_t i2 = !(j2 ^ s);
        addend = (s << 24) | (i1 << 23) | (i2 << 22) | ((upper & 0x3ff) << 12) | ((lower & 0x7ff) << 1);
        if (addend & 0x01000000)
            addend |= 0xfe000000;

        if (sym_val & 1) {
            /* BL to Thumb */
            tmp = (vaddr_t)sym_val - (vaddr_t)where + addend;
            s = (tmp >> 24) & 1;
            i1 = (tmp >> 23) & 1;
            i2 = (tmp >> 22) & 1;
            j1 = !(i1 ^ s);
            j2 = !(i2 ^ s);
            w[0] = (uint16_t)((upper & 0xf800) | (s << 10) | ((tmp >> 12) & 0x3ff));
            w[1] = (uint16_t)((lower & 0xd000) | (j1 << 13) | (1 << 12) | (j2 << 11) | ((tmp >> 1) & 0x7ff));
        } else {
            /* BLX to ARM */
            tmp = (vaddr_t)(sym_val & ~3) - ((vaddr_t)where & ~3) + addend;
            s = (tmp >> 24) & 1;
            i1 = (tmp >> 23) & 1;
            i2 = (tmp >> 22) & 1;
            j1 = !(i1 ^ s);
            j2 = !(i2 ^ s);
            w[0] = (uint16_t)((upper & 0xf800) | (s << 10) | ((tmp >> 12) & 0x3ff));
            w[1] = (uint16_t)((lower & 0xd000) | (j1 << 13) | (0 << 12) | (j2 << 11) | ((tmp >> 1) & 0x7ff));
        }
        break;
    }
    case R_ARM_PC24:
case R_ARM_PLT32:
case R_ARM_CALL:
case R_ARM_JUMP24:
    addend = *where & 0x00ffffff;
    if (addend & 0x00800000)
        addend |= 0xff000000;
    tmp = (vaddr_t)sym_val - (vaddr_t)where + (addend << 2);
    tmp >>= 2;
    *where = (*where & 0xff000000) | (tmp & 0x00ffffff);
    break;
case R_ARM_V4BX:
    break;
case R_ARM_PREL31:
    {
        int32_t addend = (((int32_t)*where) << 1) >> 1;
        uint32_t val = ((vaddr_t)ptokv(sym_val) + addend - (vaddr_t)where) & 0x7fffffff;
        *where = (*where & 0x80000000) | val;
    }
    break;
default:
    panic("relocation fail");
    return -1;
}    return 0;
}

int relocate_rela(Elf32_Rela* rela, Elf32_Addr sym_val, char* target_sec)
{

    panic("invalid relocation type");
    return -1;
}
