# ------------------------------------------------------------------------
# Copyright 2025 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script creates and configures the following Microsemi IP cores to
# support SGMII I/O from a transceiver pin via port_sgmii_raw.vhd:
#  * PF_XCVR_REF_CLK
#  * PF_TX_PLL
#  * PF_XCVR_ERM
#

# Microsemi IP: PF_XCVR_REF_CLK:1.0.103
create_and_configure_core \
    -core_vlnv {Actel:SgCore:PF_XCVR_REF_CLK:1.0.103} \
    -component_name {PF_XCVR_REF_CLK_SGMII} \
    -params \
    { \
        "ENABLE_FAB_CLK_0:false" \
        "ENABLE_FAB_CLK_1:false" \
        "ENABLE_REF_CLK_0:true" \
        "ENABLE_REF_CLK_1:false" \
        "REF_CLK_MODE_0:DIFFERENTIAL" \
        "REF_CLK_MODE_1:LVCMOS" \
    }

# Microsemi IP: PF_TX_PLL:2.0.304
create_and_configure_core \
    -core_vlnv {Actel:SgCore:PF_TX_PLL:2.0.304} \
    -component_name {PF_TX_PLL_SGMII} \
    -params \
    { \
        "CORE:PF_TX_PLL" \
        "INIT:0x0" \
        "TxPLL_AUX_LOW_SEL:true" \
        "TxPLL_AUX_OUT:125" \
        "TxPLL_BANDWIDTH:Low" \
        "TxPLL_CLK_125_EN:true" \
        "TxPLL_DYNAMIC_RECONFIG_INTERFACE_EN:false" \
        "TxPLL_EXT_WAVE_SEL:0" \
        "TxPLL_FAB_LOCK_EN:false" \
        "TxPLL_FAB_REF:200" \
        "TxPLL_INTEGER_MODE:false" \
        "TxPLL_JITTER_MODE_AT_POWERUP:true" \
        "TxPLL_JITTER_MODE_CUT_OFF_FREQ:5000" \
        "TxPLL_JITTER_MODE_OPTIMIZE_FOR:0" \
        "TxPLL_JITTER_MODE_REFCLK_FREQ:125" \
        "TxPLL_JITTER_MODE_REFCLK_SEL:DEDICATED" \
        "TxPLL_JITTER_MODE_SEL:10G SyncE 32Bit" \
        "TxPLL_JITTER_MODE_WANDER:15" \
        "TxPLL_LANE_ALIGNMENT_EN:false" \
        "TxPLL_MODE:NORMAL" \
        "TxPLL_OUT:2500.000" \
        "TxPLL_REF:125.00" \
        "TxPLL_RN_FILTER:false" \
        "TxPLL_SOURCE:DEDICATED" \
        "TxPLL_SSM_DEPTH:0" \
        "TxPLL_SSM_DIVVAL:1" \
        "TxPLL_SSM_DOWN_SPREAD:false" \
        "TxPLL_SSM_FREQ:64" \
        "TxPLL_SSM_RAND_PATTERN:0" \
        "VCOFREQUENCY:1600" \
    }

# Microsemi IP: PF_XCVR_ERM:3.1.205
create_and_configure_core \
    -core_vlnv {Actel:SystemBuilder:PF_XCVR_ERM:3.1.205} \
    -component_name {PF_XCVR_ERM_SGMII} \
    -params \
    { \
        "EXPOSE_ALL_DEBUG_PORTS:false" \
        "EXPOSE_FWF_EN_PORTS:false" \
        "SHOW_UNIVERSAL_SOLN_PORTS:true" \
        "UI_CDR_LOCK_MODE:Lock to data" \
        "UI_CDR_REFERENCE_CLK_FREQ:125.0" \
        "UI_CDR_REFERENCE_CLK_SOURCE:Dedicated" \
        "UI_CDR_REFERENCE_CLK_TOLERANCE:1" \
        "UI_ENABLE_32BIT_DATA_WIDTH:false" \
        "UI_ENABLE_64B66B:true" \
        "UI_ENABLE_64B67B:false" \
        "UI_ENABLE_64B6XB_MODE:false" \
        "UI_ENABLE_8B10B_MODE:false" \
        "UI_ENABLE_BER:false" \
        "UI_ENABLE_DISPARITY:false" \
        "UI_ENABLE_FIBRE_CHANNEL_DISPARITY:false" \
        "UI_ENABLE_PHASE_COMP_MODE:false" \
        "UI_ENABLE_PIPE_MODE:false" \
        "UI_ENABLE_PMA_MODE:true" \
        "UI_ENABLE_SCRAMBLING:false" \
        "UI_ENABLE_SWITCH_BETWEEN_CDR_REFCLKS:false" \
        "UI_ENABLE_SWITCH_BETWEEN_TXPLLS:false" \
        "UI_EXPOSE_APBLINK_PORTS:false" \
        "UI_EXPOSE_CDR_BITSLIP_PORT:true" \
        "UI_EXPOSE_DYNAMIC_RECONFIGURATION_PORTS:false" \
        "UI_EXPOSE_JA_CLOCK_PORT:false" \
        "UI_EXPOSE_RX_READY_VAL_CDR_PORT:false" \
        "UI_EXPOSE_TX_BYPASS_DATA:false" \
        "UI_EXPOSE_TX_ELEC_IDLE:true" \
        "UI_INTERFACE_RXCLOCK:Regional" \
        "UI_INTERFACE_TXCLOCK:Regional" \
        "UI_IS_CONFIGURED:true" \
        "UI_NUMBER_OF_LANES:1" \
        "UI_PCS_ARST_N:RX Only" \
        "UI_PIPE_PROTOCOL_USED:PCIe Gen1 (2.5 Gbps)" \
        "UI_PMA_ARST_N:TX and RX PMA" \
        "UI_PROTOCOL_PRESET_USED:None" \
        "UI_RX_DATA_RATE:1250" \
        "UI_RX_PCS_FAB_IF_WIDTH:10" \
        "UI_SATA_IDLE_BURST_TIMING:MAC" \
        "UI_TX_CLK_DIV_FACTOR:4" \
        "UI_TX_DATA_RATE:1250" \
        "UI_TX_PCS_FAB_IF_WIDTH:10" \
        "UI_TX_RX_MODE:Duplex" \
        "UI_USE_INTERFACE_CLK_AS_PLL_REFCLK:false" \
        "UI_XCVR_RX_CALIBRATION:None (CDR)" \
        "UI_XCVR_RX_DATA_EYE_CALIBRATION:false" \
        "UI_XCVR_RX_DFE_COEFF_CALIBRATION:false" \
        "UI_XCVR_RX_ENHANCED_MANAGEMENT:true" \
        "XT_ES_DEVICE:false" \
    }
