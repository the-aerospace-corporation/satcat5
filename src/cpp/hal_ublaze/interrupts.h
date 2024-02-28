//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Xilinx Microblaze implementation of the "InterruptController" class
//
// User should instantiate and configure a global "XIntc", then pass a
// pointer to this object.  For example:
//
//  #include <hal_ublaze/interrupts.h>
//
//  XIntc irq_xilinx;
//  satcat5::irq::ControllerMicroblaze irq_satcat5(&irq_xilinx);
//
//  int main(...) {
//      irq_satcat5.hal_start(XPAR_UBLAZE_CORE_MICROBLAZE_0_AXI_INTC_DEVICE_ID);
//      while (1) {satcat5::poll::service();}
//  }
//

#pragma once

#include <satcat5/interrupts.h>
#include <xparameters.h>

// Check if BSP will include the XIntc driver before proceeding.
#if XPAR_XINTC_NUM_INSTANCES > 0

#include <xintc.h>

namespace satcat5 {
    namespace irq {
        // Control object for registering interrupt handlers and handling
        // nested calls to atomic_start, atomic_end, etc.  Children should
        // implement the specified platform-specific methods.
        class ControllerMicroblaze : public satcat5::irq::Controller {
        public:
            explicit ControllerMicroblaze(XIntc* xintc);

            // Initialize Xilinx controller and start SatCat5 interrupts.
            void irq_start(
                u16 dev_id,                             // Xilinx device-ID
                satcat5::util::GenericTimer* timer = 0, // Diagnostic timer
                u32 opts = XIN_SVC_ALL_ISRS_OPTION);    // Xilinx option flags

        protected:
            // Hardware-abstraction overrides.
            void irq_pause() override;
            void irq_resume() override;
            void irq_register(satcat5::irq::Handler* obj) override;
            void irq_unregister(satcat5::irq::Handler* obj) override;
            void irq_acknowledge(satcat5::irq::Handler* obj) override;

        private:
            XIntc* const m_xintc;
        };
    }
}

#endif  // XPAR_XINTC_NUM_INSTANCES > 0
