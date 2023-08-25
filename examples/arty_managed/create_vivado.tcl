# ------------------------------------------------------------------------
# Copyright 2021, 2022, 2023 The Aerospace Corporation
#
# This file is part of SatCat5.
#
# SatCat5 is free software: you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# SatCat5 is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
# License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
# ------------------------------------------------------------------------
#
# This script creates a new Vivado project for the Digilent Arty A7,
# with a block diagram as the top level (i.e., using packaged IP-cores).
# To re-create the project, source this file in the Vivado Tcl Shell.

puts {Running create_vivado.tcl}

# USER picks one of the Arty board options (35t or 100t), or default to 35t.
# (Pass with -tclargs in batch mode or "set argv" in GUI mode.)
if {[llength $argv] == 1} {
    set BOARD_OPTION [string tolower [lindex $argv 0]]
} else {
    set BOARD_OPTION "35t"
}

set VALID_BOARDS [list "35t" "100t"]
if {($BOARD_OPTION in $VALID_BOARDS)} {
    puts "Targeting Arty Artix7-$BOARD_OPTION"
} else {
    error "Must choose BOARD_OPTION from [list $VALID_BOARDS]"
}

# Enable additional features on the 100T build only.
# (35T doesn't have enough slices to enable every option.)
if {$BOARD_OPTION == "100t"} {
    set HBUF_KBYTES {2}
    set MAC_TABLE_SIZE {64}
    set PTP_MIXED_STEP {true}
} else {
    set HBUF_KBYTES {0}
    set MAC_TABLE_SIZE {32}
    set PTP_MIXED_STEP {false}
}

# Change to example project folder.
cd [file normalize [file dirname [info script]]]

# Set project-level properties depending on the selected board.
set target_proj "arty_managed_$BOARD_OPTION"
set constr_synth "arty_managed_synth.xdc"
set constr_impl "arty_managed_impl.xdc"
set override_postbit ""
set bin_config [list SPIx4, 16]
if {[string equal $BOARD_OPTION "100t"]} {
    set target_part "XC7A100TCSG324-1"
} elseif {[string equal $BOARD_OPTION "35t"]} {
    set target_part "XC7A35TICSG324-1L"
} else {
    error "Must choose BOARD_OPTION from 35t 100t"
}
puts "Targeting Arty Artix7-$BOARD_OPTION"

# There's no source in this project except the IP-cores!
set files_main ""

# Run the main project-creation script and install IP-cores.
source ../../project/vivado/shared_create.tcl
source ../../project/vivado/shared_ipcores.tcl
set proj_dir [get_property directory [current_project]]

# Create the block diagram
set design_name arty_managed
create_bd_design $design_name
current_bd_design $design_name

# Top-level I/O ports
set ext_clk100 [ create_bd_port -dir I -type clk ext_clk100 ]
set_property CONFIG.FREQ_HZ {100000000} $ext_clk100
set ext_reset_n [ create_bd_port -dir I -type rst ext_reset_n ]
set_property CONFIG.POLARITY {ACTIVE_LOW} $ext_reset_n
set uart_rxd [ create_bd_port -dir I uart_rxd ]
set uart_txd [ create_bd_port -dir O uart_txd ]
set rmii [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:rmii_rtl:1.0 rmii ]
set rmii_clkout [ create_bd_port -dir O rmii_clkout ]
set rmii_mode [ create_bd_port -dir O rmii_mode ]
set rmii_resetn [ create_bd_port -dir O rmii_resetn ]
set mdio_clk [ create_bd_port -dir O mdio_clk ]
set mdio_data [ create_bd_port -dir IO mdio_data ]
set i2c_sck [ create_bd_port -dir IO i2c_sck ]
set i2c_sda [ create_bd_port -dir IO i2c_sda ]
set leds [ create_bd_port -dir O -from 15 -to 0 leds ]
set pmod1 [ create_bd_port -dir IO -from 3 -to 0 pmod1 ]
set pmod2 [ create_bd_port -dir IO -from 3 -to 0 pmod2 ]
set pmod3 [ create_bd_port -dir IO -from 3 -to 0 pmod3 ]
set pmod4 [ create_bd_port -dir IO -from 3 -to 0 pmod4 ]
set spi_csb [ create_bd_port -dir O spi_csb ]
set spi_sck [ create_bd_port -dir O spi_sck ]
set spi_sdi [ create_bd_port -dir I spi_sdi ]
set spi_sdo [ create_bd_port -dir O spi_sdo ]
set text_lcd [ create_bd_intf_port -mode Master -vlnv aero.org:satcat5:TextLCD_rtl:1.0 text ]

