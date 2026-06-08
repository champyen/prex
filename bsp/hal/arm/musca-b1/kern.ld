/*
 * Linker script for kernel on Musca-B1 (XIP Flash for code, SRAM for data)
 */
INCLUDE config.ld
OUTPUT_FORMAT("elf32-littlearm", "elf32-bigarm", "elf32-littlearm")
OUTPUT_ARCH(arm)
ENTRY(kernel_start)
PHDRS
{
	text PT_LOAD FILEHDR PHDRS;
	data PT_LOAD;
}
SECTIONS
{
	. = CONFIG_KERNEL_TEXT + SIZEOF_HEADERS;

	.text : {
		*(.text)
		*(.glue_7)
		*(.glue_7t)
	} : text = 0xff

	. = ALIGN(8);
	.rodata : {
		*(.rodata)
		*(.rodata.*)
		. = ALIGN(4);
		__exidx_start = .;
		*(.ARM.exidx*)
		__exidx_end = .;
		*(.ARM.extab*)
	} : text

	__data_lma = ALIGN(8);

	.data CONFIG_KERNEL_DATA : AT (__data_lma) {
		__data_start = .;
		*(.data)
		__data_end = .;
	} : data = 0xff

	. = ALIGN(8);
	__bss = . ;
	.bss .    : {
		*(.bss)
		*(COMMON)
	}
	. = ALIGN(8);
	__end = . ;

	/DISCARD/ : { *(.comment .note) }
}
