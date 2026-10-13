OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY {
    ROM (rx) : ORIGIN = 0x20000000, LENGTH = 1024
    RAM (rw) : ORIGIN = 0x80000000, LENGTH = 1024
}
SECTIONS {
    .text : { KEEP(*(.text.start)) *(.text*) *(.rodata*) } > ROM
    .data : { *(.data*) *(.sdata*) } > RAM
    .bss (NOLOAD) : { *(.bss*) *(.sbss*) *(COMMON) } > RAM
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
    /DISCARD/ : { *(.comment) *(.eh_frame*) }
    ASSERT(SIZEOF(.data) == 0, "BootROM startup has no data relocation")
    ASSERT(SIZEOF(.bss) == 0, "BootROM startup has no BSS initialization")
}