# Hierarchical cell: ublaze/mem
current_bd_instance [create_bd_cell -type hier ublaze]
current_bd_instance [create_bd_cell -type hier ublaze_mem]

create_bd_intf_pin -mode MirroredMaster -vlnv xilinx.com:interface:lmb_rtl:1.0 DLMB
create_bd_intf_pin -mode MirroredMaster -vlnv xilinx.com:interface:lmb_rtl:1.0 ILMB
create_bd_pin -dir I -type clk Clk
create_bd_pin -dir I -type rst SYS_Rst

set dlmb_bram_if_cntlr [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr dlmb_bram_if_cntlr ]
set_property -dict [ list \
    CONFIG.C_ECC {0} \
] $dlmb_bram_if_cntlr

set dlmb_v10 [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10 dlmb_v10 ]

set ilmb_bram_if_cntlr [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr ilmb_bram_if_cntlr ]
set_property -dict [ list \
    CONFIG.C_ECC {0} \
] $ilmb_bram_if_cntlr

set ilmb_v10 [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10 ilmb_v10 ]

set lmb_bram [ create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen lmb_bram ]
set_property -dict [ list \
    CONFIG.Memory_Type {True_Dual_Port_RAM} \
    CONFIG.use_bram_block {BRAM_Controller} \
] $lmb_bram

connect_bd_intf_net -intf_net microblaze_0_dlmb [get_bd_intf_pins DLMB] [get_bd_intf_pins dlmb_v10/LMB_M]
connect_bd_intf_net -intf_net microblaze_0_dlmb_bus [get_bd_intf_pins dlmb_bram_if_cntlr/SLMB] [get_bd_intf_pins dlmb_v10/LMB_Sl_0]
connect_bd_intf_net -intf_net microblaze_0_dlmb_cntlr [get_bd_intf_pins dlmb_bram_if_cntlr/BRAM_PORT] [get_bd_intf_pins lmb_bram/BRAM_PORTA]
connect_bd_intf_net -intf_net microblaze_0_ilmb [get_bd_intf_pins ILMB] [get_bd_intf_pins ilmb_v10/LMB_M]
connect_bd_intf_net -intf_net microblaze_0_ilmb_bus [get_bd_intf_pins ilmb_bram_if_cntlr/SLMB] [get_bd_intf_pins ilmb_v10/LMB_Sl_0]
connect_bd_intf_net -intf_net microblaze_0_ilmb_cntlr [get_bd_intf_pins ilmb_bram_if_cntlr/BRAM_PORT] [get_bd_intf_pins lmb_bram/BRAM_PORTB]

connect_bd_net -net SYS_Rst_1 [get_bd_pins SYS_Rst] \
    [get_bd_pins dlmb_bram_if_cntlr/LMB_Rst] \
    [get_bd_pins dlmb_v10/SYS_Rst] \
    [get_bd_pins ilmb_bram_if_cntlr/LMB_Rst] \
    [get_bd_pins ilmb_v10/SYS_Rst]
connect_bd_net -net microblaze_0_Clk [get_bd_pins Clk] \
    [get_bd_pins dlmb_bram_if_cntlr/LMB_Clk] \
    [get_bd_pins dlmb_v10/LMB_Clk] \
    [get_bd_pins ilmb_bram_if_cntlr/LMB_Clk] \
    [get_bd_pins ilmb_v10/LMB_Clk]

# Hierarchical cell: ublaze
current_bd_instance ..

create_bd_intf_pin -mode Master -vlnv aero.org:satcat5:ConfigBus_rtl:1.0 CfgBus
create_bd_pin -dir O -type clk clk50
create_bd_pin -dir O -type clk clk100
create_bd_pin -dir I -type clk ext_clk100
create_bd_pin -dir I -type rst ext_reset_n
create_bd_pin -dir O -from 0 -to 0 -type rst resetp
create_bd_pin -dir I uart_rxd
create_bd_pin -dir O uart_txd

set axi_crossbar_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_crossbar axi_crossbar_0 ]
set_property -dict [ list \
    CONFIG.NUM_MI {3} \
] $axi_crossbar_0

