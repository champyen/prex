/*
 * elf_reloc.c - RISC-V ELF relocation support
 */

#include <sys/param.h>
#include <boot.h>
#include <sys/elf.h>

#define R_RISCV_NONE            0
#define R_RISCV_32              1
#define R_RISCV_64              2
#define R_RISCV_RELATIVE        3
#define R_RISCV_COPY            4
#define R_RISCV_JUMP_SLOT       5
#define R_RISCV_BRANCH          16
#define R_RISCV_JAL             17
#define R_RISCV_CALL            18
#define R_RISCV_CALL_PLT        19
#define R_RISCV_GOT_HI20        20
#define R_RISCV_PCREL_HI20      23
#define R_RISCV_PCREL_LO12_I    24
#define R_RISCV_PCREL_LO12_S    25
#define R_RISCV_HI20            26
#define R_RISCV_LO12_I          27
#define R_RISCV_LO12_S          28
#define R_RISCV_TPREL_HI20      29
#define R_RISCV_TPREL_LO12_I    30
#define R_RISCV_TPREL_LO12_S    31
#define R_RISCV_TPREL_ADD       32
#define R_RISCV_ADD8            33
#define R_RISCV_ADD16           34
#define R_RISCV_ADD32           35
#define R_RISCV_ADD64           36
#define R_RISCV_SUB8            37
#define R_RISCV_SUB16           38
#define R_RISCV_SUB32           39
#define R_RISCV_SUB64           40
#define R_RISCV_GNU_VTINHERIT   41
#define R_RISCV_GNU_VTENTRY     42
#define R_RISCV_ALIGN           43
#define R_RISCV_RVC_BRANCH      44
#define R_RISCV_RVC_JUMP        45
#define R_RISCV_RVC_LUI         46
#define R_RISCV_GPREL_I         47
#define R_RISCV_GPREL_S         48
#define R_RISCV_TPREL_I         49
#define R_RISCV_TPREL_S         50
#define R_RISCV_RELAX           51
#define R_RISCV_SUB6            52
#define R_RISCV_SET6            53
#define R_RISCV_SET8            54
#define R_RISCV_SET16           55
#define R_RISCV_SET32           56
#define R_RISCV_32_PCREL        57

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
        if (hi20_lut[i].addr == addr) {
            int32_t off = hi20_lut[i].offset;
            hi20_lut[i].addr = 0; /* Clear it */
            return off;
        }
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
        /* LUI type */
        offset = (int32_t)val;
        hi = (uint32_t)(offset + 0x800) >> 12;
        *where = (*where & 0x00000fff) | (hi << 12);
        break;

    case R_RISCV_LO12_I:
        /* ADDI type */
        offset = (int32_t)val;
        lo = (uint32_t)offset & 0xfff;
        *where = (*where & 0x000fffff) | (lo << 20);
        break;

    case R_RISCV_LO12_S:
        /* SW type */
        offset = (int32_t)val;
        lo = (uint32_t)offset & 0xfff;
        *where = (*where & 0x01fff07f) | ((lo & 0xfe0) << 20) | ((lo & 0x01f) << 7);
        break;

    case R_RISCV_PCREL_HI20:
        /* AUIPC type */
        offset = (int32_t)val - (int32_t)where;
        hi = (uint32_t)(offset + 0x800) >> 12;
        *where = (*where & 0x00000fff) | (hi << 12);
        add_hi20((Elf32_Addr)where, offset);
        break;

    case R_RISCV_PCREL_LO12_I:
        /* Retrieve offset from LUT */
        offset = find_hi20(sym_val);
        lo = (uint32_t)offset & 0xfff;
        *where = (*where & 0x000fffff) | (lo << 20);
        break;

    case R_RISCV_PCREL_LO12_S:
        /* Retrieve offset from LUT */
        offset = find_hi20(sym_val);
        lo = (uint32_t)offset & 0xfff;
        *where = (*where & 0x01fff07f) | ((lo & 0xfe0) << 20) | ((lo & 0x01f) << 7);
        break;

    case R_RISCV_CALL:
    case R_RISCV_CALL_PLT:
        /* AUIPC + JALR */
        offset = (int32_t)val - (int32_t)where;
        hi = (uint32_t)(offset + 0x800) >> 12;
        lo = (uint32_t)offset & 0xfff;
        DPRINTF(("Reloc CALL at %lx to %lx (off=%lx, hi=%x, lo=%x)\n", (long)where, (long)val, (long)offset, hi, lo));
        /* Patch auipc */
        *where = (*where & 0x00000fff) | (hi << 12);
        /* Patch jalr */
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

    case R_RISCV_ADD32:
        *where += val;
        break;

    case R_RISCV_SUB32:
        *where -= val;
        break;

    case R_RISCV_32_PCREL:
        *where = val - (Elf32_Addr)where;
        break;

    case R_RISCV_SUB8:
        *(uint8_t *)where = (*(uint8_t *)where) - (uint8_t)(val);
        break;

    case R_RISCV_SUB16:
        *(uint16_t *)where = (*(uint16_t *)where) - (uint16_t)(val);
        break;

    case R_RISCV_SUB6:
        *(uint8_t *)where = (*(uint8_t *)where & 0xc0) | (((*(uint8_t *)where & 0x3f) - (val & 0x3f)) & 0x3f);
        break;

    case R_RISCV_SET6:
        *(uint8_t *)where = (*(uint8_t *)where & 0xc0) | (val & 0x3f);
        break;

    case R_RISCV_SET8:
        *(uint8_t *)where = (uint8_t)val;
        break;

    case R_RISCV_SET16:
        *(uint16_t *)where = (uint16_t)val;
        break;

    case R_RISCV_SET32:
        *(uint32_t *)where = (uint32_t)val;
        break;

    default:
        DPRINTF(("RISCV-BOOT: Unknown reloc type %d at %lx sym_val=%lx\n", type, (long)where, (long)sym_val));
        return -1;
    }
    return 0;
}

int relocate_rel(Elf32_Rel* rel, Elf32_Addr sym_val, char* target_sect)
{
    return -1;
}
