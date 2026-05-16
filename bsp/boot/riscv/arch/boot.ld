/*
 * Linker script for boot loader
 */
INCLUDE config.ld
OUTPUT_ARCH(riscv)
SECTIONS {
	. = CONFIG_LOADER_TEXT ;

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
		*(.bss)
		*(COMMON)
	}
	. = CONFIG_LOADER_TEXT + 0x1fff;
	.tail : {
		*(.tail)
	}

	/DISCARD/ : { *(.note*) *(.comment*) }
}
