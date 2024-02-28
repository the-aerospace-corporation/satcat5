# ------------------------------------------------------------------------
# Copyright 2021-2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This file declares a number of TCL functions.  Each function creates and
# configures one instance of a Xilinx IP-core relating to SGMII interfaces
# that use Xilinx MGT resources.
#
# To use the file, first load it using `source generate_sgmii_gtx.tcl` and
# then run any of the following functions:
#   * `generate_sgmii_gtx` instantiates the Xilinx Ethernet PCS/PMA IP core
#     for use with "src/vhdl/xilinx/port_sgmii_gtx.vhd".  This version is
#     recommended for most new designs.
#   * `generate_sgmii_raw` instantiates the Xilinx Transceiver Wizard for
#     use with src/vhdl/xilinx/port_sgmii_raw.vhd".  This version uses
#     more FPGA fabric resources, but allows better PTP timestamps
#
# The user must indicate the desired MGT location using `gtloc`, e.g., "X0Y0".
#
# For use cases with a single core, set `include_shared_logic` = 1.
# For use cases with multiple cores in the same MGT quad, additional care
# is required; see the respective VHDL wrapper for additional information.
#

proc generate_sgmii_gtx {gt_loc {core_name sgmii_gtx0} {include_shared_logic 1} {refclk_freq_mhz 125}} {
    # Clear out any previous instances with the same name.
    set old_core [get_filesets -quiet $core_name]
    if {[llength $old_core] > 0} {
        remove_files [get_files -of $old_core]
    }
    # Create the new IP core and set all parameters.
    # Note: Enable "Auto_Negotiation" or the configuration_vector port does nothing.
    create_ip -name gig_ethernet_pcs_pma -vendor xilinx.com -library ip -module_name $core_name
    set ip_obj [get_ips $core_name]
    set_property -dict [list\
        CONFIG.Auto_Negotiation     true\
        CONFIG.RefClkRate           $refclk_freq_mhz\
        CONFIG.Management_Interface false\
        CONFIG.MaxDataRate          1G\
        CONFIG.SGMII_PHY_Mode       false\
        CONFIG.Standard             SGMII\
    ] $ip_obj
    if {$include_shared_logic} {
        set_property CONFIG.SupportLevel {Include_Shared_Logic_in_Core} $ip_obj
    } else {
        set_property CONFIG.SupportLevel {Include_Shared_Logic_in_Example_Design} $ip_obj
    }
    # Some additional properties are only set if present.
    # (Depends on installed LogiCORE IP version.)
    catch {set_property CONFIG.Physical_Interface Transceiver $ip_obj}
    catch {set_property CONFIG.GT_Location $gt_loc $ip_obj}
    # Generate files for the new core.
    generate_target {instantiation_template} [get_files $core_name.xci]
    generate_target all [get_files $core_name.xci]
    catch { config_ip_cache -export $ip_obj }
    export_ip_user_files -of_objects [get_files $core_name.xci] -no_script -sync -force -quiet
    create_ip_run [get_files -of_objects [get_fileset sources_1] $core_name.xci]
    return $core_name
}

