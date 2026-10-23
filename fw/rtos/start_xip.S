.section .text.start,"ax",@progbits
.global _start
_start:
    csrci mstatus, 8
    csrw mie, zero
    .option push
    .option norelax
    la sp, _stack_top
    la t0, freertos_risc_v_trap_handler
    la a0, _ramtext_load
    la a1, _ramtext_start
    la a2, _ramtext_end
    .option pop
    csrw mtvec, t0
1:  bgeu a1, a2, 2f
    lw t1, 0(a0)
    sw t1, 0(a1)
    addi a0, a0, 4
    addi a1, a1, 4
    j 1b
2:  .option push
    .option norelax
    la a0, _data_load
    la a1, _data_start
    la a2, _data_end
    .option pop
3:  bgeu a1, a2, 4f
    lw t1, 0(a0)
    sw t1, 0(a1)
    addi a0, a0, 4
    addi a1, a1, 4
    j 3b
4:  .option push
    .option norelax
    la a0, _bss_start
    la a1, _bss_end
    .option pop
5:  bgeu a0, a1, 6f
    sw zero, 0(a0)
    addi a0, a0, 4
    j 5b
6:  call main
7:  j 7b
