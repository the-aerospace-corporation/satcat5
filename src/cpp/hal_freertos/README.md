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
const unsigned STACK_SIZE = 8 * 1024; // 8KB
satcat5::freertos::ControllerFreeRTOS irq_controller;
satcat5::freertos::TickTimer tick_timer;
satcat5::freertos::SatCatTask<STACK_SIZE, tskIDLE_PRIORITY+1> satcat5_task(
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

# Copyright Notice

Copyright 2025 The Aerospace Corporation.

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https://cern.ch/cern-ohl) for applicable conditions.
