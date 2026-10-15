.section .text.register_spinner,"ax",@progbits
.global register_spinner
register_spinner:
    addi s0, a1, 1
    addi s1, a1, 2
    addi s2, a1, 3
    addi s3, a1, 4
    addi s4, a1, 5
    addi s5, a1, 6
    addi s6, a1, 7
    addi s7, a1, 8
    addi s8, a1, 9
    addi s9, a1, 10
    addi s10, a1, 11
    addi s11, a1, 12
1:
    addi t0, a1, 1
    bne s0, t0, rtos_register_failure
    addi t0, t0, 1
    bne s1, t0, rtos_register_failure
    addi t0, t0, 1
    bne s2, t0, rtos_register_failure
    addi t0, t0, 1
    bne s3, t0, rtos_register_failure
    addi t0, t0, 1
    bne s4, t0, rtos_register_failure
    addi t0, t0, 1
    bne s5, t0, rtos_register_failure
    addi t0, t0, 1
    bne s6, t0, rtos_register_failure
    addi t0, t0, 1
    bne s7, t0, rtos_register_failure
    addi t0, t0, 1
    bne s8, t0, rtos_register_failure
    addi t0, t0, 1
    bne s9, t0, rtos_register_failure
    addi t0, t0, 1
    bne s10, t0, rtos_register_failure
    addi t0, t0, 1
    bne s11, t0, rtos_register_failure
    lw t1, 0(a0)
    addi t1, t1, 1
    sw t1, 0(a0)
    j 1b
