/*
 * Linker script for driver (RISC-V)
 */
INCLUDE config.ld
OUTPUT_FORMAT("elf32-littleriscv")
OUTPUT_ARCH(riscv)
ENTRY(driver_main)
PHDRS
{
	text PT_LOAD FILEHDR PHDRS;
	data PT_LOAD;
}
SECTIONS
{
	. = SIZEOF_HEADERS ;

	.text : {
	        *(.text*)
	} : text = 0xff

	. = ALIGN(4);

	.rodata : {
		*(.rodata)
		*(.rodata.*)
	} : text

        . = ALIGN(4);
	.data : {
		*(.data)
		*(.data.*)
		*(.sdata)
		*(.sdata.*)
	} : data

        . = ALIGN(4);
	.bss . : {
		*(.sbss)
		*(.sbss.*)
		*(.bss)
		*(.bss.*)
		*(COMMON)
	}

	/DISCARD/ : { *(.comment .note .debug_*) }
}
