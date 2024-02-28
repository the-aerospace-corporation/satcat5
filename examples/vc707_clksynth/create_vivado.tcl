# ------------------------------------------------------------------------
# Copyright 2022-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------

# This script creates a new Vivado project for the Xilinx VC707 dev board.
# To re-create the project, source this file in the Vivado Tcl Shell.

puts {Running create_vivado.tcl}

# Change to example project folder.
cd [file normalize [file dirname [info script]]]

# Set project-level properties depending on the selected board.
set target_part "XC7VX485TFFG1761-2"
set target_proj "vc707_clksynth"
set target_top "vc707_clksynth"
set constr_synth "vc707_synth.xdc"
set constr_impl "vc707_impl.xdc"
set override_postbit ""

# Add source files:
set files_main [list \
    "[file normalize "../../src/vhdl/common/*.vhd"]"\
    "[file normalize "../../src/vhdl/xilinx/7series_*.vhd"]"\
    "[file normalize "../../src/vhdl/xilinx/clkgen_sgmii.vhd"]"\
    "[file normalize "../../src/vhdl/xilinx/sgmii_serdes_tx.vhd"]"\
    "[file normalize "./*.vhd"]"\
]

# Run the main script.
source ../../project/vivado/shared_create.tcl

# Create the GTX IP-core and generate example design.
create_ip -name gtwizard -vendor xilinx.com -library ip -module_name gtwizard_0
set gtwizard0 [get_ips gtwizard_0]
set_property -dict [list \
    CONFIG.identical_val_tx_line_rate {6.25} \
    CONFIG.identical_val_tx_reference_clock {125.000} \
    CONFIG.identical_val_no_rx {true} \
    CONFIG.gt_val_tx_pll {CPLL} \
    CONFIG.gt0_usesharedlogic {1} \
    CONFIG.gt0_val_cpll_txout_div {1} \
    CONFIG.gt0_val_drp_clock {125} \
    CONFIG.gt0_val_tx_data_width {40} \
    CONFIG.gt0_val_decoding {None} \
    CONFIG.gt0_val_encoding {None_(MSB_First)} \
    CONFIG.gt0_val_no_rx {true} \
    CONFIG.gt0_val_tx_buffer_bypass_mode {Manual} \
    CONFIG.gt0_val_tx_int_datawidth {40} \
    CONFIG.gt0_val_tx_line_rate {6.25} \
    CONFIG.gt0_val_tx_reference_clock {125.000} \
    CONFIG.gt0_val_txbuf_en {false} \
    CONFIG.gt0_val_txoutclk_source {true} \
    CONFIG.gt0_val_tx_refclk {REFCLK0_Q0} \
    CONFIG.gt1_val {true} \
    CONFIG.gt1_val_tx_refclk {REFCLK1_Q0} \
] $gtwizard0
generate_target all $gtwizard0

# Suppress specific warnings in the Vivado GUI:
set_msg_config -suppress -id {[DRC 23-20]};         # Unspecified I/O standard
set_msg_config -suppress -id {[Netlist 29-101]};    # Netlist not ideal for floorplanning
set_msg_config -suppress -id {[Place 30-574]};      # IO/BUFG routing (CLOCK_DEDICATED_ROUTE)
set_msg_config -suppress -id {[Project 1-486]};     # Could not resolve primitive black-box
set_msg_config -suppress -id {[Timing 38-316]};     # Clock period mismatch (OOC vs synth)

# Build the newly created project:
update_compile_order -fileset sources_1
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
