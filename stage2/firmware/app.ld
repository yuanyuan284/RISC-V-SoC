OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 896 }
SECTIONS {
    .text : { KEEP(*(.text.start)) *(.text*) *(.rodata*) } > RAM
    .data : { *(.data*) *(.sdata*) } > RAM
    .bss (NOLOAD) : {
        . = ALIGN(4); _bss_start = .;
        *(.bss*) *(.sbss*) *(COMMON)
        . = ALIGN(4); _bss_end = .;
    } > RAM
    _stack_top = 0x80000400;
    /DISCARD/ : { *(.comment) *(.eh_frame*) }
}
