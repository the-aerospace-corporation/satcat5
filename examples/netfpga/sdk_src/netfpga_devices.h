//////////////////////////////////////////////////////////////////////////
// Copyright 2022 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Define hardware constants relating to the NetFPGA-Managed design.

// Import definitions from the BSP.
#include <xparameters.h>

#pragma once

// ConfigBus device-addresses.
// For now, manually sync these with constants from "create_vivado.tcl".
// (We're not fancy enough to do this through the Xilinx tools yet.)
static const unsigned DEVADDR_MAILMAP   = 0;    // MailMap virtual Ethernet port
static const unsigned DEVADDR_LEDS      = 1;    // User LEDs (total 4x)
static const unsigned DEVADDR_SWSTATUS  = 2;    // Legacy status UART
static const unsigned DEVADDR_PMOD_JA   = 3;    // Ethernet-over-SPI/UART
static const unsigned DEVADDR_PMOD_JB   = 4;    // Ethernet-over-SPI/UART
static const unsigned DEVADDR_TIMER     = 5;    // Timer functions
static const unsigned DEVADDR_PTPREF    = 6;    // PTP time reference
static const unsigned DEVADDR_MDIO      = 7;    // MDIO for the Ethernet PHYs
static const unsigned DEVADDR_SWCORE    = 8;    // Switch management
static const unsigned DEVADDR_TRAFFIC   = 9;    // Traffic statistics

// TODO: Find MDIO address for each PHY (Realtek RTL8211)

// Define Ethernet port indices for switch control and statistics.
static const unsigned PORT_IDX_MAILMAP  = 0;    // Virtual port for Microblaze
static const unsigned PORT_IDX_RGMII0   = 1;    // RGMII port (RJ45)
static const unsigned PORT_IDX_RGMII1   = 2;    // RGMII port (RJ45)
static const unsigned PORT_IDX_RGMII2   = 3;    // RGMII port (RJ45)
static const unsigned PORT_IDX_RGMII3   = 4;    // RGMII port (RJ45)
static const unsigned PORT_IDX_PMOD_JA  = 5;    // SPI/UART port (PMOD)
static const unsigned PORT_IDX_PMOD_JB  = 6;    // SPI/UART port (PMOD)
