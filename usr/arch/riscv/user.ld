/*
 * Linker script for user-space applications (RISC-V)
 */
OUTPUT_FORMAT("elf32-littleriscv")
OUTPUT_ARCH(riscv)
ENTRY(_start)
PHDRS
{
	text PT_LOAD FILEHDR PHDRS;
	data PT_LOAD;
}
SECTIONS
{
	. = 0x10000 + SIZEOF_HEADERS;

	.text : {
		*(.text)
		*(.text.*)
	} : text

	. = ALIGN(8);
	.rodata : {
		*(.rodata)
		*(.rodata.*)
	} : text

	. = ALIGN(0x1000);
	.data : {
		*(.data)
		*(.data.*)
		*(.sdata)
		*(.sdata.*)
	} : data

	. = ALIGN(8);
	.bss .  : {
		*(.sbss)
		*(.sbss.*)
		*(.bss)
		*(.bss.*)
		*(COMMON)
	}

	/DISCARD/ : { *(.comment .note) }
}
