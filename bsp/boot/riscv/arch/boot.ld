/*
 * Linker script for boot loader (RISC-V)
 */
INCLUDE config.ld
OUTPUT_ARCH(riscv)
SECTIONS {
    /* 
     * QEMU RISC-V Virt loads -kernel at 0x80000000.
     * We want LOADER_TEXT to be at 0x80010000 to leave room for the System Page.
     * We put a jump at 0x80000000 to the real entry point.
     */
    . = 0x80000000;
    .entry : {
        *(.entry)
    }

    . = CONFIG_LOADER_TEXT ; /* 0x80010000 */

    .text . : {
        *(.start)
        *(.text)
    }
    . = ALIGN(16);
    .rodata . : {
        *(.rodata)
        *(.rodata.*)
    }
    . = ALIGN(16);
    .data . : {
        *(.data)
    }
    . = ALIGN(16);
    .bss . : {
        __bss = . ;
        *(.bss)
        *(COMMON)
        __end = . ;
    }

    . = CONFIG_LOADER_TEXT + 0x3fff;
    .tail : {
        BYTE(0xff);
    }

    /DISCARD/ : { *(.note*) *(.comment*) }
}
