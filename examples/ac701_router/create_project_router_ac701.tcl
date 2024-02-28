# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script creates a new Vivado project for the Xilinx AC701 dev board,
# with an Avnet "Network FMC" card (AES-FMC-NETW1-G) installed to provide
# a total of three RGMII-based Ethernet ports.
#
# Each port has a unique subnet:
#   RGMII0 (AC701 built-in) = 192.168.15.*
#   RGMII1 (Avnet Port 1) = 192.168.16.*
#   RGMII2 (Avnet Port 2) = 192.168.17.*
#
# This project also demonstrates use of the "IP-Core" wrappers for several
# SatCat5 components, using a block diagram as the top-level.
#
# To re-create the project, source this file in the Vivado Tcl Shell.
#

# Change to example project folder.
cd [file normalize [file dirname [info script]]]

# Set project-level properties depending on the selected board.
set target_proj "router_ac701"
set target_part "xc7a200tfbg676-2"
set constr_synth "router_ac701_synth.xdc"
set constr_impl "router_ac701_impl.xdc"

# There's no source in this project except the IP-cores!
set files_main ""

# Run the main project-creation script and install IP-cores.
source ../../project/vivado/shared_create.tcl
source ../../project/vivado/shared_ipcores.tcl
set proj_dir [get_property directory [current_project]]

# Create the main block diagram.
set design_name router_ac701
create_bd_design $design_name
current_bd_design $design_name

# Top-level I/O ports
set refclk200 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 refclk200 ]
set_property CONFIG.FREQ_HZ {200000000} $refclk200
set rgmii0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:rgmii_rtl:1.0 rgmii0 ]
set rgmii1 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:rgmii_rtl:1.0 rgmii1 ]
set rgmii2 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:rgmii_rtl:1.0 rgmii2 ]
set text_lcd [ create_bd_intf_port -mode Master -vlnv aero.org:satcat5:TextLCD_rtl:1.0 text ]
set reset_p [ create_bd_port -dir I -type rst reset_p ]
set_property CONFIG.POLARITY {ACTIVE_HIGH} $reset_p
set scrub_clk [ create_bd_port -dir I -type clk scrub_clk ]
set status_uart [ create_bd_port -dir O status_uart ]
set rgmii0_rst_b [ create_bd_port -dir O -type rst rgmii0_rst_b ]
set rgmii1_rst_b [ create_bd_port -dir O -type rst rgmii1_rst_b ]
set rgmii2_rst_b [ create_bd_port -dir O -type rst rgmii2_rst_b ]

# Create hierarchical block for clock generator
set parent_obj [current_bd_instance .]
current_bd_instance [create_bd_cell -type hier clkgen]

create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 CLK_IN1_D
create_bd_pin -dir O -type clk clk125_00
create_bd_pin -dir O -type clk clk125_90
create_bd_pin -dir I -type rst reset
create_bd_pin -dir O -from 0 -to 0 -type rst resetn
create_bd_pin -dir O -from 0 -to 0 -type rst resetp

set clk_wiz_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz clk_wiz_0 ]
set_property -dict [ list \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {125} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125} \
    CONFIG.CLKOUT2_REQUESTED_PHASE {90} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {200} \
    CONFIG.CLKOUT3_USED {true} \
    CONFIG.CLK_IN1_BOARD_INTERFACE {sys_diff_clock} \
    CONFIG.NUM_OUT_CLKS {3} \
    CONFIG.PRIM_SOURCE {Differential_clock_capable_pin} \
] $clk_wiz_0

set proc_sys_reset_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0 ]

set util_idelay_ctrl_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_idelay_ctrl:1.0 util_idelay_ctrl_0 ]

connect_bd_intf_net -intf_net CLK_IN1_D_1 \
    [get_bd_intf_pins CLK_IN1_D] \
    [get_bd_intf_pins clk_wiz_0/CLK_IN1_D]
