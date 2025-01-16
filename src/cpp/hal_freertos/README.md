# FreeRTOS HAL Introduction

hal_freertos is a powerful HAL for SatCat5 that leverages the FreeRTOS port
layer API to extend compatibility with most (if not all) FreeRTOS processors.
This layer enables rapid deployment of SatCat5 on a processor that has an
existing provided FreeRTOS port. This README aims to provide the "how-to" with
examples.

# Important Notes

- All SatCat objects are created in the main source file as global objects.
- User MUST Resume SatCatOS for processing. Based on the current implementation,
  SatCat will sleep after processing (to save power). So if a FreeRTOS task (or
  other) writes data for processing, the user must wake the task.

# Getting Started with SatCat Task

There are only 3 objects that you will need to instantiate to start running
SatCatOS on FreeRTOS:
* ControllerFreeRTOS
    * Provides critical sections for SatCat5 infrastructure.
* TickTimer
    * Leverages `xTaskGetTickCount()` to supply a low-rate, platform-agnostic
      timer.
    * Ensure configTICK_RATE_HZ is configured correctly.
* StaticTask
    * Establishes a statically-allocated task to run SatCat5 infrastructure.

See the below example:

```
// FreeRTOS
extern "C"
{
#include <FreeRTOS.h>
}

// SatCat HAL
#include <hal_freertos/interrupts.h>
#include <hal_freertos/task.h>
#include <hal_freertos/tick_timer.h>

// SatCat HAL
const unsigned satcat5_stack_size = 8 * 1024; // 8KB
satcat5::freertos::ControllerFreeRTOS irq_controller;
satcat5::freertos::TickTimer tick_timer;
satcat5::freertos::StaticTask<satcat5_stack_size> satcat5_task(
    &irq_controller, &tick_timer);

// main()
int main(void)
{
    // Other initialization functions...

    // Start FreeRTOS Scheduler
    vTaskStartScheduler();

    // Unreachable
    return 0;
}
```
