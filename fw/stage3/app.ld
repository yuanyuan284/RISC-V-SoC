OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 61440 }
SECTIONS {
    .text : { KEEP(*(.text.start)) *(.text*) *(.rodata*) *(.srodata*) } > RAM
    .data : { *(.data*) *(.sdata*) } > RAM
    .bss (NOLOAD) : {
        . = ALIGN(4); _bss_start = .;
        *(.bss*) *(.sbss*) *(COMMON)
        . = ALIGN(4); _bss_end = .;
    } > RAM
    . = ALIGN(16); _heap_start = .;
    _heap_end = 0x8000b800;
    ASSERT(_heap_start + 4096 <= _heap_end, "Need at least 4 KiB heap before memory test")
    .memtest 0x8000b800 (NOLOAD) : { *(.memtest) } > RAM
    _stack_bottom = 0x8000f000;
    _stack_top = 0x80010000;
    /DISCARD/ : { *(.comment) *(.eh_frame*) }
}
