OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY {
    FLASH (rx) : ORIGIN = 0x30050010, LENGTH = 65520
    RAM (rw) : ORIGIN = 0x80000000, LENGTH = 65536
}
SECTIONS {
    .text : { KEEP(*(.text.start)) *(.text*) *(.rodata*) } > FLASH
    .data : { *(.data*) *(.sdata*) } > RAM
    .bss (NOLOAD) : { _bss_start = .; *(.bss*) *(.sbss*) *(COMMON) . = ALIGN(4); _bss_end = .; } > RAM
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
    /DISCARD/ : { *(.comment) *(.eh_frame*) }
    ASSERT(SIZEOF(.data) == 0, "Flash application needs .data copy support")
}
