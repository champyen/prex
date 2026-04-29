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
#include <sys/elf.h>
#include <sys/syslog.h>
#include <sys/prex.h>
#include <stdint.h>

#ifndef R_ARM_THM_MOVW_ABS_NC
#define R_ARM_THM_MOVW_ABS_NC 47
#endif
#ifndef R_ARM_THM_MOVT_ABS
#define R_ARM_THM_MOVT_ABS 48
#endif

int relocate_rel(Elf32_Rel* rel, Elf32_Addr sym_val, char* target_sect)
{
    Elf32_Addr *where, tmp;
    Elf32_Sword addend;

    where = (Elf32_Addr*)(target_sect + rel->r_offset);

    switch (ELF32_R_TYPE(rel->r_info)) {
    case R_ARM_NONE:
        break;
    case R_ARM_ABS32:
        *where += (Elf32_Addr)sym_val;
        break;
    case R_ARM_MOVW_ABS_NC:
        addend = *where;
        addend = ((addend & 0xf0000) >> 4) | (addend & 0xfff);
        tmp = (Elf32_Addr)sym_val + addend;
        *where = (*where & 0xfff0f000) | ((tmp & 0xf000) << 4) | (tmp & 0xfff);
        break;
    case R_ARM_MOVT_ABS:
        addend = *where;
        addend = ((addend & 0xf0000) >> 4) | (addend & 0xfff);
        tmp = (Elf32_Addr)sym_val + addend;
        tmp >>= 16;
        *where = (*where & 0xfff0f000) | ((tmp & 0xf000) << 4) | (tmp & 0xfff);
        break;
    case R_ARM_PC24:
    case R_ARM_PLT32:
    case R_ARM_CALL:
    case R_ARM_JUMP24:
        addend = *where & 0x00ffffff;
        if (addend & 0x00800000)
            addend |= 0xff000000;
        tmp = sym_val - (Elf32_Addr)where + (addend << 2);
        tmp >>= 2;
        *where = (*where & 0xff000000) | (tmp & 0x00ffffff);
        break;
    case R_ARM_THM_CALL:
    case R_ARM_THM_JUMP24:
        /*
         * R_ARM_THM_CALL: ((S + A) | T) - P
         * S=sym_val, A=addend, P=where
         */
        {
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
            tmp = sym_val - (Elf32_Addr)where + addend;

            if ((sym_val & 1) == 0 && ELF32_R_TYPE(rel->r_info) == R_ARM_THM_CALL) {
                /* Interworking: convert BL to BLX */
                tmp = (tmp + 2) & ~3; /* BLX immediate must be 4-byte aligned */
                w[1] = (uint16_t)((w[1] & 0xefff)); /* Clear bit 12 to make it BLX */
                lower = w[1];
            }

            s = (tmp >> 24) & 1;
            i1 = (tmp >> 23) & 1;
            i2 = (tmp >> 22) & 1;
            j1 = !(i1 ^ s);
            j2 = !(i2 ^ s);
            w[0] = (uint16_t)((upper & 0xf800) | (s << 10) | ((tmp >> 12) & 0x3ff));
            w[1] = (uint16_t)((lower & 0xd000) | (j1 << 13) | (j2 << 11) | ((tmp >> 1) & 0x7ff));
        }
        break;
    case R_ARM_THM_MOVW_ABS_NC:
        {
            uint16_t* w = (uint16_t*)where;
            uint32_t upper = w[0];
            uint32_t lower = w[1];
            addend = ((upper & 0x0400) << 1) | ((upper & 0x000f) << 12) |
                     ((lower & 0x7000) >> 4) | (lower & 0x00ff);
            tmp = sym_val + addend;
            w[0] = (uint16_t)((upper & 0xfbf0) | ((tmp & 0x0800) >> 1) | ((tmp & 0xf000) >> 12));
            w[1] = (uint16_t)((lower & 0x8f00) | ((tmp & 0x0700) << 4) | (tmp & 0x00ff));
        }
        break;
    case R_ARM_THM_MOVT_ABS:
        {
            uint16_t* w = (uint16_t*)where;
            uint32_t upper = w[0];
            uint32_t lower = w[1];
            addend = ((upper & 0x0400) << 1) | ((upper & 0x000f) << 12) |
                     ((lower & 0x7000) >> 4) | (lower & 0x00ff);
            tmp = (sym_val + addend) >> 16;
            w[0] = (uint16_t)((upper & 0xfbf0) | ((tmp & 0x0800) >> 1) | ((tmp & 0xf000) >> 12));
            w[1] = (uint16_t)((lower & 0x8f00) | ((tmp & 0x0700) << 4) | (tmp & 0x00ff));
        }
        break;
    case R_ARM_V4BX:
        /* nothing to do: bx instruction is supported */
        break;
    case R_ARM_PREL31:
        {
            int32_t addend = (((int32_t)*where) << 1) >> 1;
            uint32_t val = (sym_val + addend - (Elf32_Addr)where) & 0x7fffffff;
            *where = (*where & 0x80000000) | val;
        }
        break;
    default:
#ifdef DEBUG
        syslog(LOG_ERR, "relocation fail type=%d\n", ELF32_R_TYPE(rel->r_info));
#endif
        return -1;
    }
    return 0;
}

int relocate_rela(Elf32_Rela* rela, Elf32_Addr sym_val, char* target_sec)
{
    /* printf("Invalid relocation type\n"); */
    return -1;
}
