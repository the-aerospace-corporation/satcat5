//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////
// Includes
//////////////////////////////////////////////////////////////////////////

// SatCat HAL
#include <hal_freertos/interrupts.h>

//////////////////////////////////////////////////////////////////////////
// Namespace
//////////////////////////////////////////////////////////////////////////

using satcat5::freertos::ControllerFreeRTOS;
using satcat5::irq::Handler;
using satcat5::irq::Controller;

//////////////////////////////////////////////////////////////////////////

ControllerFreeRTOS::ControllerFreeRTOS() {
    // Nothing
}

void ControllerFreeRTOS::irq_start(satcat5::util::TimeRef* timer) {
    // Initialize SatCat5 interrupt system.
    init(timer);

    // Enable interrupts globally
    taskENABLE_INTERRUPTS();
}

void ControllerFreeRTOS::irq_handler(Handler* obj) {
    Controller::interrupt_static(obj);
}

void ControllerFreeRTOS::irq_pause() {
    taskDISABLE_INTERRUPTS();
}

void ControllerFreeRTOS::irq_resume() {
    taskENABLE_INTERRUPTS();
}

void ControllerFreeRTOS::irq_register(Handler* obj) {
    // Nothing
}

void ControllerFreeRTOS::irq_unregister(Handler* obj) {
    // Nothing
}

void ControllerFreeRTOS::irq_acknowledge(Handler* obj) {
    // Nothing
}

//////////////////////////////////////////////////////////////////////////
