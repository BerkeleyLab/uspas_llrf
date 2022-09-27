INCLUDE generated/output_format.ld
ENTRY(_start)
INCLUDE generated/regions.ld
__stack_size = 1k;
/* Use regions.ld instead of MEMORY in picolibc.ld */
/* INCLUDE picolibc.ld */
SECTIONS
{
	PROVIDE(__stack = ORIGIN(sram) + LENGTH(sram));
	.init : {
		KEEP (*(.text.init.enter))
		KEEP (*(.data.init.enter))
		KEEP (*(SORT_BY_NAME(.init) SORT_BY_NAME(.init.*)))
	} >main_ram AT>main_ram :text
	.text :
	{
		_ftext = .;
		/* ARM (Quicklogic EOS-S3, Gowin EMCU) interrupt vector tables use section name "isr_vector" */
		/* - such a table has to be placed at start */
		KEEP(*(.isr_vector))
		/* Make sure crt0 files come first, and they, and the isr */
		/* don't get disposed of by greedy optimisation */
		*crt0*(.text)
		KEEP(*crt0*(.text))
		KEEP(*(.text.isr))
		*(.text .stub .text.* .gnu.linkonce.t.*)
		_etext = .;
	} > main_ram
	.rodata :
	{
		. = ALIGN(8);
		_frodata = .;
		*(.rodata .rodata.* .gnu.linkonce.r.*)
		*(.rodata1)
		*(.got .got.*)
		*(.toc .toc.*)
		/* Make sure the file is aligned on disk as well
		   as in memory; CRC calculation requires that. */
		FILL(0);
		. = ALIGN(8);
		_erodata = .;
	} > main_ram
	.data :
	{
		. = ALIGN(8);
		_fdata = .;
		*(.data .data.* .gnu.linkonce.d.*)
		*(.data1)
		*(.sdata .sdata.* .gnu.linkonce.s.*)
		/* Make sure the file is aligned on disk as well
		   as in memory; CRC calculation requires that. */
		FILL(0);
		. = ALIGN(8);
		_edata = .;
	} > sram AT > main_ram
	.bss :
	{
		. = ALIGN(8);
		_fbss = .;
		*(.dynsbss)
		*(.sbss .sbss.* .gnu.linkonce.sb.*)
		*(.scommon)
		*(.dynbss)
		*(.bss .bss.* .gnu.linkonce.b.*)
		*(COMMON)
		. = ALIGN(8);
		__bss_end = .;
		_ebss = .;
		_end = .;
	} > sram
	/* Make the rest of memory available for heap storage */
	PROVIDE (__heap_start = _end);
	PROVIDE (__heap_end = __stack - (DEFINED(__stack_size) ? __stack_size : 0x800));
	PROVIDE (__heap_size = __heap_end - __heap_start);
	/* Define a stack region to make sure it fits in memory */
	.stack (NOLOAD) : {
		. += (DEFINED(__stack_size) ? __stack_size : 0x800);
	} > sram
	/DISCARD/ :
	{
		*(.eh_frame)
		*(.comment)
	}
}
PROVIDE(_fstack = ORIGIN(sram) + LENGTH(sram));
PROVIDE(_fdata_rom = LOADADDR(.data));
PROVIDE(_edata_rom = LOADADDR(.data) + SIZEOF(.data));