connect_bd_net -net clk_wiz_0_clk_out1 \
    [get_bd_pins clk125_00] \
    [get_bd_pins clk_wiz_0/clk_out1] \
    [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
connect_bd_net -net clk_wiz_0_clk_out2 \
    [get_bd_pins clk125_90] \
    [get_bd_pins clk_wiz_0/clk_out2]
connect_bd_net -net clk_wiz_0_clk_out3 \
    [get_bd_pins clk_wiz_0/clk_out3] \
    [get_bd_pins util_idelay_ctrl_0/ref_clk]
connect_bd_net -net clk_wiz_0_locked \
    [get_bd_pins clk_wiz_0/locked] \
    [get_bd_pins proc_sys_reset_0/dcm_locked]
connect_bd_net -net proc_sys_reset_0_peripheral_aresetn \
    [get_bd_pins resetn] \
    [get_bd_pins proc_sys_reset_0/peripheral_aresetn]
connect_bd_net -net proc_sys_reset_0_peripheral_reset \
    [get_bd_pins resetp] \
    [get_bd_pins proc_sys_reset_0/peripheral_reset]
connect_bd_net -net reset_1 \
    [get_bd_pins reset] \
    [get_bd_pins clk_wiz_0/reset] \
    [get_bd_pins proc_sys_reset_0/ext_reset_in] \
    [get_bd_pins util_idelay_ctrl_0/rst]

regenerate_bd_layout -hierarchy [get_bd_cells /clkgen]
current_bd_instance $parent_obj

# Create and configure each of the SatCat5 IP blocks.
set port_rgmii_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_rgmii:1.0 port_rgmii_0 ]
set_property CONFIG.RXCLK_DELAY {0} $port_rgmii_0
set_property CONFIG.RXDAT_DELAY {2000} $port_rgmii_0
set port_rgmii_1 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_rgmii:1.0 port_rgmii_1 ]
set_property CONFIG.RXCLK_DELAY {0} $port_rgmii_1
set_property CONFIG.RXDAT_DELAY {2000} $port_rgmii_1
set port_rgmii_2 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_rgmii:1.0 port_rgmii_2 ]
set_property CONFIG.RXCLK_DELAY {0} $port_rgmii_2
set_property CONFIG.RXDAT_DELAY {2000} $port_rgmii_2
set router_inline_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:router_inline:1.0 router_inline_0 ]
set_property CONFIG.STATIC_CONFIG {1} $router_inline_0
set_property CONFIG.STATIC_IPADDR {0xC0A80F01} $router_inline_0
set_property CONFIG.STATIC_SUBADDR {0xC0A80F00} $router_inline_0
set_property CONFIG.ROUTER_MACADDR {0x5ADEADBEEF0F} $router_inline_0
set_property CONFIG.SUBNET_IS_LCL_PORT {0} $router_inline_0
set router_inline_1 [ create_bd_cell -type ip -vlnv aero.org:satcat5:router_inline:1.0 router_inline_1 ]
set_property CONFIG.STATIC_CONFIG {1} $router_inline_1
set_property CONFIG.STATIC_IPADDR {0xC0A81001} $router_inline_1
set_property CONFIG.STATIC_SUBADDR {0xC0A81000} $router_inline_1
set_property CONFIG.ROUTER_MACADDR {0x5ADEADBEEF10} $router_inline_1
set_property CONFIG.SUBNET_IS_LCL_PORT {0} $router_inline_1
set router_inline_2 [ create_bd_cell -type ip -vlnv aero.org:satcat5:router_inline:1.0 router_inline_2 ]
set_property CONFIG.STATIC_CONFIG {1} $router_inline_2
set_property CONFIG.STATIC_IPADDR {0xC0A81101} $router_inline_2
set_property CONFIG.STATIC_SUBADDR {0xC0A81100} $router_inline_2
set_property CONFIG.ROUTER_MACADDR {0x5ADEADBEEF11} $router_inline_2
set_property CONFIG.SUBNET_IS_LCL_PORT {0} $router_inline_2
set switch_aux_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:switch_aux:1.0 switch_aux_0 ]
set switch_core_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:switch_core:1.0 switch_core_0 ]

# Create interface and port connections
# TODO: RGMII0 isn't working. Receives OK but can't send?
connect_bd_intf_net -intf_net refclk200 \
    [get_bd_intf_ports refclk200] \
    [get_bd_intf_pins clkgen/CLK_IN1_D]
connect_bd_intf_net \
    [get_bd_intf_pins port_rgmii_0/Eth] \
    [get_bd_intf_pins router_inline_0/NetPort]
connect_bd_intf_net \
    [get_bd_intf_pins router_inline_0/LocalPort] \
    [get_bd_intf_pins switch_core_0/Port00]
connect_bd_intf_net \
    [get_bd_intf_pins port_rgmii_1/Eth] \
    [get_bd_intf_pins router_inline_1/NetPort]
