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
		__bss = . ;
		*(.bss)
		*(COMMON)
		__end = . ;
	}
	. = CONFIG_LOADER_TEXT + 0xffff;
	.tail : {
		*(.tail)
	}

	/DISCARD/ : { *(.note*) *(.comment*) }
}
