/*
 * Linker script for user-space applications (RISC-V NOMMU)
 */
OUTPUT_FORMAT("elf32-littleriscv")
OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
        . = 0;

        .text : {
                *(.text)
                *(.text.*)
        }

        . = ALIGN(4);
        .rodata : {
                *(.rodata)
                *(.rodata.*)
                *(.srodata)
                *(.srodata.*)
        }

        . = ALIGN(4);
        .data : {
                __global_pointer$ = . + 0x800;
                *(.data)
                *(.data.*)
                *(.sdata)
                *(.sdata.*)
        }

        . = ALIGN(4);
        .bss : {
                *(.sbss)
                *(.sbss.*)
                *(.bss)
                *(.bss.*)
                *(COMMON)
        }

        /DISCARD/ : { *(.comment .note) }
}
