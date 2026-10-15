OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 61440 }
SECTIONS {
    .text : { KEEP(*(.text.start)) *(.text*) *(.rodata*) *(.srodata*) } > RAM
    .data : { *(.data*) *(.sdata*) } > RAM
    .bss (NOLOAD) : {
        . = ALIGN(16); _bss_start = .;
        *(.bss*) *(.sbss*) *(COMMON)
        . = ALIGN(16); _bss_end = .;
    } > RAM
    _stack_bottom = 0x8000f000;
    _stack_top = 0x80010000;
    __freertos_irq_stack_top = _stack_top;
    ASSERT(_bss_end <= _stack_bottom, "FreeRTOS image/heap overlaps the 4 KiB main/ISR stack")
    /DISCARD/ : { *(.comment) *(.eh_frame*) }
}
