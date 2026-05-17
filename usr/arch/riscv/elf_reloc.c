/*
 * elf_reloc.c - RISC-V ELF relocation support (User-space)
 */

#include <sys/param.h>
#include <sys/elf.h>

#define R_RISCV_NONE 0
#define R_RISCV_32 1
#define R_RISCV_BRANCH 16
#define R_RISCV_JAL 17
#define R_RISCV_CALL 18
#define R_RISCV_CALL_PLT 19
#define R_RISCV_PCREL_HI20 23
#define R_RISCV_PCREL_LO12_I 24
#define R_RISCV_PCREL_LO12_S 25
#define R_RISCV_HI20 26
#define R_RISCV_LO12_I 27
#define R_RISCV_LO12_S 28
#define R_RISCV_RELAX 51
#define R_RISCV_ALIGN 52

/* 
 * A small LUT to store the calculated offset of HI20 relocations,
 * so they can be retrieved by the following LO12 relocations.
 */
#define MAX_HI20 256
static struct {
    Elf32_Addr addr;
    int32_t offset;
} hi20_lut[MAX_HI20];
static int hi20_idx = 0;

static void add_hi20(Elf32_Addr addr, int32_t offset)
{
    hi20_lut[hi20_idx].addr = addr;
    hi20_lut[hi20_idx].offset = offset;
    hi20_idx = (hi20_idx + 1) % MAX_HI20;
}

static int32_t find_hi20(Elf32_Addr addr)
{
    int i;
    for (i = 0; i < MAX_HI20; i++) {
        if (hi20_lut[i].addr == addr)
            return hi20_lut[i].offset;
    }
    return 0;
}

int relocate_rela(Elf32_Rela* rela, Elf32_Addr sym_val, char* target_sect)
{
    Elf32_Addr* where;
    Elf32_Addr val;
    int32_t offset;
    uint32_t hi, lo;
    int type = (int)ELF32_R_TYPE(rela->r_info);

    where = (Elf32_Addr*)(target_sect + rela->r_offset);
    val = sym_val + rela->r_addend;

    switch (type) {
    case R_RISCV_NONE:
    case R_RISCV_RELAX:
    case R_RISCV_ALIGN:
        break;

    case R_RISCV_32:
        *where = val;
        break;

    case R_RISCV_HI20:
        offset = (int32_t)val;
        hi = (uint32_t)(offset + 0x800) >> 12;
        *where = (*where & 0x00000fff) | (hi << 12);
        break;

    case R_RISCV_LO12_I:
        offset = (int32_t)val;
        lo = (uint32_t)offset & 0xfff;
        *where = (*where & 0x000fffff) | (lo << 20);
        break;

    case R_RISCV_LO12_S:
        offset = (int32_t)val;
        lo = (uint32_t)offset & 0xfff;
        *where = (*where & 0x01fff07f) | ((lo & 0xfe0) << 20) | ((lo & 0x01f) << 7);
        break;

    case R_RISCV_PCREL_HI20:
        offset = (int32_t)val - (int32_t)where;
        hi = (uint32_t)(offset + 0x800) >> 12;
        *where = (*where & 0x00000fff) | (hi << 12);
        add_hi20((Elf32_Addr)where, offset);
        break;

    case R_RISCV_PCREL_LO12_I:
        offset = find_hi20(sym_val);
        lo = (uint32_t)offset & 0xfff;
        *where = (*where & 0x000fffff) | (lo << 20);
        break;

    case R_RISCV_PCREL_LO12_S:
        offset = find_hi20(sym_val);
        lo = (uint32_t)offset & 0xfff;
        *where = (*where & 0x01fff07f) | ((lo & 0xfe0) << 20) | ((lo & 0x01f) << 7);
        break;

    case R_RISCV_CALL:
    case R_RISCV_CALL_PLT:
        offset = (int32_t)val - (int32_t)where;
        hi = (uint32_t)(offset + 0x800) >> 12;
        lo = (uint32_t)offset & 0xfff;
        *where = (*where & 0x00000fff) | (hi << 12);
        *(where + 1) = (*(where + 1) & 0x000fffff) | (lo << 20);
        break;

    case R_RISCV_BRANCH:
        offset = (int32_t)val - (int32_t)where;
        *where = (*where & 0x01fff07f) | 
                 (((offset >> 12) & 0x01) << 31) |
                 (((offset >> 5) & 0x3f) << 25) |
                 (((offset >> 1) & 0x0f) << 8) |
                 (((offset >> 11) & 0x01) << 7);
        break;

    case R_RISCV_JAL:
        offset = (int32_t)val - (int32_t)where;
        *where = (*where & 0x0000007f) | 
                 (((offset >> 20) & 0x01) << 31) |
                 (((offset >> 1) & 0x3ff) << 21) |
                 (((offset >> 11) & 0x01) << 20) |
                 (((offset >> 12) & 0xff) << 12);
        break;

    default:
        return -1;
    }
    return 0;
}

int relocate_rel(Elf32_Rel* rel, Elf32_Addr sym_val, char* target_sect)
{
    return -1;
}
