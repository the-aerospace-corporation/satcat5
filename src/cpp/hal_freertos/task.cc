//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_freertos/task.h>

// Allocate the task handle in task.cc, marked as extern in task.h
TaskHandle_t satcat5::freertos::satcat_task_handle = NULL;

// Default hook functions for SatCat5, marked as weak to allow users to override
// them. See also:
// https://www.freertos.org/Documentation/02-Kernel/02-Kernel-features/12-Hook-functions
// https://www.freertos.org/Documentation/02-Kernel/03-Supported-devices/02-Customization#configsupport_static_allocation

// Function required for static allocation. Copied from FreeRTOS documentation.
extern "C" __attribute__((weak))
void vApplicationGetIdleTaskMemory(StaticTask_t** ppxIdleTaskTCBBuffer,
    StackType_t** ppxIdleTaskStackBuffer, configSTACK_DEPTH_TYPE* pulIdleTaskStackSize)
{
    static StaticTask_t xIdleTaskTCB;
    static StackType_t uxIdleTaskStack[configMINIMAL_STACK_SIZE];
    *ppxIdleTaskTCBBuffer = &xIdleTaskTCB;
    *ppxIdleTaskStackBuffer = uxIdleTaskStack;
    *pulIdleTaskStackSize = configMINIMAL_STACK_SIZE;
}

// Function required for static allocation. Copied from FreeRTOS documentation.
extern "C" __attribute__((weak))
void vApplicationGetTimerTaskMemory( StaticTask_t **ppxTimerTaskTCBBuffer,
                                     StackType_t **ppxTimerTaskStackBuffer,
                                     configSTACK_DEPTH_TYPE *pulTimerTaskStackSize )
{
    static StaticTask_t xTimerTaskTCB;
    static StackType_t uxTimerTaskStack[ configTIMER_TASK_STACK_DEPTH ];
    *ppxTimerTaskTCBBuffer = &xTimerTaskTCB;
    *ppxTimerTaskStackBuffer = uxTimerTaskStack;
    *pulTimerTaskStackSize = configTIMER_TASK_STACK_DEPTH;
}

// Executes from an ISR, notify the timekeeper of the tick then resume.
extern "C" __attribute__((weak)) void vApplicationTickHook(void)
{
    satcat5::poll::timekeeper.request_poll();
    if(satcat5::freertos::satcat_task_handle)
        xTaskResumeFromISR(satcat5::freertos::satcat_task_handle);
}

// If dynamic allocation is used, halt execution if malloc() fails.
#if (configUSE_MALLOC_FAILED_HOOK == 1)
extern "C" __attribute__((weak)) void vApplicationMallocFailedHook(void)
{
    while (1) {} // Busywait forever, should trip watchdog.
}
#endif // (configUSE_MALLOC_FAILED_HOOK == 1)

// If stack overflow checking is enabled, halt execution if detected.
#if (configCHECK_FOR_STACK_OVERFLOW > 0)
extern "C" __attribute__((weak)) void vApplicationStackOverflowHook(
    TaskHandle_t xTask, char *pcTaskName)
{
    while (1) {} // Busywait forever, should trip watchdog.
}
#endif // (configCHECK_FOR_STACK_OVERFLOW > 0)
