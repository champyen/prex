/*
 * Linker script for armv8-m boot loader
 */
INCLUDE config.ld
OUTPUT_FORMAT("elf32-littlearm", "elf32-bigarm", "elf32-littlearm")
OUTPUT_ARCH(arm)
SECTIONS {
	. = CONFIG_LOADER_TEXT ;

	.text . : {
		*(.start)
		*(.text)
		*(.text.*)
	}
	. = ALIGN(4);
	.rodata . : {
		*(.rodata)
		*(.rodata.*)
	}
	. = ALIGN(4);
	.data . : {
		*(.data)
		*(.data.*)
	}
	. = ALIGN(4);
	.bss . : {
		*(.bss)
		*(.bss.*)
		*(COMMON)
	}
	. = CONFIG_LOADER_TEXT + 0x1fff;
	.tail : {
		*(.tail)
	}

	/DISCARD/ : { *(.ARM.exidx) }
}
