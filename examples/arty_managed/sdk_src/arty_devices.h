//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Define hardware constants relating to the "Arty-Managed" design.

// Import definitions from the BSP.
#include <xparameters.h>

#pragma once

// ConfigBus device-addresses.
// For now, manually sync these with constants from "create_vivado.tcl".
// (We're not fancy enough to do this through the Xilinx tools yet.)
static const unsigned DEVADDR_MAILMAP   = 0;    // MailMap virtual Ethernet port
static const unsigned DEVADDR_PMOD1     = 1;    // Control of each PMOD port
static const unsigned DEVADDR_PMOD2     = 2;
static const unsigned DEVADDR_PMOD3     = 3;
static const unsigned DEVADDR_PMOD4     = 4;
static const unsigned DEVADDR_SWCORE    = 5;    // Switch management
static const unsigned DEVADDR_TRAFFIC   = 6;    // Traffic statistics
static const unsigned DEVADDR_MDIO      = 7;    // MDIO for the Ethernet PHY
static const unsigned DEVADDR_LEDS      = 8;    // LEDs (total 16x)
static const unsigned DEVADDR_TIMER     = 9;    // Timer functions
static const unsigned DEVADDR_I2C       = 10;   // I2C controller
static const unsigned DEVADDR_SPI       = 11;   // SPI controller (J6)
static const unsigned DEVADDR_TFT       = 12;   // SPI controller (TFT)
static const unsigned DEVADDR_CFGSW     = 13;   // Buttons and switches

// Arty's RMII Ethernet PHY address for MDIO queries.
static const unsigned RMII_PHYADDR      = 1;

// Define Ethernet port indices for switch control and statistics.
static const unsigned PORT_IDX_MAILMAP  = 0;
static const unsigned PORT_IDX_PMOD1    = 1;
static const unsigned PORT_IDX_PMOD2    = 2;
static const unsigned PORT_IDX_PMOD3    = 3;
static const unsigned PORT_IDX_PMOD4    = 4;
static const unsigned PORT_IDX_RMII     = 5;
static const u32 PORT_MASK_MAILMAP      = (1u << PORT_IDX_MAILMAP);
static const u32 PORT_MASK_PMOD1        = (1u << PORT_IDX_PMOD1);
static const u32 PORT_MASK_PMOD2        = (1u << PORT_IDX_PMOD2);
static const u32 PORT_MASK_PMOD3        = (1u << PORT_IDX_PMOD3);
static const u32 PORT_MASK_PMOD4        = (1u << PORT_IDX_PMOD4);
static const u32 PORT_MASK_RMII         = (1u << PORT_IDX_RMII);

// LED animation parameters.
static const unsigned LED_BLU0          = 0;
static const unsigned LED_GRN0          = 1;
static const unsigned LED_RED0          = 2;
static const unsigned LED_BLU1          = 3;
static const unsigned LED_GRN1          = 4;
static const unsigned LED_RED1          = 5;
static const unsigned LED_BLU2          = 6;
static const unsigned LED_GRN2          = 7;
static const unsigned LED_RED2          = 8;
static const unsigned LED_BLU3          = 9;
static const unsigned LED_GRN3          = 10;
static const unsigned LED_RED3          = 11;
static const unsigned LED_AUX0          = 12;
static const unsigned LED_AUX1          = 13;
static const unsigned LED_AUX2          = 14;
static const unsigned LED_AUX3          = 15;
