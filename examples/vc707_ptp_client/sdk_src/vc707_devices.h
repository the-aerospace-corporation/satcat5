//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
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
static const unsigned DEVADDR_DIP_SW    = 10;   // DIP switches, other buttons
static const unsigned DEVADDR_SYNTH     = 11;   // Reference-signal synthesis

// VC707's SGMII Ethernet PHY address for MDIO queries.
static const unsigned RJ45_PHYADDR      = 7;    // From UG885

// Button mapping for the dip switch.
static const uint32_t GPIO_DIP_MASTER = (1u << 0);  // Master/slave select
static const uint32_t GPIO_EXT_DETECT = (1u << 8);  // External clock detect
static const uint32_t GPIO_EXT_SELECT = (1u << 9);
static const uint32_t GPIO_BTN_NORTH  = (1u << 10);  // Buttons near LCD
static const uint32_t GPIO_BTN_SOUTH  = (1u << 11);
static const uint32_t GPIO_BTN_EAST   = (1u << 12);
static const uint32_t GPIO_BTN_WEST   = (1u << 13);
static const uint32_t GPIO_BTN_CENTER = (1u << 14);
static const uint32_t GPIO_ROTR_INCA  = (1u << 15); // Rotary encoder + button
static const uint32_t GPIO_ROTR_INCB  = (1u << 16);
static const uint32_t GPIO_ROTR_PUSH  = (1u << 17);

// Define Ethernet port indices for switch control and statistics.
static const unsigned PORT_IDX_MAILMAP  = 0;    // Virtual port for Microblaze
static const unsigned PORT_IDX_ETH_UART = 1;    // Ethernet-over-UART (USB)
static const unsigned PORT_IDX_ETH_RJ45 = 2;    // SGMII to the RJ45 port
static const unsigned PORT_IDX_ETH_SFP  = 3;    // SGMII to the SFP port
static const unsigned PORT_IDX_ETH_SMA  = 4;    // SGMII to the SMA ports

// Device address for the PCA9548A I2C MUX (A[2:0] = 1, 0, 0)
static const auto I2C_ADDR_MUX = satcat5::util::I2cAddr::addr7(0x74);
static const auto I2C_ADDR_SFP = satcat5::util::I2cAddr::addr7(0x50);
static const unsigned I2C_CH_USERCLK    = 0;
static const unsigned I2C_CH_FMC1       = 1;
static const unsigned I2C_CH_FMC2       = 2;
static const unsigned I2C_CH_EEPROM     = 3;
static const unsigned I2C_CH_SFP        = 4;
static const unsigned I2C_CH_HDMI       = 5;
static const unsigned I2C_CH_DDR3       = 6;
static const unsigned I2C_CH_SI5324     = 7;