connect_bd_intf_net \
    [get_bd_intf_pins router_inline_1/LocalPort] \
    [get_bd_intf_pins switch_core_0/Port01]
connect_bd_intf_net \
    [get_bd_intf_pins port_rgmii_2/Eth] \
    [get_bd_intf_pins router_inline_2/NetPort]
connect_bd_intf_net \
    [get_bd_intf_pins router_inline_2/LocalPort] \
    [get_bd_intf_pins switch_core_0/Port02]
connect_bd_intf_net -intf_net port_rgmii0 \
    [get_bd_intf_ports rgmii0] \
    [get_bd_intf_pins port_rgmii_0/RGMII]
connect_bd_intf_net -intf_net port_rgmii1 \
    [get_bd_intf_ports rgmii1] \
    [get_bd_intf_pins port_rgmii_1/RGMII]
connect_bd_intf_net -intf_net port_rgmii2 \
    [get_bd_intf_ports rgmii2] \
    [get_bd_intf_pins port_rgmii_2/RGMII]
connect_bd_intf_net -intf_net text_lcd \
    [get_bd_intf_ports text] \
    [get_bd_intf_pins switch_aux_0/text_lcd]
connect_bd_net -net clk_125_00 \
    [get_bd_pins clkgen/clk125_00] \
    [get_bd_pins port_rgmii_0/clk_125] \
    [get_bd_pins port_rgmii_1/clk_125] \
    [get_bd_pins port_rgmii_2/clk_125] \
    [get_bd_pins switch_core_0/core_clk]
connect_bd_net -net clk_125_90 \
    [get_bd_pins clkgen/clk125_90] \
    [get_bd_pins port_rgmii_0/clk_txc] \
    [get_bd_pins port_rgmii_1/clk_txc] \
    [get_bd_pins port_rgmii_2/clk_txc]
connect_bd_net -net gen_reset_n \
    [get_bd_pins clkgen/resetn] \
    [get_bd_ports rgmii0_rst_b] \
    [get_bd_ports rgmii1_rst_b] \
    [get_bd_ports rgmii2_rst_b]
connect_bd_net -net gen_reset_p \
    [get_bd_pins clkgen/resetp] \
    [get_bd_pins port_rgmii_0/reset_p] \
    [get_bd_pins port_rgmii_1/reset_p] \
    [get_bd_pins port_rgmii_2/reset_p] \
    [get_bd_pins router_inline_0/reset_p] \
    [get_bd_pins router_inline_1/reset_p] \
    [get_bd_pins router_inline_2/reset_p] \
    [get_bd_pins switch_core_0/reset_p]
connect_bd_net -net ext_reset_p \
    [get_bd_ports reset_p] \
    [get_bd_pins clkgen/reset] \
    [get_bd_pins switch_aux_0/reset_p]
connect_bd_net -net scrub_clk \
    [get_bd_ports scrub_clk] \
    [get_bd_pins switch_aux_0/scrub_clk]
connect_bd_net -net scrub_req \
    [get_bd_pins switch_aux_0/scrub_req_t] \
    [get_bd_pins switch_core_0/scrub_req_t]
connect_bd_net -net status_uart \
    [get_bd_ports status_uart] \
    [get_bd_pins switch_aux_0/status_uart]
connect_bd_net -net errvec \
    [get_bd_pins switch_aux_0/errvec_00] \
    [get_bd_pins switch_core_0/errvec_t]

# Cleanup
regenerate_bd_layout
save_bd_design
validate_bd_design

# Export block design in PDF and SVG form.
source ../../project/vivado/export_bd_image.tcl

# Suppress specific warnings in the Vivado GUI:
set_msg_config -suppress -id {[Project 1-486]}
set_msg_config -suppress -id {[Synth 8-506]}
set_msg_config -suppress -id {[Synth 8-3331]}
set_msg_config -suppress -id {[Synth 8-3332]}
set_msg_config -suppress -id {[Synth 8-3919]}
set_msg_config -suppress -id {[Place 30-574]}
set_msg_config -suppress -id {[DRC 23-20]}

# Create block-diagram wrapper and set as top level.
set wrapper [make_wrapper -files [get_files ${design_name}.bd] -top]
add_files -norecurse $wrapper
set_property "top" router_ac701_wrapper [get_filesets sources_1]

# Execute the build and write out the .bin file.
source ../../project/vivado/shared_build.tcl
satcat5_launch_run
satcat5_write_bin router_ac701_wrapper.bin
