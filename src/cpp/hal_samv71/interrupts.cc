//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

// SAMV71 Drivers
extern "C"{
    // Advanced Software Framework
    #include <asf.h>
};

// SatCat HAL
#include <hal_samv71/interrupts.h>
#include <hal_samv71/interrupt_handler.h>

using satcat5::irq::Handler;
using satcat5::sam::ControllerSAMV71;
using satcat5::sam::HandlerSAMV71;
using satcat5::util::TimeRef;

//////////////////////////////////////////////////////////////////////////

ControllerSAMV71::ControllerSAMV71() {
    // Nothing
}

void ControllerSAMV71::irq_start(TimeRef* timer) {
    // Initialize SatCat5 interrupt system.
    init(timer);

    // Enable interrupts globally
    cpu_irq_enable();
}

void ControllerSAMV71::irq_handler(Handler* obj) {
    satcat5::irq::Controller::interrupt_static(obj);
}

void ControllerSAMV71::irq_pause() {
    // Disable Interrupts
    cpu_irq_disable();
}

void ControllerSAMV71::irq_resume() {
    // Enable Interrupts
    cpu_irq_enable();
}

void ControllerSAMV71::irq_register(Handler* obj) {
    // Disable Interrupt
    NVIC_DisableIRQ((IRQn_Type)(obj->m_irq_idx - NVIC_USER_IRQ_OFFSET));

    // Clear Pending Interrupt
    NVIC_ClearPendingIRQ((IRQn_Type)(obj->m_irq_idx - NVIC_USER_IRQ_OFFSET));

    // Enable Interrupt
    NVIC_EnableIRQ((IRQn_Type)(obj->m_irq_idx - NVIC_USER_IRQ_OFFSET));
}

void ControllerSAMV71::irq_unregister(Handler* obj) {
    // Disable Interrupt
    NVIC_DisableIRQ((IRQn_Type)(obj->m_irq_idx - NVIC_USER_IRQ_OFFSET));

    // Clear Pending Interrupt
    NVIC_ClearPendingIRQ((IRQn_Type)(obj->m_irq_idx - NVIC_USER_IRQ_OFFSET));
}

void ControllerSAMV71::irq_acknowledge(Handler* obj) {
    // Clear Pending Interrupt
    NVIC_ClearPendingIRQ((IRQn_Type)(obj->m_irq_idx - NVIC_USER_IRQ_OFFSET));
}

//////////////////////////////////////////////////////////////////////////
