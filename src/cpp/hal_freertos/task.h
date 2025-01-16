//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! Provides a FreeRTOS task function and hooks for using SatCat5 as a task
//! inside a larger FreeRTOS project.
//!
//! Please reference the FreeRTOS HAL README.md for help getting this code
//! running.
//!

#pragma once

#include <satcat5/build_date.h>
#include <satcat5/polling.h>
#include <satcat5/log.h>
extern "C"{
#include <FreeRTOS.h>
#include <task.h>
};
#include <hal_freertos/interrupts.h>
#include <hal_freertos/tick_timer.h>

// This HAL requires static allocation and tick hooks to be enabled.
#if (configSUPPORT_STATIC_ALLOCATION == 0)
#error FreeRTOS static allocation must be enabled for SatCat5.
#endif // (configSUPPORT_STATIC_ALLOCATION == 0)
#if (configUSE_TICK_HOOK == 0)
#error The FreeRTOS tick hook must be enabled for SatCat5.
#endif // (configUSE_TICK_HOOK == 0)

namespace satcat5 {
    namespace freertos {
        //! Task handle, must be outside StaticTask for access by C functions.
        extern TaskHandle_t task_handle;

        //! Struct holding all relevant parameters for Task::task().
        struct Parameters {
            ControllerFreeRTOS* irq_controller;
            TickTimer* tick_timer;
        };

        //! Instantiate a FreeRTOS statically-allocated Task that services the
        //! SatCat5 core loop. The task implementation is in a separate static
        //! member function StaticTask::task(). To use, instantiate this class
        //! in global scope of your main file and call `vTaskStartScheduler()`
        //! as is typical for FreeRTOS.
        template <unsigned STACK_SIZE>
        class StaticTask final {
        public:
            StaticTask(
                ControllerFreeRTOS* irq_controller, TickTimer* tick_timer,
                unsigned priority=tskIDLE_PRIORITY)
                    : m_params({irq_controller, tick_timer})
                {
                    task_handle = xTaskCreateStatic(
                        (TaskFunction_t) task,
                        "SatCat5 Core Infrastructure",
                        STACK_SIZE,
                        &m_params,
                        priority,
                        m_stack,
                        &m_static_task);
            }

            //! Core task entry function, performs setup then calls
            //! poll::service_all() on a loop.
            //! \param pvParams A pointer to a freertos::Parameters struct.
            static void task(void* pvParams)
            {
                // Link Reference Tick to Timekeeper, init Interrupt Controller
                Parameters* params = (Parameters*) pvParams;
                satcat5::poll::timekeeper.set_clock(params->tick_timer);
                params->irq_controller->irq_start(params->tick_timer);

                // Start-up Message
                satcat5::log::Log(satcat5::log::INFO,
                    "FreeRTOS with SatCat5!\r\n\t"
                    "Built ").write(satcat5::get_sw_build_string());

                // Main loop services all demands then returns to the scheduler.
                while (1) {
                    satcat5::poll::service_all();
                    vTaskSuspend(task_handle);
                }
            }

        private:
            // Member variables
            Parameters      m_params;               //!< Task parameters.
            StackType_t     m_stack[STACK_SIZE];    //!< Task stack.
            StaticTask_t    m_static_task;          //!< Task internals.
        };
    }
}