set axi_uart16550_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uart16550 axi_uart16550_0 ]

set cfgbus_host_axi_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_host_axi cfgbus_host_axi_0 ]

set clk_wiz_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz clk_wiz_0 ]
set_property -dict [ list \
    CONFIG.CLKOUT1_DRIVES {BUFG} \
    CONFIG.CLKOUT2_DRIVES {BUFG} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {50} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.MMCM_CLKOUT1_DIVIDE {20} \
    CONFIG.NUM_OUT_CLKS {2} \
    CONFIG.RESET_PORT {resetn} \
    CONFIG.RESET_TYPE {ACTIVE_LOW} \
    CONFIG.USE_PHASE_ALIGNMENT {false} \
] $clk_wiz_0

set mdm_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:mdm mdm_1 ]

set microblaze_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze microblaze_0 ]
set_property -dict [ list \
    CONFIG.C_DEBUG_ENABLED {1} \
    CONFIG.C_D_AXI {1} \
    CONFIG.C_D_LMB {1} \
    CONFIG.C_I_LMB {1} \
    CONFIG.C_USE_BARREL {1} \
    CONFIG.C_USE_DIV {1} \
    CONFIG.C_USE_HW_MUL {2} \
] $microblaze_0

set microblaze_0_axi_intc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc microblaze_0_axi_intc ]
set_property -dict [ list \
    CONFIG.C_HAS_FAST {1} \
] $microblaze_0_axi_intc

set ublaze_reset [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset ublaze_reset ]

set xlconcat_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat xlconcat_0 ]

connect_bd_intf_net -intf_net CfgOut [get_bd_intf_pins CfgBus] [get_bd_intf_pins cfgbus_host_axi_0/Cfg]
connect_bd_intf_net -intf_net axi_crossbar_0_M00_AXI [get_bd_intf_pins axi_crossbar_0/M00_AXI] [get_bd_intf_pins microblaze_0_axi_intc/s_axi]
connect_bd_intf_net -intf_net axi_crossbar_0_M01_AXI [get_bd_intf_pins axi_crossbar_0/M01_AXI] [get_bd_intf_pins axi_uart16550_0/S_AXI]
connect_bd_intf_net -intf_net axi_crossbar_0_M02_AXI [get_bd_intf_pins axi_crossbar_0/M02_AXI] [get_bd_intf_pins cfgbus_host_axi_0/CtrlAxi]
connect_bd_intf_net -intf_net microblaze_0_M_AXI_DP [get_bd_intf_pins axi_crossbar_0/S00_AXI] [get_bd_intf_pins microblaze_0/M_AXI_DP]
connect_bd_intf_net -intf_net microblaze_0_debug [get_bd_intf_pins mdm_1/MBDEBUG_0] [get_bd_intf_pins microblaze_0/DEBUG]
connect_bd_intf_net -intf_net microblaze_0_dlmb_1 [get_bd_intf_pins microblaze_0/DLMB] [get_bd_intf_pins ublaze_mem/DLMB]
connect_bd_intf_net -intf_net microblaze_0_ilmb_1 [get_bd_intf_pins microblaze_0/ILMB] [get_bd_intf_pins ublaze_mem/ILMB]
connect_bd_intf_net -intf_net microblaze_0_interrupt [get_bd_intf_pins microblaze_0/INTERRUPT] [get_bd_intf_pins microblaze_0_axi_intc/interrupt]

