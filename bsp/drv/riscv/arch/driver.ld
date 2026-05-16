/*
 * Linker script for driver
 */
OUTPUT_ARCH(riscv)
SECTIONS
{
	.text : {
		*(.text)
	}
	. = ALIGN(16);
	.rodata : {
		*(.rodata)
		*(.rodata.*)
	}
	. = ALIGN(16);
	.data : {
		*(.data)
	}
	. = ALIGN(16);
	.bss : {
		*(.bss)
		*(COMMON)
	}

	/DISCARD/ : { *(.comment .note) }
}
