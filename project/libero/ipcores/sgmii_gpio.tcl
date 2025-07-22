# ------------------------------------------------------------------------
# Copyright 2025 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script creates and configures the following Microsemi IP cores to
# support SGMII I/O from a GPIO pin via port_sgmii_gpio.vhd:
#  * PF_IOD_CDR_CCC
#  * PF_IOD_CDR
#

# Microsemi IP: PF_IOD_CDR_CCC:2.1.111
create_and_configure_core \
    -core_vlnv {Actel:SystemBuilder:PF_IOD_CDR_CCC:2.1.111} \
    -component_name {PF_IOD_CDR_CCC_SGMII} \
    -params \
    { \
        "CCC_PLL_MULTIPLIER:5" \
        "CCC_PLL_REF_FREQ:125.000" \
        "DATA_RATE:1250" \
        "GENERATE_TX_FAB_CLK:true" \
        "TX_CLK_G_FREQ:125.000" \
    }

# Microsemi IP: PF_IOD_CDR:2.4.105
create_and_configure_core \
    -core_vlnv {Actel:SystemBuilder:PF_IOD_CDR:2.4.105} \
    -component_name {PF_IOD_CDR_SGMII} \
    -params \
    { \
        "CLOCK_TYPE:ASYNCHRONOUS" \
        "DATA_RATE:1250" \
        "DATA_WIDTH:9" \
        "EXPOSE_DIAGNOSTIC_PORT:false" \
        "EYE_WINDOW_N:6" \
        "EYE_WINDOW_P:5" \
        "FLAG_OFFSET_SIZE:4" \
        "JUMP_STEP_SIZE:3" \
        "LVDS_FAILSAFE_EN:false" \
        "RATIO:5" \
        "RX_BIT_SLIP_EN:false" \
        "RX_CLK_MODE:CDR4" \
        "RX_ENABLED:true" \
        "RX_ONLY:false" \
        "SIMULATION_MODE:FULL" \
        "TX_ENABLED:true" \
        "TX_TRAINING_MODE:AUTO" \
    }