connect_bd_net -net axi_uart16550_0_ip2intc_irpt [get_bd_pins axi_uart16550_0/ip2intc_irpt] [get_bd_pins xlconcat_0/In0]
connect_bd_net -net axi_uart16550_0_sout [get_bd_pins uart_txd] [get_bd_pins axi_uart16550_0/sout]
connect_bd_net -net cfgbus_host_axi_0_irq_out [get_bd_pins cfgbus_host_axi_0/irq_out] [get_bd_pins xlconcat_0/In1]
connect_bd_net -net clk_wiz_0_clk_out2 [get_bd_pins clk50] [get_bd_pins clk_wiz_0/clk_out2]
connect_bd_net -net clk_wiz_0_locked [get_bd_pins clk_wiz_0/locked] [get_bd_pins ublaze_reset/dcm_locked]
connect_bd_net -net ext_clk100_1 [get_bd_pins ext_clk100] [get_bd_pins clk_wiz_0/clk_in1]
connect_bd_net -net ext_reset_n_1 [get_bd_pins ext_reset_n] [get_bd_pins clk_wiz_0/resetn] [get_bd_pins ublaze_reset/ext_reset_in]
connect_bd_net -net mdm_1_debug_sys_rst [get_bd_pins mdm_1/Debug_SYS_Rst] [get_bd_pins ublaze_reset/mb_debug_sys_rst]
connect_bd_net -net microblaze_0_Clk [get_bd_pins clk100] \
    [get_bd_pins axi_crossbar_0/aclk] \
    [get_bd_pins axi_uart16550_0/s_axi_aclk] \
    [get_bd_pins cfgbus_host_axi_0/axi_clk] \
    [get_bd_pins clk_wiz_0/clk_out1] \
    [get_bd_pins microblaze_0/Clk] \
    [get_bd_pins microblaze_0_axi_intc/processor_clk] \
    [get_bd_pins microblaze_0_axi_intc/s_axi_aclk] \
    [get_bd_pins ublaze_mem/Clk] \
    [get_bd_pins ublaze_reset/slowest_sync_clk]
connect_bd_net -net rst_Clk_100M_bus_struct_reset [get_bd_pins ublaze_mem/SYS_Rst] [get_bd_pins ublaze_reset/bus_struct_reset]
connect_bd_net -net rst_Clk_100M_mb_reset [get_bd_pins microblaze_0/Reset] \
    [get_bd_pins microblaze_0_axi_intc/processor_rst] \
    [get_bd_pins ublaze_reset/mb_reset]
connect_bd_net -net rst_Clk_100M_peripheral_aresetn [get_bd_pins axi_crossbar_0/aresetn] \
    [get_bd_pins axi_uart16550_0/s_axi_aresetn] \
    [get_bd_pins cfgbus_host_axi_0/axi_aresetn] \
    [get_bd_pins microblaze_0_axi_intc/s_axi_aresetn] \
    [get_bd_pins ublaze_reset/peripheral_aresetn]
connect_bd_net -net rst_Clk_100M_peripheral_reset [get_bd_pins resetp] [get_bd_pins ublaze_reset/peripheral_reset]
connect_bd_net -net uart_rxd_1 [get_bd_pins uart_rxd] [get_bd_pins axi_uart16550_0/sin]
connect_bd_net -net xlconcat_0_dout [get_bd_pins microblaze_0_axi_intc/intr] [get_bd_pins xlconcat_0/dout]

# Create and connect top-level
# Note: ConfigBus DEV_ADDR fields are assigned sequentially.
current_bd_instance ..

set cfgbus_split_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_split cfgbus_split_0 ]
set_property -dict [ list \
    CONFIG.PORT_COUNT {11} \
] $cfgbus_split_0

set port_mailmap_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_mailmap port_mailmap_0 ]
set_property -dict [ list \
    CONFIG.DEV_ADDR {0} \
    CONFIG.PTP_ENABLE {true} \
    CONFIG.PTP_REF_HZ {100000000} \
] $port_mailmap_0

set pmod1 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_serial_auto pmod1 ]
set_property -dict [ list \
    CONFIG.CFG_DEV_ADDR {1} \
    CONFIG.CFG_ENABLE {true} \
] $pmod1

set pmod2 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_serial_auto pmod2 ]
set_property -dict [ list \
    CONFIG.CFG_DEV_ADDR {2} \
    CONFIG.CFG_ENABLE {true} \
] $pmod2

set pmod3 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_serial_auto pmod3 ]
set_property -dict [ list \
    CONFIG.CFG_DEV_ADDR {3} \
    CONFIG.CFG_ENABLE {true} \
] $pmod3

set pmod4 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_serial_auto pmod4 ]
set_property -dict [ list \
    CONFIG.CFG_DEV_ADDR {4} \
    CONFIG.CFG_ENABLE {true} \
] $pmod4

set switch_core_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:switch_core switch_core_0 ]
set_property -dict [ list \
    CONFIG.ALLOW_PRECOMMIT {true} \
    CONFIG.ALLOW_RUNT {true} \
    CONFIG.CFG_DEV_ADDR {5} \
    CONFIG.CFG_ENABLE {true} \
    CONFIG.CORE_CLK_HZ {100000000} \
    CONFIG.DATAPATH_BYTES {1} \
    CONFIG.HBUF_KBYTES $HBUF_KBYTES \
    CONFIG.MAC_TABLE_SIZE $MAC_TABLE_SIZE \
    CONFIG.PORT_COUNT {6} \
    CONFIG.PTP_MIXED_STEP $PTP_MIXED_STEP \
    CONFIG.STATS_DEVADDR {6} \
    CONFIG.STATS_ENABLE {true} \
    CONFIG.SUPPORT_PTP {true} \
    CONFIG.SUPPORT_VLAN {true} \
] $switch_core_0

