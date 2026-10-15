#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#define MMIO(a) (*(volatile uint32_t *)(a))
#define UART_BASE 0x40001000u
#define PLIC_BASE 0x0c000000u
#define EVENT 0x40002000u
#define MSIP 0x02000000u
static QueueHandle_t messages;
static TaskHandle_t irq_task;
volatile uint32_t rtos_switches, tick_hooks, spins[2];
volatile uint32_t software_irqs, event_irqs, uart_irqs, notifications, consumed;
extern void register_spinner(volatile uint32_t *counter, uint32_t seed);
void rtos_register_failure(void) { rtos_fail("register context", 0); }

static void puts_uart(const char *text) {
    while (*text) {
        while (MMIO(UART_BASE + 0x40) & 2u) {}
        MMIO(UART_BASE + 0x4c) = (uint8_t)*text++;
    }
}
static void number(uint32_t value) {
    char digits[11]; unsigned n = 0;
    do { digits[n++] = (char)('0' + value % 10); value /= 10; } while (value);
    while (n) { char byte[2] = {digits[--n], 0}; puts_uart(byte); }
}
void rtos_fail(const char *reason, unsigned line) {
    portDISABLE_INTERRUPTS();
    puts_uart("FREERTOS FAIL: "); puts_uart(reason);
    puts_uart(" line="); number(line); puts_uart("\r\n");
    for (;;) {}
}
void vApplicationMallocFailedHook(void) { rtos_fail("heap", 0); }
void vApplicationStackOverflowHook(TaskHandle_t task, char *name) {
    (void)task; rtos_fail(name, 0);
}
void vApplicationTickHook(void) { ++tick_hooks; }
void freertos_risc_v_application_exception_handler(uint32_t cause) {
    rtos_fail("exception", cause);
}
void freertos_risc_v_application_interrupt_handler(uint32_t cause) {
    BaseType_t wake = pdFALSE;
    if (cause == 0x80000003u) {
        MMIO(MSIP) = 0; ++software_irqs;
        vTaskNotifyGiveFromISR(irq_task, &wake);
    } else if (cause == 0x8000000bu) {
        uint32_t id = MMIO(PLIC_BASE + 0x200004);
        if (id == 1) {
            while (!(MMIO(UART_BASE + 0x80) & 1u)) {
                (void)MMIO(UART_BASE + 0x8c); ++uart_irqs;
            }
        } else if (id == 2) {
            MMIO(EVENT) = 0; ++event_irqs;
        } else { rtos_fail("PLIC claim", id); }
        MMIO(PLIC_BASE + 0x200004) = id;
        vTaskNotifyGiveFromISR(irq_task, &wake);
    } else { rtos_fail("interrupt", cause); }
    portYIELD_FROM_ISR(wake);
}
static void interrupt_task(void *argument) {
    (void)argument;
    uint32_t reported = 0;
    for (;;) {
        notifications += ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        if (uart_irqs > reported) {
            reported = uart_irqs;
            puts_uart("UART IRQ PASS count="); number(reported); puts_uart("\r\n");
        }
    }
}
static void spin_task(void *argument) {
    unsigned id = (unsigned)(uintptr_t)argument;
    // Distinct saved-register values must survive involuntary task switches.
    register_spinner(&spins[id], 0x1000u + 0x100u * id);
    rtos_fail("spinner returned", 0);
}
static void producer(void *argument) {
    (void)argument; uint32_t sequence = 1;
    TickType_t previous = xTaskGetTickCount();
    for (;;) {
        configASSERT(xQueueSend(messages, &sequence, portMAX_DELAY) == pdPASS);
        ++sequence; xTaskDelayUntil(&previous, 5);
    }
}
static void consumer(void *argument) {
    (void)argument; uint32_t value, expected = 1;
    for (;;) {
        configASSERT(xQueueReceive(messages, &value, portMAX_DELAY) == pdPASS);
        configASSERT(value == expected++); ++consumed;
    }
}
static void monitor(void *argument) {
    (void)argument;
    uint32_t status;
    taskENTER_CRITICAL(); taskENTER_CRITICAL();
    __asm volatile ("csrr %0, mstatus" : "=r"(status));
    configASSERT(!(status & 8u));
    TickType_t before = xTaskGetTickCount();
    taskYIELD();
    configASSERT(xTaskGetTickCount() == before);
    taskEXIT_CRITICAL();
    __asm volatile ("csrr %0, mstatus" : "=r"(status));
    configASSERT(!(status & 8u));
    taskEXIT_CRITICAL();
    __asm volatile ("csrr %0, mstatus" : "=r"(status));
    configASSERT(status & 8u);
    vTaskDelay(10);
    MMIO(MSIP) = 1;
    MMIO(EVENT) = 1;
    vTaskDelay(50);
    configASSERT(tick_hooks >= 60 && xTaskGetTickCount() >= 60);
    configASSERT(spins[0] > 100 && spins[1] > 100);
    configASSERT(consumed >= 10 && rtos_switches >= 20);
    configASSERT(software_irqs == 1 && event_irqs == 1 && notifications >= 2);
    puts_uart("CHECK preemption=1 registers=1 critical=1 queue=1 notify=1\r\n");
    puts_uart("FREERTOS PASS tick="); number(xTaskGetTickCount());
    puts_uart(" switches="); number(rtos_switches);
    puts_uart(" queue="); number(consumed);
    puts_uart(" msip="); number(software_irqs);
    puts_uart(" plic="); number(event_irqs);
    puts_uart(" uart="); number(uart_irqs);
    puts_uart("\r\n");
    for (;;) {
        vTaskDelay(1000);
        configASSERT(spins[0] > 100 && spins[1] > 100);
        puts_uart("RTOS ALIVE tick="); number(xTaskGetTickCount());
        puts_uart(" queue="); number(consumed); puts_uart("\r\n");
    }
}
int main(void) {
    MMIO(UART_BASE) = 216;
    puts_uart("FREERTOS START V11.1.0 RV32IM 64K tick=1000Hz\r\n");
    MMIO(PLIC_BASE + 4) = 1; MMIO(PLIC_BASE + 8) = 2;
    MMIO(PLIC_BASE + 0x2000) = 6; MMIO(PLIC_BASE + 0x200000) = 0;
    MMIO(MSIP) = 0; MMIO(EVENT) = 0;
    messages = xQueueCreate(4, sizeof(uint32_t));
    configASSERT(messages != NULL);
    configASSERT(xTaskCreate(interrupt_task, "IRQ", 256, NULL, 3, &irq_task) == pdPASS);
    configASSERT(xTaskCreate(producer, "producer", 256, NULL, 2, NULL) == pdPASS);
    configASSERT(xTaskCreate(consumer, "consumer", 256, NULL, 2, NULL) == pdPASS);
    configASSERT(xTaskCreate(monitor, "monitor", 256, NULL, 2, NULL) == pdPASS);
    configASSERT(xTaskCreate(spin_task, "spin0", 128, (void *)0, 1, NULL) == pdPASS);
    configASSERT(xTaskCreate(spin_task, "spin1", 128, (void *)1, 1, NULL) == pdPASS);
    __asm volatile ("csrs mie, %0" :: "r"(8));
    vTaskStartScheduler();
    rtos_fail("scheduler returned", 0);
    return 0;
}