proc generate_sgmii_raw {core_name {mgt_type gtx} {refclk_freq_mhz {125.000}} {refclk_src REFCLK0_Q0}} {
    # Clear out any previous instances with the same name.
    set old_core [get_filesets -quiet $core_name]
    if {[llength $old_core] > 0} {
        remove_files [get_files -of $old_core]
    }
    # Create the new IP core and set all parameters.
    if {$mgt_type == "gtx"} {
        # 7-series GTX transceiver wizard.
        # Note: "refclk_freq_mhz" argument MUST have trailing zeros.
        create_ip -name gtwizard -vendor xilinx.com -library ip -module_name $core_name
        puts "$refclk_freq_mhz"
        set_property -dict [list\
            CONFIG.identical_val_tx_reference_clock $refclk_freq_mhz\
            CONFIG.identical_val_rx_reference_clock $refclk_freq_mhz\
            CONFIG.identical_val_tx_line_rate {2.5}\
            CONFIG.identical_val_rx_line_rate {2.5}\
            CONFIG.gt_val_tx_pll {CPLL}\
            CONFIG.gt_val_rx_pll {CPLL}\
            CONFIG.gt0_val_drp_clock {100}\
            CONFIG.gt0_val_txbuf_en {false}\
            CONFIG.gt0_val_rxbuf_en {false}\
            CONFIG.gt0_val_rxcomma_deten {false}\
            CONFIG.gt0_val_dfe_mode {LPM-Auto}\
            CONFIG.gt0_usesharedlogic 0\
            CONFIG.gt0_val_tx_line_rate {2.5}\
            CONFIG.gt0_val_tx_data_width {20}\
            CONFIG.gt0_val_tx_int_datawidth {20}\
            CONFIG.gt0_val_tx_refclk $refclk_src\
            CONFIG.gt0_val_tx_reference_clock $refclk_freq_mhz\
            CONFIG.gt0_val_rx_line_rate {2.5}\
            CONFIG.gt0_val_rx_data_width {20}\
            CONFIG.gt0_val_rx_int_datawidth {20}\
            CONFIG.gt0_val_rx_refclk $refclk_src\
            CONFIG.gt0_val_rx_reference_clock $refclk_freq_mhz\
            CONFIG.gt0_val_cpll_fbdiv_45 {5}\
            CONFIG.gt0_val_cpll_fbdiv {4}\
            CONFIG.gt0_val_tx_buffer_bypass_mode {Auto}\
            CONFIG.gt0_val_txoutclk_source {true}\
            CONFIG.gt0_val_rx_buffer_bypass_mode {Auto}\
            CONFIG.gt0_val_rxusrclk {RXOUTCLK}\
            CONFIG.gt0_val_dec_mcomma_detect {false}\
            CONFIG.gt0_val_dec_pcomma_detect {false}\
            CONFIG.gt0_val_port_rxslide {false}\
            CONFIG.gt0_val_rx_termination_voltage {Programmable}\
            CONFIG.gt0_val_rx_cm_trim {800}\
            CONFIG.gt0_val_rxslide_mode {OFF}\
        ] [get_ips $core_name]
    } elseif {$mgt_type == "gty"} {
        # Ultrascale / Ultrascale+ GTY transceiver wizard.
        create_ip -name gtwizard_ultrascale -vendor xilinx.com -library ip -module_name $core_name
        set_property -dict [list\
            CONFIG.TX_LINE_RATE {2.5}\
            CONFIG.TX_PLL_TYPE {CPLL}\
            CONFIG.TX_REFCLK_FREQUENCY $refclk_freq_mhz\
            CONFIG.TX_USER_DATA_WIDTH {20}\
            CONFIG.TX_INT_DATA_WIDTH {20}\
            CONFIG.TX_BUFFER_MODE {0}\
            CONFIG.TX_OUTCLK_SOURCE {TXPROGDIVCLK}\
            CONFIG.RX_LINE_RATE {2.5}\
            CONFIG.RX_PLL_TYPE {CPLL}\
            CONFIG.RX_REFCLK_FREQUENCY $refclk_freq_mhz\
            CONFIG.RX_USER_DATA_WIDTH {20}\
            CONFIG.RX_INT_DATA_WIDTH {20}\
            CONFIG.RX_BUFFER_MODE {0}\
            CONFIG.RX_EQ_MODE {LPM}\
            CONFIG.RX_COMMA_SHOW_REALIGN_ENABLE {false}\
            CONFIG.LOCATE_TX_BUFFER_BYPASS_CONTROLLER {CORE}\
            CONFIG.LOCATE_RX_BUFFER_BYPASS_CONTROLLER {CORE}\
            CONFIG.LOCATE_RX_USER_CLOCKING {EXAMPLE_DESIGN}\
            CONFIG.LOCATE_USER_DATA_WIDTH_SIZING {CORE}\
            CONFIG.TXPROGDIV_FREQ_SOURCE {CPLL}\
            CONFIG.TXPROGDIV_FREQ_VAL {125}\
            CONFIG.FREERUN_FREQUENCY {100}\
        ] [get_ips $core_name]
    } else {
        error "Unsupported transceiver type: $mgt_type"
    }
    # Generate files for the new core.
    generate_target {instantiation_template} [get_files $core_name.xci]
    generate_target all [get_files $core_name.xci]
    catch { config_ip_cache -export [get_ips $core_name] }
    export_ip_user_files -of_objects [get_files $core_name.xci] -no_script -sync -force -quiet
    create_ip_run [get_files -of_objects [get_fileset sources_1] $core_name.xci]
    return $core_name
}
