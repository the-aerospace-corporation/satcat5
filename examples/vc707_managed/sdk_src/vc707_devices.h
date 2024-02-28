//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2022 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Define hardware constants relating to the "VC707-Managed" design.

// Import definitions from the BSP.
#include <xparameters.h>

#pragma once

// ConfigBus device-addresses.
// For now, manually sync these with constants from "create_vivado.tcl".
// (We're not fancy enough to do this through the Xilinx tools yet.)
static const unsigned DEVADDR_SWCORE    = 0;    // Switch management
static const unsigned DEVADDR_TRAFFIC   = 1;    // Traffic statistics
static const unsigned DEVADDR_MAILMAP   = 2;    // MailMap virtual Ethernet port
static const unsigned DEVADDR_ETH_UART  = 3;    // Configure Ethernet-over-UART
static const unsigned DEVADDR_I2C_SFP   = 4;    // I2C interface to SFP module
static const unsigned DEVADDR_TIMER     = 5;    // Timer functions
static const unsigned DEVADDR_MDIO      = 6;    // MDIO for the Ethernet PHY
static const unsigned DEVADDR_LEDS      = 7;    // User LEDs (total 8x)
static const unsigned DEVADDR_SWSTATUS  = 8;    // Legacy status UART
static const unsigned DEVADDR_TEXTLCD   = 9;    // Two-line LCD display

// VC707's SGMII Ethernet PHY address for MDIO queries.
static const unsigned RJ45_PHYADDR      = 7;    // From UG885

// Define Ethernet port indices for switch control and statistics.
static const unsigned PORT_IDX_MAILMAP  = 0;    // Virtual port for Microblaze
static const unsigned PORT_IDX_ETH_UART = 1;    // Ethernet-over-UART (USB)
static const unsigned PORT_IDX_ETH_SFP  = 2;    // SGMII to the SFP port
static const unsigned PORT_IDX_ETH_RJ45 = 3;    // SGMII to the RJ45 port
static const u32 PORT_MASK_MAILMAP      = (1u << PORT_IDX_MAILMAP);
static const u32 PORT_MASK_ETH_UART     = (1u << PORT_IDX_ETH_UART);
static const u32 PORT_MASK_ETH_SFP      = (1u << PORT_IDX_ETH_SFP);
static const u32 PORT_MASK_ETH_RJ45     = (1u << PORT_IDX_ETH_RJ45);