set cfgbus_mdio_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_mdio cfgbus_mdio_0 ]
set_property -dict [ list \
    CONFIG.DEV_ADDR {7} \
] $cfgbus_mdio_0

set cfgbus_led_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_led cfgbus_led_0 ]
set_property -dict [list \
    CONFIG.DEV_ADDR {8} \
    CONFIG.LED_COUNT {16} \
] $cfgbus_led_0

set cfgbus_timer_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_timer cfgbus_timer_0 ]
set_property -dict [list \
    CONFIG.DEV_ADDR {9} \
    CONFIG.EVT_ENABLE {false} \
] $cfgbus_timer_0

set cfgbus_i2c_0 [ create_bd_cell -type ip \
    -vlnv aero.org:satcat5:cfgbus_i2c_controller:1.0 cfgbus_i2c_0 ]
set_property -dict [list \
    CONFIG.DEV_ADDR {10} \
] $cfgbus_i2c_0

set cfgbus_spi_0 [ create_bd_cell -type ip \
    -vlnv aero.org:satcat5:cfgbus_spi_controller:1.0 cfgbus_spi_0 ]
set_property -dict [list \
    CONFIG.DEV_ADDR {11} \
] $cfgbus_spi_0

set port_adapter_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_adapter port_adapter_0 ]
set ptp_reference_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:ptp_reference ptp_reference_0 ]
set rmii_mode_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant rmii_mode_0 ]
set rmii_reset_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:reset_hold rmii_reset_0 ]
set port_rmii_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_rmii port_rmii_0 ]
set_property -dict [ list \
    CONFIG.MODE_CLKOUT {true} \
    CONFIG.PTP_ENABLE {true} \
    CONFIG.PTP_REF_HZ {100000000} \
] $port_rmii_0

set switch_aux_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:switch_aux switch_aux_0 ]

