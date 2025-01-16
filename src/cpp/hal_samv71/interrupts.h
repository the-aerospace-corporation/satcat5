//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Microchip SAM V71 implementation of the "InterruptController" class
//
// User should instantiate and configure a global "satcat5::irq::Handler",
// then pass a pointer to this object. User is responsible for populating
// interrupt handlers and calling irq_handler with the handler object.
// In addition, because SatCat does not allow negative IRQ Nums
// and some IRQ Nums are negative the NVIC_USER_IRQ_OFFSET is applied
// when creating interrupt handlers. The ControllerSAMV71 will then
// revert this offset before calling NVIC API functions.
//
// Example:
//
// #include <hal_sam/interrupts.h>
// #include <hal_sam/systick_timer.h>
//
// // IRQ Controller
// extern satcat5::sam::ControllerSAMV71 irq_controller;
//
// // SysTick Timer
// extern satcat5::sam::SysTickTimer systick_timer;
//
// void SysTick_Handler()
// {
//     irq_controller.irq_handler(&systick_timer);
// }
//
//  int main(...) {
//      while (1) {satcat5::poll::service();}
//  }
//

#pragma once

//////////////////////////////////////////////////////////////////////////
// Includes
//////////////////////////////////////////////////////////////////////////

// SAMV71 Drivers
extern "C"{
    // Advanced Software Framework
    #include <asf.h>
};

// SatCat
#include <satcat5/interrupts.h>

// SatCat HAL
#include <hal_samv71/interrupt_handler.h>

//////////////////////////////////////////////////////////////////////////

namespace satcat5 {
    namespace sam {
        // Control object for registering interrupt handlers and handling
        // nested calls to atomic_start, atomic_end, etc.  Children should
        // implement the specified platform-specific methods.
        class ControllerSAMV71 : public satcat5::irq::Controller {
        public:
            // Constructor
            ControllerSAMV71();

            // Initialize SAMV71 controller and start SatCat5 interrupts.
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
    }  // namespace sam
}  // namespace satcat5

//////////////////////////////////////////////////////////////////////////
