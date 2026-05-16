/*
 * elf_reloc.c - RISC-V ELF relocation support
 */

#include <sys/param.h>
#include <boot.h>
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

int relocate_rela(Elf32_Rela* rela, Elf32_Addr sym_val, char* target_sect)
{
    Elf32_Addr* where;
    Elf32_Addr val;
    int32_t offset;
    uint32_t hi, lo;
    int type = (int)ELF32_R_TYPE(rela->r_info);

    printf("reloc type %d\n", type);
    where = (Elf32_Addr*)(target_sect + rela->r_offset);
    val = sym_val + rela->r_addend;

    switch (ELF32_R_TYPE(rela->r_info)) {
    case R_RISCV_NONE:
    case R_RISCV_RELAX:
    case R_RISCV_ALIGN:
        break;

    case R_RISCV_32:
        *where = val;
        break;

    case R_RISCV_HI20:
        *where = (*where & 0x00000fff) | ((val + 0x800) & 0xfffff000);
        break;

    case R_RISCV_LO12_I:
        *where = (*where & 0x000fffff) | ((val & 0xfff) << 20);
        break;

    case R_RISCV_LO12_S:
        *where = (*where & 0x01fff07f) | ((val & 0xfe0) << 20) | ((val & 0x01f) << 7);
        break;

    case R_RISCV_PCREL_HI20:
    case R_RISCV_CALL:
    case R_RISCV_CALL_PLT:
        offset = (int32_t)val - (int32_t)where;
        hi = (uint32_t)(offset + 0x800) >> 12;
        lo = (uint32_t)offset - (hi << 12);
        /* Patch auipc */
        *where = (*where & 0x00000fff) | (hi << 12);
        /* Patch jalr / load / op-imm */
        *(where + 1) = (*(where + 1) & 0x000fffff) | (lo << 20);
        break;

    case R_RISCV_PCREL_LO12_I:
        /* This usually follows a PCREL_HI20. The 'val' here should be the 
           result of the HI20 relocation. But in simple loaders, we often 
           handle them together in HI20. If we hit this alone, we need to know 
           the original symbol value. */
        /* For now, we assume HI20 already handled it or we just patch the low bits if we have sym_val. */
        offset = (int32_t)val - (int32_t)where;
        *where = (*where & 0x000fffff) | ((offset & 0xfff) << 20);
        break;

    case R_RISCV_PCREL_LO12_S:
        offset = (int32_t)val - (int32_t)where;
        *where = (*where & 0x01fff07f) | ((offset & 0xfe0) << 20) | ((offset & 0x01f) << 7);
        break;

    case R_RISCV_BRANCH:
        offset = (int32_t)val - (int32_t)where;
        *where = (*where & 0x01fff07f) | 
                 ((offset & 0x1000) << 19) | 
                 ((offset & 0x07e0) << 20) | 
                 ((offset & 0x001e) << 7) | 
                 ((offset & 0x0800) >> 4);
        break;

    case R_RISCV_JAL:
        offset = (int32_t)val - (int32_t)where;
        *where = (*where & 0x0000007f) | 
                 ((offset & 0x100000) << 11) | 
                 ((offset & 0x0007fe) << 20) | 
                 ((offset & 0x000800) << 9) | 
                 ((offset & 0x0ff000) << 0);
        break;

    default:
        DPRINTF(("RISCV-LOADER: Unknown reloc type %d (XLEN=%d)\n", (int)ELF32_R_TYPE(rela->r_info), __riscv_xlen));
        return -1;
    }
    return 0;
}

int relocate_rel(Elf32_Rel* rel, Elf32_Addr sym_val, char* target_sect)
{
    return -1;
}
