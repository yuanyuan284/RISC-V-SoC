OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY {
    FLASH (rx) : ORIGIN = 0x30050010, LENGTH = 65520
    RAM_DATA (rw) : ORIGIN = 0x80000000, LENGTH = 32768
    RAM_CODE (rx) : ORIGIN = 0x80008000, LENGTH = 28672
}
SECTIONS {
    .entry : { KEEP(*(.text.start)) } > FLASH
    .text : {
        *(EXCLUDE_FILE (*freertos_tasks.o *freertos_list.o *freertos_portASM.o) .text*)
        *(.rodata*) *(.srodata*)
        . = ALIGN(4);
    } > FLASH
    .ramtext : {
        . = ALIGN(4); _ramtext_start = .;
        *freertos_tasks.o(.text*)
        *freertos_list.o(.text*)
        *freertos_portASM.o(.text*)
        . = ALIGN(4); _ramtext_end = .;
    } > RAM_CODE AT> FLASH
    _ramtext_load = LOADADDR(.ramtext);
    .data : {
        . = ALIGN(4); _data_start = .;
        *(.data*) *(.sdata*)
        . = ALIGN(4); _data_end = .;
    } > RAM_DATA AT> FLASH
    _data_load = LOADADDR(.data);
    .bss (NOLOAD) : {
        . = ALIGN(16); _bss_start = .;
        *(.bss*) *(.sbss*) *(COMMON)
        . = ALIGN(16); _bss_end = .;
    } > RAM_DATA
    _stack_bottom = 0x8000f000;
    _stack_top = 0x80010000;
    __freertos_irq_stack_top = _stack_top;
    ASSERT(_bss_end <= ORIGIN(RAM_DATA) + LENGTH(RAM_DATA), "FreeRTOS data/heap exceeds low RAM")
    ASSERT(_ramtext_end <= ORIGIN(RAM_CODE) + LENGTH(RAM_CODE), "FreeRTOS RAM code exceeds high RAM")
    /DISCARD/ : { *(.comment) *(.eh_frame*) }
}
