//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// FreeRTOS implementation of the "InterruptController" class. This
// implementation supports irq_pause() and irq_resume() via FreeRTOS
// portable layer API. This interrupt controller does not override any
// vector tables, or provide any interrupt handlers for a given
// processor. It is the responsibility of the user to create the ISR for
// the processor and call irq_handler() passing the associated SatCat
// handler obj to defer interrupt processing to SatCat. It is important
// to note that you only NEED to do this if leveraging any SatCat HAL
// peripherals that have integrated ISRs (SAMV71, PFSoC, etc). The below
// example demonstrates this using this class and the UsartDmaSAMV71
// class provided by hal_samv71. Since this is a SAMV71, we have to define
// XDMAC_Handler() to catch the DMA interrupt. Since UsartDmaSAMV71 then
// has an integrated ISR, we pass in the object to irq_handler() to defer
// processing to SatCat.
//
// Example:
//
// extern satcat5::freertos::ControllerFreeRTOS irq_controller;
// extern satcat5::sam::UsartDmaSAMV71 satcat_uart;
//
// void XDMAC_Handler()
// {
//     irq_controller.irq_handler(&satcat_uart);
// }

#pragma once

//////////////////////////////////////////////////////////////////////////
// Includes
//////////////////////////////////////////////////////////////////////////

// SatCat
#include <satcat5/interrupts.h>
#include <satcat5/timeref.h>

// FreeRTOS
extern "C"{
    #include <FreeRTOS.h>
    #include <task.h>
};

//////////////////////////////////////////////////////////////////////////

namespace satcat5 {
    namespace freertos {
        // Control object for registering interrupt handlers and handling
        // nested calls to atomic_start, atomic_end, etc.  Children should
        // implement the specified platform-specific methods.
        class ControllerFreeRTOS : public satcat5::irq::Controller {
            public:
            // Constructor
            ControllerFreeRTOS();

            // Initialize FreeRTOS controller and start SatCat5 interrupts.
            void irq_start(satcat5::util::TimeRef* timer = 0);

            // IRQ Handler
            void irq_handler(satcat5::irq::Handler* obj);

            protected:
            // Hardware-abstraction overrides.
            void irq_pause() override;
            void irq_resume() override;
            void irq_register(satcat5::irq::Handler* obj) override;
            void irq_unregister(satcat5::irq::Handler* obj) override;
            void irq_acknowledge(satcat5::irq::Handler* obj) override;
        };
    }  // namespace freertos
}  // namespace satcat5

//////////////////////////////////////////////////////////////////////////
