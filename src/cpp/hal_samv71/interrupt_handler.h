//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//
// This class is needed to apply NVIC_USER_IRQ_OFFSET when creating
// SAMV71 interrupt handlers. SatCat does not allow negative IRQ nums,
// and the SAMV71 has a few Ex: SysTick_IRQn. So when creating the
// Handlers NVIC_USER_IRQ_OFFSET is applied to bring this number to be
// positive. The controller uses this value to revert the offset
// when attempting to set the ISR vector for the given interrupt.

#pragma once

//////////////////////////////////////////////////////////////////////////
// Includes
//////////////////////////////////////////////////////////////////////////

// SatCat
#include <satcat5/interrupts.h>

//////////////////////////////////////////////////////////////////////////

namespace satcat5 {
    namespace sam {
        class HandlerSAMV71 : public satcat5::irq::Handler {
        public:
            explicit HandlerSAMV71(const char* lbl, int irq);
        };
    }  // namespace sam
}  // namespace satcat5

//////////////////////////////////////////////////////////////////////////