connect_bd_intf_net -intf_net cfgbus_split_0_Port00 [get_bd_intf_pins cfgbus_split_0/Port00] [get_bd_intf_pins port_mailmap_0/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port01 [get_bd_intf_pins cfgbus_split_0/Port01] [get_bd_intf_pins pmod1/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port02 [get_bd_intf_pins cfgbus_split_0/Port02] [get_bd_intf_pins pmod2/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port03 [get_bd_intf_pins cfgbus_split_0/Port03] [get_bd_intf_pins pmod3/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port04 [get_bd_intf_pins cfgbus_split_0/Port04] [get_bd_intf_pins pmod4/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port05 [get_bd_intf_pins cfgbus_split_0/Port05] [get_bd_intf_pins switch_core_0/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port06 [get_bd_intf_pins cfgbus_split_0/Port06] [get_bd_intf_pins cfgbus_mdio_0/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port07 [get_bd_intf_pins cfgbus_split_0/Port07] [get_bd_intf_pins cfgbus_led_0/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port08 [get_bd_intf_pins cfgbus_split_0/Port08] [get_bd_intf_pins cfgbus_timer_0/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port09 [get_bd_intf_pins cfgbus_split_0/Port09] [get_bd_intf_pins cfgbus_i2c_0/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port10 [get_bd_intf_pins cfgbus_split_0/Port10] [get_bd_intf_pins cfgbus_spi_0/Cfg]
connect_bd_intf_net -intf_net pmod1_Eth [get_bd_intf_pins pmod1/Eth] [get_bd_intf_pins switch_core_0/Port01]
connect_bd_intf_net -intf_net pmod2_Eth [get_bd_intf_pins pmod2/Eth] [get_bd_intf_pins switch_core_0/Port02]
connect_bd_intf_net -intf_net pmod3_Eth [get_bd_intf_pins pmod3/Eth] [get_bd_intf_pins switch_core_0/Port03]
connect_bd_intf_net -intf_net pmod4_Eth [get_bd_intf_pins pmod4/Eth] [get_bd_intf_pins switch_core_0/Port04]
connect_bd_intf_net -intf_net port_adapter_0_SwPort [get_bd_intf_pins port_adapter_0/SwPort] [get_bd_intf_pins switch_core_0/Port05]
connect_bd_intf_net -intf_net port_mailmap_0_Eth [get_bd_intf_pins port_mailmap_0/Eth] [get_bd_intf_pins switch_core_0/Port00]
connect_bd_intf_net -intf_net port_rmii_0_Eth [get_bd_intf_pins port_adapter_0/MacPort] [get_bd_intf_pins port_rmii_0/Eth]
connect_bd_intf_net -intf_net port_rmii_0_RMII [get_bd_intf_ports rmii] [get_bd_intf_pins port_rmii_0/RMII]
connect_bd_intf_net -intf_net ptpref [get_bd_intf_pins ptp_reference_0/PtpRef] [get_bd_intf_pins port_mailmap_0/PtpRef] 
connect_bd_intf_net -intf_net ptpref [get_bd_intf_pins ptp_reference_0/PtpRef] [get_bd_intf_pins port_rmii_0/PtpRef]
connect_bd_intf_net -intf_net ublaze_CfgBus [get_bd_intf_pins cfgbus_split_0/Cfg] [get_bd_intf_pins ublaze/CfgBus]
connect_bd_net -net Net [get_bd_ports pmod1] [get_bd_pins pmod1/ext_pads]
connect_bd_net -net Net1 [get_bd_ports pmod4] [get_bd_pins pmod4/ext_pads]
connect_bd_net -net Net2 [get_bd_ports pmod3] [get_bd_pins pmod3/ext_pads]
connect_bd_net -net Net3 [get_bd_ports pmod2] [get_bd_pins pmod2/ext_pads]
connect_bd_net -net ext_reset_in_0_1 [get_bd_ports ext_reset_n] \
    [get_bd_pins ublaze/ext_reset_n] \
    [get_bd_pins rmii_reset_0/aresetn]
connect_bd_net -net microblaze_0_Clk [get_bd_ports ext_clk100] \
    [get_bd_pins rmii_reset_0/clk] \
    [get_bd_pins port_rmii_0/ctrl_clkin] \
    [get_bd_pins ptp_reference_0/ref_clk] \
    [get_bd_pins switch_aux_0/scrub_clk] \
    [get_bd_pins ublaze/ext_clk100]
connect_bd_net -net port_rmii_0_rmii_clkout [get_bd_ports rmii_clkout] [get_bd_pins port_rmii_0/rmii_clkout]
connect_bd_net -net port_rmii_0_rmii_mode [get_bd_ports rmii_mode] [get_bd_pins rmii_mode_0/dout]
connect_bd_net -net port_rmii_0_rmii_resetn [get_bd_ports rmii_resetn] [get_bd_pins rmii_reset_0/reset_n]
connect_bd_net -net switch_aux_0_scrub_req_t [get_bd_pins switch_aux_0/scrub_req_t] [get_bd_pins switch_core_0/scrub_req_t]
connect_bd_net -net switch_core_0_errvec_t [get_bd_pins switch_aux_0/errvec_00] [get_bd_pins switch_core_0/errvec_t]
connect_bd_net -net uart_rxd_1 [get_bd_ports uart_rxd] [get_bd_pins ublaze/uart_rxd]
connect_bd_net -net ublaze_clk50 [get_bd_pins port_rmii_0/rmii_clkin] [get_bd_pins ublaze/clk50]
connect_bd_net -net ublaze_clk100 [get_bd_pins pmod1/refclk] \
    [get_bd_pins pmod2/refclk] \
    [get_bd_pins pmod3/refclk] \
    [get_bd_pins pmod4/refclk] \
    [get_bd_pins switch_core_0/core_clk] \
    [get_bd_pins ublaze/clk100]
connect_bd_net -net ublaze_resetp [get_bd_pins pmod1/reset_p] \
    [get_bd_pins pmod2/reset_p] \
    [get_bd_pins pmod3/reset_p] \
    [get_bd_pins pmod4/reset_p] \
    [get_bd_pins switch_aux_0/reset_p] \
    [get_bd_pins switch_core_0/reset_p] \
    [get_bd_pins ublaze/resetp]
connect_bd_net \
    [get_bd_pins port_rmii_0/reset_p] \
    [get_bd_pins ptp_reference_0/reset_p] \
    [get_bd_pins rmii_reset_0/reset_p]
connect_bd_net -net ublaze_uart_txd [get_bd_ports uart_txd] [get_bd_pins ublaze/uart_txd]
connect_bd_net [get_bd_pins /cfgbus_mdio_0/mdio_clk] [get_bd_ports mdio_clk]
connect_bd_net [get_bd_pins /cfgbus_mdio_0/mdio_data] [get_bd_ports mdio_data]
connect_bd_net [get_bd_ports i2c_sck] [get_bd_pins cfgbus_i2c_0/i2c_sclk]
connect_bd_net [get_bd_ports i2c_sda] [get_bd_pins cfgbus_i2c_0/i2c_sdata]
connect_bd_net [get_bd_ports spi_csb] [get_bd_pins cfgbus_spi_0/spi_csb]
connect_bd_net [get_bd_ports spi_sck] [get_bd_pins cfgbus_spi_0/spi_sck]
connect_bd_net [get_bd_ports spi_sdi] [get_bd_pins cfgbus_spi_0/spi_sdi]
connect_bd_net [get_bd_ports spi_sdo] [get_bd_pins cfgbus_spi_0/spi_sdo]
connect_bd_net [get_bd_ports leds] [get_bd_pins cfgbus_led_0/led_out]
connect_bd_intf_net [get_bd_intf_ports text] [get_bd_intf_pins switch_aux_0/text_lcd]

# Create address segments
create_bd_addr_seg -range 0x00010000 -offset 0x44A00000 \
    [get_bd_addr_spaces ublaze/microblaze_0/Data] [get_bd_addr_segs ublaze/axi_uart16550_0/S_AXI/Reg] SEG_axi_uart16550_0_Reg
create_bd_addr_seg -range 0x00100000 -offset 0x44B00000 \
    [get_bd_addr_spaces ublaze/microblaze_0/Data] [get_bd_addr_segs ublaze/cfgbus_host_axi_0/CtrlAxi/CtrlAxi_addr] SEG_cfgbus_host_axi_0_CtrlAxi_addr
create_bd_addr_seg -range 0x00010000 -offset 0x00000000 \
    [get_bd_addr_spaces ublaze/microblaze_0/Data] [get_bd_addr_segs ublaze/ublaze_mem/dlmb_bram_if_cntlr/SLMB/Mem] SEG_dlmb_bram_if_cntlr_Mem
create_bd_addr_seg -range 0x00010000 -offset 0x00000000 \
    [get_bd_addr_spaces ublaze/microblaze_0/Instruction] [get_bd_addr_segs ublaze/ublaze_mem/ilmb_bram_if_cntlr/SLMB/Mem] SEG_ilmb_bram_if_cntlr_Mem
create_bd_addr_seg -range 0x00010000 -offset 0x41200000 \
    [get_bd_addr_spaces ublaze/microblaze_0/Data] [get_bd_addr_segs ublaze/microblaze_0_axi_intc/S_AXI/Reg] SEG_microblaze_0_axi_intc_Reg

# Cleanup
regenerate_bd_layout
save_bd_design
validate_bd_design

# Export block design in PDF and SVG form.
source ../../project/vivado/export_bd_image.tcl

# Suppress specific warnings in the Vivado GUI:
set_msg_config -suppress -id {[Constraints 18-550]}
set_msg_config -suppress -id {[DRC 23-20]}
set_msg_config -suppress -id {[Opt 31-35]}
set_msg_config -suppress -id {[Place 30-574]}
set_msg_config -suppress -id {[Power 33-332]}
set_msg_config -suppress -id {[Project 1-486]}
set_msg_config -suppress -id {[Synth 8-506]}
set_msg_config -suppress -id {[Synth 8-3301]}
set_msg_config -suppress -id {[Synth 8-3331]}
set_msg_config -suppress -id {[Synth 8-3332]}
set_msg_config -suppress -id {[Synth 8-3819]}
set_msg_config -suppress -id {[Synth 8-3919]}
set_msg_config -suppress -id {[Synth 8-3936]}
set_msg_config -suppress -id {[Timing 38-316]}

# Create block-diagram wrapper and set as top level.
set wrapper [make_wrapper -files [get_files ${design_name}.bd] -top]
add_files -norecurse $wrapper
set_property "top" ${design_name}_wrapper [get_filesets sources_1]
