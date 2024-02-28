# ------------------------------------------------------------------------
# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# Generate IP-core for the "synth_mgt_from_rtc" block
#
# Vivado IP integrator has automatic discovery for simple "modules",
# but does not allow such modules to incorporate nested IP.  Instead,
# we must package and install the module as a formal IP-core.
#

# Create a basic IP-core project.
set ip_name "synth_mgt_from_rtc"
set ip_vers "1.0"
set ip_disp "Synthesize phase-locked time references"
set ip_desc "Synthesize phase-locked 1PPS and 10MHz reference signals, using an MGT and an RTC."

variable example_src [file normalize [file dirname [info script]]]
variable satcat5_prj $example_src/../../project/vivado
variable satcat5_src $example_src/../../src/vhdl
source $satcat5_prj/ipcores/ipcore_shared.tcl

# Create the underlying "Gigabit Transceiver Wizard" IP-core.
# Enable GTX lanes 16-19 in transmit-only mode at 10 Gbaud.
variable core_name gtwizard_fmc2
create_ip \
    -name gtwizard -vendor xilinx.com -library ip -version 3.6 \
    -module_name $core_name
set_property -dict [list \
    CONFIG.identical_val_no_rx {true} \
    CONFIG.identical_val_rx_reference_clock {100.000} \
    CONFIG.identical_val_tx_reference_clock {100.000} \
    CONFIG.identical_val_rx_line_rate {10} \
    CONFIG.identical_val_tx_line_rate {10} \
    CONFIG.gt_val_tx_pll {QPLL} \
    CONFIG.gt0_val {false} \
    CONFIG.gt0_val_drp_clock {80} \
    CONFIG.gt16_val {true} \
    CONFIG.gt17_val {true} \
    CONFIG.gt18_val {true} \
    CONFIG.gt19_val {true} \
    CONFIG.gt16_val_tx_refclk {REFCLK0_Q4} \
    CONFIG.gt17_val_tx_refclk {REFCLK0_Q4} \
    CONFIG.gt18_val_tx_refclk {REFCLK0_Q4} \
    CONFIG.gt19_val_tx_refclk {REFCLK0_Q4} \
    CONFIG.gt0_usesharedlogic {1} \
    CONFIG.gt0_val_txbuf_en {false} \
    CONFIG.gt0_val_port_txpcsreset {false} \
    CONFIG.gt0_val_port_txbufstatus {true} \
    CONFIG.gt0_val_port_txpmareset {false} \
    CONFIG.gt0_val_rxcomma_deten {false} \
    CONFIG.gt0_val_rx_line_rate {10} \
    CONFIG.gt0_val_tx_line_rate {10} \
    CONFIG.gt0_val_tx_data_width {80} \
    CONFIG.gt0_val_encoding {None} \
    CONFIG.gt0_val_tx_int_datawidth {40} \
    CONFIG.gt0_val_rx_reference_clock {100.000} \
    CONFIG.gt0_val_tx_reference_clock {100.000} \
    CONFIG.gt0_val_decoding {None} \
    CONFIG.gt0_val_qpll_fbdiv {100} \
    CONFIG.gt0_val_cpll_rxout_div {1} \
    CONFIG.gt0_val_cpll_txout_div {1} \
    CONFIG.gt0_val_tx_buffer_bypass_mode {Manual} \
    CONFIG.gt0_val_txdiffctrl {true} \
    CONFIG.gt0_val_txoutclk_source {true} \
    CONFIG.gt0_val_dec_mcomma_detect {false} \
    CONFIG.gt0_val_dec_pcomma_detect {false} \
    CONFIG.gt0_val_port_rxslide {false} \
    CONFIG.gt0_val_port_rxdfereset {false} \
    CONFIG.gt0_val_rxslide_mode {OFF} \
] [get_ips $core_name]
ipcore_add_xci $core_name

# Add all required source files:
ipcore_add_file $satcat5_src/common/*.vhd
ipcore_add_file $example_src/synth_mgt_wrapper.vhd
ipcore_add_top  $example_src/synth_mgt_from_rtc.vhd

# Connect I/O ports
ipcore_add_clock sys_clk_125 {} slave 125000000
ipcore_add_clock out_clk_125 {} master 125000000
ipcore_add_ptptime PtpTime rtc monitor
ipcore_add_refopt PtpRef tref false
ipcore_add_reset sys_reset_p ACTIVE_HIGH slave
ipcore_add_reset out_reset_p ACTIVE_HIGH master
ipcore_add_gpio out_detect
ipcore_add_gpio out_select
ipcore_add_clock debug1_clk {} master 125000000
ipcore_add_gpio debug1_flag
ipcore_add_gpio debug1_time
ipcore_add_clock debug2_clk {} master 125000000
ipcore_add_gpio debug2_flag
ipcore_add_gpio debug2_time
ipcore_add_cfgopt Cfg cfg

# Connect the GTX reference clock (100 MHz).
set intf [ipx::add_bus_interface GTREFCLK $ip]
set_property abstraction_type_vlnv xilinx.com:interface:diff_clock_rtl:1.0 $intf
set_property bus_type_vlnv xilinx.com:interface:diff_clock:1.0 $intf
set_property interface_mode slave $intf
set_property physical_name mgt_refclk_p [ipx::add_port_map CLK_P $intf]
set_property physical_name mgt_refclk_n [ipx::add_port_map CLK_N $intf]
set_property value 100000000 [ipx::add_bus_parameter FREQ_HZ $intf]

# Set parameters
ipcore_add_param RTC_REF_HZ long 100000000 \
    {Operating frequency for the MailMap RTC.}
ipcore_add_param DEBUG_MODE bool false \
    {Replace phase-locked outputs with simpler test patterns?}
ipcore_add_param CLOCK_MODE string auto \
    {Select clock source "auto", "ext" (external), or "sys" (system).}

# Package the IP-core.
ipcore_finished
