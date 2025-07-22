//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Xilinx Microblaze implementation of the "InterruptController" class

#pragma once

#include <satcat5/interrupts.h>
#include <xparameters.h>

// Check if BSP will include the XIntc driver before proceeding.
#if XPAR_XINTC_NUM_INSTANCES > 0

#include <xintc.h>

namespace satcat5 {
    namespace irq {
        //! Xilinx Microblaze implementation of the irq::Controller API.
        //! This class attaches the SatCat5 interrupt-handling system to the
        //! Xilinx-provided "XIntc" IP-core used with Microblaze CPUs.
        //!
        //! To use, instantiate and configure a global "XIntc" object, then
        //! create this adapter object and pass a pointer to the XIntc struct.
        //! This provides all necessary hooks to connect SatCat5 interrupts,
        //! which can interoperate with conventional XIntc interrupt handlers.
        //! Finally, call `irq_start` before entering the programs main loop.
        //!
        //!```
        //!  #include <hal_ublaze/interrupts.h>
        //!
        //!  XIntc irq_xilinx;
        //!  satcat5::irq::ControllerMicroblaze irq_satcat5(&irq_xilinx);
        //!
        //!  int main(...) {
        //!      irq_satcat5.irq_start(XPAR_UBLAZE_CORE_MICROBLAZE_0_AXI_INTC_DEVICE_ID);
        //!      while (1) {satcat5::poll::service();}
        //!  }
        //!```
        class ControllerMicroblaze : public satcat5::irq::Controller {
        public:
            //! Attach to the Xilinx interrupt controller.
            explicit ControllerMicroblaze(XIntc* xintc);

            //! Initialize Xilinx controller and start SatCat5 interrupts.
            void irq_start(
                u16 dev_id,                             // Xilinx device-ID
                satcat5::util::TimeRef* timer = 0,      // Diagnostic timer
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
