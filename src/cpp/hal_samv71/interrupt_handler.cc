//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////
// Includes
//////////////////////////////////////////////////////////////////////////

// SAMV71 Drivers
extern "C" {
    // Advanced Software Framework
    #include <asf.h>
};

// SatCat
#include <satcat5/interrupts.h>

// SatCat HAL
#include <hal_samv71/interrupt_handler.h>

//////////////////////////////////////////////////////////////////////////
// Namespace
//////////////////////////////////////////////////////////////////////////

using satcat5::sam::HandlerSAMV71;
using satcat5::irq::Handler;

//////////////////////////////////////////////////////////////////////////

HandlerSAMV71::HandlerSAMV71(const char* lbl, int irq)
: Handler(lbl, irq + NVIC_USER_IRQ_OFFSET) {
    // Nothing
}

//////////////////////////////////////////////////////////////////////////
