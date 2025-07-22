//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
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

#ifndef portYIELD_FROM_ISR(x)
#define portYIELD_FROM_ISR(x) portEND_SWITCHING_ISR(x)
#endif

namespace satcat5 {
    namespace freertos {

        //! Instantiate a FreeRTOS statically-allocated Task. This class can
        //! then be inherited by other classes to create FreeRTOS tasks.
        template <configSTACK_DEPTH_TYPE TASK_SIZE, unsigned TASK_PRIORITY>
        class StaticTask {
        public:
            //! Suspends running task
            inline void suspend(void) {
                vTaskSuspend(m_task_handle);
            }
            //! Resumes suspended task
            inline void resume(void) {
                vTaskResume(m_task_handle);
            }
            //! Resumes suspended task (should be called from ISR)
            inline void resume_from_isr(void) {
                xTaskResumeFromISR(m_task_handle);
            }
            //! Returns task handle of created task
            inline TaskHandle_t get_task_handle(void) {
                return m_task_handle;
            }
            //! Notify Task
            inline void notify(void) {
                xTaskNotifyGive(m_task_handle);
            }
            //! Notify Task (should be called from ISR)
            inline void notify_from_isr(void) {
                BaseType_t yield_flag = pdFALSE;
                vTaskNotifyGiveFromISR(m_task_handle, &yield_flag);
                portYIELD_FROM_ISR(yield_flag);
            }

        protected:
            // Class Constructor
            StaticTask(
                const char* task_name,
                TaskFunction_t task_function,
                void * const task_params = NULL)
            {
                // Create Static Task
                m_task_handle = xTaskCreateStatic(
                    task_function,
                    task_name,
                    TASK_SIZE,
                    task_params,
                    TASK_PRIORITY,
                    m_stack,
                    &m_static_task);
            }

            // Member Variables
            TaskHandle_t    m_task_handle;          //!< Task Handle
            StackType_t     m_stack[TASK_SIZE];     //!< Task Stack
            StaticTask_t    m_static_task;          //!< Task internals
        };

        //! Task handle, must be outside StaticTask for access by
        //! vApplicationTickHook()
        extern TaskHandle_t satcat_task_handle;

        //! Instantiate a FreeRTOS statically-allocated Task that services the
        //! SatCat5 core loop. The task implementation is in a separate static
        //! member function StaticTask::task(). To use, instantiate this class
        //! in global scope of your main file and call `vTaskStartScheduler()`
        //! as is typical for FreeRTOS.
        template <configSTACK_DEPTH_TYPE TASK_SIZE, unsigned TASK_PRIORITY>
        class SatCatTask : public StaticTask<TASK_SIZE, TASK_PRIORITY> {
        public:
            // Constructor
            SatCatTask(
                ControllerFreeRTOS* irq_controller,
                TickTimer* tick_timer)
                    : StaticTask<TASK_SIZE, TASK_PRIORITY>(
                        "SatCat OS Task",
                        task,
                        this)
                    , m_irq_controller(irq_controller)
                    , m_tick_timer(tick_timer)
            {
                satcat_task_handle = this->get_task_handle();
            }

            //! Core task entry function, performs setup then calls
            //! poll::service_all() on a loop.
            //! \param pvParams A pointer to a freertos::Parameters struct.
            static void task(void* pvParams)
            {
                // Link Reference Tick to Timekeeper, init Interrupt Controller
                SatCatTask* params = (SatCatTask*) pvParams;
                satcat5::poll::timekeeper.set_clock(params->m_tick_timer);
                params->m_irq_controller->irq_start(params->m_tick_timer);

                // Start-up Message
                satcat5::log::Log(satcat5::log::INFO,
                    "FreeRTOS with SatCat5!\r\n\t"
                    "Built ").write(satcat5::get_sw_build_string());

                // Main loop services all demands then returns to the scheduler.
                while (1) {
                    satcat5::poll::service_all();
                    vTaskSuspend(params->m_task_handle);
                }
            }

            // Member Variables, left public for access from `task()`.
            ControllerFreeRTOS* m_irq_controller;   //!< Interrupt Controller
            TickTimer*          m_tick_timer;       //!< Reference Timer
        };
    }  // namespace freertos
}  // namespace satcat5

