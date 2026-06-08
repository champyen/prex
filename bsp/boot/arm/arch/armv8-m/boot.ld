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
	_data_flash_start = . ;

	.data (CONFIG_SYSPAGE_BASE + 0x4000) : AT(_data_flash_start) {
		_data_start = . ;
		*(.data)
		*(.data.*)
		_data_end = . ;
	}
	. = ALIGN(4);
	.bss . : {
		_bss_start = . ;
		*(.bss)
		*(.bss.*)
		*(COMMON)
		_bss_end = . ;
	}
	. = _data_flash_start + SIZEOF(.data) ;
	.tail : {
		*(.tail)
	}

	/DISCARD/ : { *(.ARM.exidx) }
}
