/*
 * Linker script for kernel
 */
INCLUDE config.ld
OUTPUT_ARCH(riscv)
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
	} : text = 0xff

	. = ALIGN(16);
	PROVIDE(__global_pointer$ = . + 0x800);

	.rodata : {
		*(.rodata)
		*(.rodata.*)
	} : text

	.data ALIGN(16) : {
		*(.data)
	} : data = 0xff

	. = ALIGN(16);
	__bss = . ;
	.bss .    : {
		*(.bss)
		*(COMMON)
	}
	. = ALIGN(16);
	__end = . ;

	/DISCARD/ : { *(.comment .note) }
}
