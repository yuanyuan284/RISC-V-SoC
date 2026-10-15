#ifndef SOC_FREERTOS_CONFIG_H
#define SOC_FREERTOS_CONFIG_H
#include <stdint.h>
void rtos_fail(const char *reason, unsigned line);
#define configCPU_CLOCK_HZ 25000000UL
#define configTICK_RATE_HZ 1000
#define configMTIME_BASE_ADDRESS 0x0200bff8UL
#define configMTIMECMP_BASE_ADDRESS 0x02004000UL
#define configUSE_PREEMPTION 1
#define configUSE_TIME_SLICING 1
#define configUSE_PORT_OPTIMISED_TASK_SELECTION 1
#define configMAX_PRIORITIES 5
#define configMINIMAL_STACK_SIZE 128
#define configMAX_TASK_NAME_LEN 12
#define configTOTAL_HEAP_SIZE (16 * 1024)
#define configSUPPORT_DYNAMIC_ALLOCATION 1
#define configSUPPORT_STATIC_ALLOCATION 0
#define configUSE_16_BIT_TICKS 0
#define configUSE_MUTEXES 0
#define configUSE_TIMERS 0
#define configUSE_TASK_NOTIFICATIONS 1
#define configUSE_IDLE_HOOK 0
#define configUSE_TICK_HOOK 1
#define configCHECK_FOR_STACK_OVERFLOW 2
#define configUSE_MALLOC_FAILED_HOOK 1
#define configUSE_NEWLIB_REENTRANT 0
#define configUSE_TRACE_FACILITY 0
#define configQUEUE_REGISTRY_SIZE 0
#define configASSERT(x) do { if (!(x)) rtos_fail(#x, __LINE__); } while (0)
#define INCLUDE_vTaskDelay 1
#define INCLUDE_xTaskDelayUntil 1
#define INCLUDE_vTaskSuspend 1
#define INCLUDE_uxTaskGetStackHighWaterMark 1
#define INCLUDE_xTaskGetSchedulerState 1
#define traceTASK_SWITCHED_IN() do { extern volatile uint32_t rtos_switches; ++rtos_switches; } while (0)
#endif
