.section .text.start,"ax",@progbits
.global _start
_start:
    .option push
    .option norelax
    la sp, _stack_top
    .option pop
    call boot_main
1:  j 1b
