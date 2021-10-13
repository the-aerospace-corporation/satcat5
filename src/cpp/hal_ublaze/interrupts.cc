//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
//////////////////////////////////////////////////////////////////////////
// Hardware abstraction layer for the Xilinx Microblaze interrupt handler.

#include <hal_ublaze/interrupts.h>

// Check if BSP will include the XIntc driver before proceeding.
#if XPAR_XINTC_NUM_INSTANCES > 0

satcat5::irq::ControllerMicroblaze::ControllerMicroblaze(XIntc* xintc)
    : m_xintc(xintc)
{
    // Nothing else to do at this time.
}

void satcat5::irq::ControllerMicroblaze::irq_start(
    u16 dev_id, satcat5::util::GenericTimer* timer, u32 opts)
{
    // Initialize the Xilinx interrupt controller.
    XIntc_Initialize(m_xintc, dev_id);
    XIntc_SetOptions(m_xintc, opts);

    // Initialize SatCat5 interrupt system.
    // (This also registers all interrupt-handlers.)
    init(timer);

    // Start servicing interrupts.
    XIntc_Start(m_xintc, XIN_REAL_MODE);
    microblaze_enable_interrupts();
}

void satcat5::irq::ControllerMicroblaze::irq_pause()
{
    microblaze_disable_interrupts();
}

void satcat5::irq::ControllerMicroblaze::irq_resume()
{
    microblaze_enable_interrupts();
}

void satcat5::irq::ControllerMicroblaze::irq_register(satcat5::irq::Handler* obj)
{
    XIntc_Connect(
            m_xintc,
            obj->m_irq_idx,
            (XInterruptHandler)satcat5::irq::Controller::interrupt_static,
            (void*)obj);
    XIntc_Enable(m_xintc, obj->m_irq_idx);
}

void satcat5::irq::ControllerMicroblaze::irq_unregister(satcat5::irq::Handler* obj)
{
    XIntc_Disable(m_xintc, obj->m_irq_idx);
    XIntc_Disconnect(m_xintc, obj->m_irq_idx);
}

void satcat5::irq::ControllerMicroblaze::irq_acknowledge(satcat5::irq::Handler* obj)
{
    XIntc_Acknowledge(m_xintc, obj->m_irq_idx);
}

#endif  // XPAR_XINTC_NUM_INSTANCES > 0
