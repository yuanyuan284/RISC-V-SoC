.section .text.start,"ax",@progbits
.global _start
_start:
    csrci mstatus, 8
    csrw mie, zero
    .option push
    .option norelax
    la sp, _stack_top
    la a0, _bss_start
    la a1, _bss_end
    la t0, freertos_risc_v_trap_handler
    .option pop
    csrw mtvec, t0
1:  bgeu a0, a1, 2f
    sw zero, 0(a0)
    addi a0, a0, 4
    j 1b
2:  call main
3:  j 3b
