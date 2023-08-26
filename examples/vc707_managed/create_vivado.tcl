# ------------------------------------------------------------------------
# Copyright 2022 The Aerospace Corporation
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
# This script creates a new Vivado project for the Xilinx VC707 dev board,
# with a block diagram as the top level (i.e., using packaged IP-cores).
# To re-create the project, source this file in the Vivado Tcl Shell.

puts {Running create_vivado.tcl}

# Change to example project folder.
cd [file normalize [file dirname [info script]]]

# Set project-level properties depending on the selected board.
set target_part "XC7VX485TFFG1761-2"
set target_proj "vc707_managed"
set constr_synth "vc707_synth.xdc"
set constr_impl "vc707_impl.xdc"
set override_postbit ""

# There's no source in this project except the IP-cores!
set files_main ""

# Run the main project-creation script and install IP-cores.
source ../../project/vivado/shared_create.tcl
source ../../project/vivado/shared_ipcores.tcl
set proj_dir [get_property directory [current_project]]

# Link to the VC707 board for predefined named interfaces (e.g., DDR3, SGMII)
set_property board_part xilinx.com:vc707:part0:1.4 [current_project]

# Create the block diagram
set design_name vc707_managed
create_bd_design $design_name
current_bd_design $design_name

# Top-level I/O ports
set cpu_reset [ create_bd_port -dir I -type rst cpu_reset ]
set_property CONFIG.POLARITY {ACTIVE_HIGH} $cpu_reset
set emc_clk [ create_bd_port -dir I -type clk emc_clk ]
set_property CONFIG.FREQ_HZ {80000000} $emc_clk
set mgt_clk [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 mgt_clk ]
set_property CONFIG.FREQ_HZ {125000000} $mgt_clk
set phy_mdio_sck [ create_bd_port -dir O phy_mdio_sck ]
set phy_mdio_sda [ create_bd_port -dir IO phy_mdio_sda ]
set sfp_i2c_sck [ create_bd_port -dir IO sfp_i2c_sck ]
set sfp_i2c_sda [ create_bd_port -dir IO sfp_i2c_sda ]
set status_led [ create_bd_port -dir O -from 7 -to 0 status_led ]
set usb_uart [ create_bd_port -dir IO -from 3 -to 0 usb_uart ]
set ddr3 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 ddr3 ]
set sgmii_rj45 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:sgmii_rtl:1.0 sgmii_rj45 ]
set sgmii_sfp [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:sgmii_rtl:1.0 sgmii_sfp ]
set sys_clk [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 sys_clk ]
set text_lcd [ create_bd_intf_port -mode Master -vlnv aero.org:satcat5:TextLCD_rtl:1.0 text_lcd ]

# Hierarchical cell: ublaze/mem
current_bd_instance [create_bd_cell -type hier ublaze0]
current_bd_instance [create_bd_cell -type hier microblaze_0_local_memory]

create_bd_intf_pin -mode MirroredMaster -vlnv xilinx.com:interface:lmb_rtl:1.0 DLMB
create_bd_intf_pin -mode MirroredMaster -vlnv xilinx.com:interface:lmb_rtl:1.0 ILMB
create_bd_pin -dir I -type clk LMB_Clk
create_bd_pin -dir I -type rst SYS_Rst

set dlmb_bram_if_cntlr [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr dlmb_bram_if_cntlr ]
set_property CONFIG.C_ECC {0} $dlmb_bram_if_cntlr

set dlmb_v10 [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10 dlmb_v10 ]

set ilmb_bram_if_cntlr [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr ilmb_bram_if_cntlr ]
set_property CONFIG.C_ECC {0} $ilmb_bram_if_cntlr

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
connect_bd_net -net microblaze_0_Clk [get_bd_pins LMB_Clk] \
    [get_bd_pins dlmb_bram_if_cntlr/LMB_Clk] \
    [get_bd_pins dlmb_v10/LMB_Clk] \
    [get_bd_pins ilmb_bram_if_cntlr/LMB_Clk] \
    [get_bd_pins ilmb_v10/LMB_Clk]

# Hierarchical cell: ublaze0
current_bd_instance ..

create_bd_intf_pin -mode Master -vlnv aero.org:satcat5:ConfigBus_rtl:1.0 CfgBus
create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 ddr3
create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_ctrl
create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 sys_clk
create_bd_pin -dir O -from 0 -to 0 -type rst axi_aresetn
create_bd_pin -dir O -type clk clk_100
create_bd_pin -dir O -type clk clk_200
create_bd_pin -dir I -type rst cpu_reset
create_bd_pin -dir I -from 5 -to 0 -type intr intr
create_bd_pin -dir O -from 0 -to 0 -type rst reset_p
create_bd_pin -dir I -type rst wdog_resetp

set axi_crossbar_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_crossbar:2.1 axi_crossbar_0 ]
set_property -dict [ list \
    CONFIG.CONNECTIVITY_MODE {SASD} \
    CONFIG.NUM_MI {4} \
    CONFIG.PROTOCOL {AXI4LITE} \
    CONFIG.R_REGISTER {1} \
    CONFIG.S00_SINGLE_THREAD {1} \
] $axi_crossbar_0

set cfgbus_host_axi_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_host_axi:1.0 cfgbus_host_axi_0 ]

set mdm_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:mdm:3.2 mdm_1 ]
set_property -dict [ list \
    CONFIG.C_ADDR_SIZE {32} \
    CONFIG.C_M_AXI_ADDR_WIDTH {32} \
    CONFIG.C_USE_UART {1} \
] $mdm_1

set microblaze_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze:11.0 microblaze_0 ]
set_property -dict [ list \
    CONFIG.C_DEBUG_ENABLED {1} \
    CONFIG.C_D_AXI {1} \
    CONFIG.C_D_LMB {1} \
    CONFIG.C_I_AXI {0} \
    CONFIG.C_I_LMB {1} \
    CONFIG.C_USE_BARREL {1} \
    CONFIG.C_USE_DIV {1} \
    CONFIG.C_USE_FPU {2} \
    CONFIG.C_USE_HW_MUL {2} \
] $microblaze_0

set microblaze_0_axi_intc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 microblaze_0_axi_intc ]
set_property CONFIG.C_HAS_FAST {1} $microblaze_0_axi_intc

set microblaze_0_axi_periph [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 microblaze_0_axi_periph ]
set_property -dict [ list \
    CONFIG.M00_HAS_DATA_FIFO {2} \
    CONFIG.M00_HAS_REGSLICE {3} \
    CONFIG.M01_HAS_DATA_FIFO {0} \
    CONFIG.M01_HAS_REGSLICE {3} \
    CONFIG.NUM_MI {2} \
    CONFIG.S00_HAS_DATA_FIFO {0} \
] $microblaze_0_axi_periph

set microblaze_0_xlconcat [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 microblaze_0_xlconcat ]
set_property -dict [ list \
    CONFIG.NUM_PORTS {3} \
] $microblaze_0_xlconcat

set mig_7series_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:mig_7series:4.2 mig_7series_0 ]
set_property -dict [ list \
    CONFIG.BOARD_MIG_PARAM {Custom} \
    CONFIG.MIG_DONT_TOUCH_PARAM {Custom} \
    CONFIG.RESET_BOARD_INTERFACE {Custom} \
    CONFIG.XML_INPUT_FILE [file normalize ./vc707_mig.prj] \
] $mig_7series_0

set rst_clk_wiz_1_100M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_clk_wiz_1_100M ]
set_property -dict [ list \
    CONFIG.C_AUX_RESET_HIGH {1} \
] $rst_clk_wiz_1_100M

set util_vector_logic_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 util_vector_logic_0 ]
set_property -dict [ list \
    CONFIG.C_OPERATION {not} \
    CONFIG.LOGO_FILE {data/sym_notgate.png} \
] $util_vector_logic_0

connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins CfgBus] [get_bd_intf_pins cfgbus_host_axi_0/Cfg]
connect_bd_intf_net -intf_net Conn2 [get_bd_intf_pins ddr3] [get_bd_intf_pins mig_7series_0/ddr3]
connect_bd_intf_net -intf_net Conn3 [get_bd_intf_pins sys_clk] [get_bd_intf_pins mig_7series_0/SYS_CLK]
connect_bd_intf_net -intf_net axi_crossbar_0_M00_AXI [get_bd_intf_pins axi_crossbar_0/M00_AXI] [get_bd_intf_pins microblaze_0_axi_intc/s_axi]
connect_bd_intf_net -intf_net axi_crossbar_0_M01_AXI [get_bd_intf_pins axi_crossbar_0/M01_AXI] [get_bd_intf_pins cfgbus_host_axi_0/CtrlAxi]
connect_bd_intf_net -intf_net axi_crossbar_0_M02_AXI [get_bd_intf_pins axi_ctrl] [get_bd_intf_pins axi_crossbar_0/M02_AXI]
connect_bd_intf_net -intf_net axi_crossbar_0_M03_AXI [get_bd_intf_pins axi_crossbar_0/M03_AXI] [get_bd_intf_pins mdm_1/S_AXI]
connect_bd_intf_net -intf_net microblaze_0_axi_dp [get_bd_intf_pins microblaze_0/M_AXI_DP] [get_bd_intf_pins microblaze_0_axi_periph/S00_AXI]
connect_bd_intf_net -intf_net microblaze_0_axi_periph_M00_AXI [get_bd_intf_pins microblaze_0_axi_periph/M00_AXI] [get_bd_intf_pins mig_7series_0/S_AXI]
connect_bd_intf_net -intf_net microblaze_0_axi_periph_M01_AXI [get_bd_intf_pins axi_crossbar_0/S00_AXI] [get_bd_intf_pins microblaze_0_axi_periph/M01_AXI]
connect_bd_intf_net -intf_net microblaze_0_debug [get_bd_intf_pins mdm_1/MBDEBUG_0] [get_bd_intf_pins microblaze_0/DEBUG]
connect_bd_intf_net -intf_net microblaze_0_dlmb_1 [get_bd_intf_pins microblaze_0/DLMB] [get_bd_intf_pins microblaze_0_local_memory/DLMB]
connect_bd_intf_net -intf_net microblaze_0_ilmb_1 [get_bd_intf_pins microblaze_0/ILMB] [get_bd_intf_pins microblaze_0_local_memory/ILMB]
connect_bd_intf_net -intf_net microblaze_0_interrupt [get_bd_intf_pins microblaze_0/INTERRUPT] [get_bd_intf_pins microblaze_0_axi_intc/interrupt]
connect_bd_net -net M00_ACLK_1 [get_bd_pins microblaze_0_axi_periph/M00_ACLK] [get_bd_pins mig_7series_0/ui_clk]
connect_bd_net -net aux_reset_in_0_1 [get_bd_pins wdog_resetp] [get_bd_pins rst_clk_wiz_1_100M/aux_reset_in]
connect_bd_net -net cfgbus_host_axi_0_irq_out [get_bd_pins cfgbus_host_axi_0/irq_out] [get_bd_pins microblaze_0_xlconcat/In0]
connect_bd_net -net cpu_reset_1 [get_bd_pins cpu_reset] [get_bd_pins mig_7series_0/sys_rst] [get_bd_pins util_vector_logic_0/Op1]
connect_bd_net -net intr_1 [get_bd_pins intr] [get_bd_pins microblaze_0_xlconcat/In1]
connect_bd_net -net mdm_1_Interrupt [get_bd_pins mdm_1/Interrupt] [get_bd_pins microblaze_0_xlconcat/In2]
connect_bd_net -net mdm_1_debug_sys_rst [get_bd_pins mdm_1/Debug_SYS_Rst] [get_bd_pins rst_clk_wiz_1_100M/mb_debug_sys_rst]
connect_bd_net -net microblaze_0_xlconcat_dout [get_bd_pins microblaze_0_axi_intc/intr] [get_bd_pins microblaze_0_xlconcat/dout]
connect_bd_net -net mig_7series_0_mmcm_locked [get_bd_pins mig_7series_0/mmcm_locked] [get_bd_pins rst_clk_wiz_1_100M/dcm_locked]
connect_bd_net -net mig_7series_0_ui_addn_clk_1 [get_bd_pins clk_200] [get_bd_pins mig_7series_0/ui_addn_clk_1]
connect_bd_net -net rst_clk_wiz_1_100M_bus_struct_reset [get_bd_pins microblaze_0_local_memory/SYS_Rst] [get_bd_pins rst_clk_wiz_1_100M/bus_struct_reset]
connect_bd_net -net rst_clk_wiz_1_100M_interconnect_aresetn [get_bd_pins axi_aresetn] [get_bd_pins mig_7series_0/aresetn] [get_bd_pins rst_clk_wiz_1_100M/interconnect_aresetn]
connect_bd_net -net rst_clk_wiz_1_100M_mb_reset [get_bd_pins microblaze_0/Reset] [get_bd_pins microblaze_0_axi_intc/processor_rst] [get_bd_pins rst_clk_wiz_1_100M/mb_reset]
connect_bd_net -net rst_clk_wiz_1_100M_peripheral_aresetn [get_bd_pins axi_crossbar_0/aresetn] [get_bd_pins cfgbus_host_axi_0/axi_aresetn] [get_bd_pins mdm_1/S_AXI_ARESETN] [get_bd_pins microblaze_0_axi_intc/s_axi_aresetn] [get_bd_pins microblaze_0_axi_periph/ARESETN] [get_bd_pins microblaze_0_axi_periph/M00_ARESETN] [get_bd_pins microblaze_0_axi_periph/M01_ARESETN] [get_bd_pins microblaze_0_axi_periph/S00_ARESETN] [get_bd_pins rst_clk_wiz_1_100M/peripheral_aresetn]
connect_bd_net -net rst_clk_wiz_1_100M_peripheral_reset [get_bd_pins reset_p] [get_bd_pins rst_clk_wiz_1_100M/peripheral_reset]
connect_bd_net -net slowest_sync_clk_0_1 [get_bd_pins clk_100] [get_bd_pins axi_crossbar_0/aclk] [get_bd_pins cfgbus_host_axi_0/axi_clk] [get_bd_pins mdm_1/S_AXI_ACLK] [get_bd_pins microblaze_0/Clk] [get_bd_pins microblaze_0_axi_intc/processor_clk] [get_bd_pins microblaze_0_axi_intc/s_axi_aclk] [get_bd_pins microblaze_0_axi_periph/ACLK] [get_bd_pins microblaze_0_axi_periph/M01_ACLK] [get_bd_pins microblaze_0_axi_periph/S00_ACLK] [get_bd_pins microblaze_0_local_memory/LMB_Clk] [get_bd_pins mig_7series_0/ui_addn_clk_0] [get_bd_pins rst_clk_wiz_1_100M/slowest_sync_clk]
connect_bd_net -net util_vector_logic_0_Res [get_bd_pins rst_clk_wiz_1_100M/ext_reset_in] [get_bd_pins util_vector_logic_0/Res]

# Hierarchical cell: xilinx_temac
current_bd_instance ..
current_bd_instance [create_bd_cell -type hier xilinx_temac]

create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 ctrl_axi
create_bd_intf_pin -mode Master -vlnv aero.org:satcat5:EthPort_rtl:1.0 eth_rj45
create_bd_intf_pin -mode Master -vlnv aero.org:satcat5:EthPort_rtl:1.0 eth_sfp
create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 mgt_clk
create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:sgmii_rtl:1.0 sgmii_rj45
create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:sgmii_rtl:1.0 sgmii_sfp
create_bd_pin -dir I -type clk clk_200
create_bd_pin -dir I -type clk ctrl_clk
create_bd_pin -dir O -from 1 -to 0 ctrl_irq
create_bd_pin -dir I -type rst ctrl_resetn

set axi_crossbar_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_crossbar:2.1 axi_crossbar_0 ]

set axi_ethernet_rj45 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_ethernet:7.1 axi_ethernet_rj45 ]
set_property -dict [ list \
   CONFIG.DIFFCLK_BOARD_INTERFACE {sgmii_mgt_clk} \
   CONFIG.ETHERNET_BOARD_INTERFACE {sgmii} \
   CONFIG.Enable_1588 {false} \
   CONFIG.Frame_Filter {false} \
   CONFIG.PHYRST_BOARD_INTERFACE {phy_reset_out} \
   CONFIG.PHY_TYPE {SGMII} \
   CONFIG.Statistics_Counters {false} \
   CONFIG.Statistics_Width {32bit} \
   CONFIG.processor_mode {false} \
] $axi_ethernet_rj45

set axi_ethernet_sfp [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_ethernet:7.1 axi_ethernet_sfp ]
set_property -dict [ list \
   CONFIG.DIFFCLK_BOARD_INTERFACE {Custom} \
   CONFIG.ETHERNET_BOARD_INTERFACE {sfp_sgmii} \
   CONFIG.Enable_1588 {false} \
   CONFIG.Frame_Filter {false} \
   CONFIG.PHYRST_BOARD_INTERFACE {Custom} \
   CONFIG.PHY_TYPE {SGMII} \
   CONFIG.Statistics_Counters {false} \
   CONFIG.Statistics_Width {32bit} \
   CONFIG.SupportLevel {0} \
   CONFIG.processor_mode {false} \
] $axi_ethernet_sfp

set port_stream_rj45 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_stream:1.0 port_stream_rj45 ]
set_property -dict [ list \
    CONFIG.RX_MIN_FRM {0} \
    CONFIG.RX_HAS_FCS {false} \
    CONFIG.TX_HAS_FCS {false} \
] $port_stream_rj45

set port_stream_sfp [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_stream:1.0 port_stream_sfp ]
set_property -dict [ list \
    CONFIG.RX_MIN_FRM {0} \
    CONFIG.RX_HAS_FCS {false} \
    CONFIG.TX_HAS_FCS {false} \
] $port_stream_sfp

set util_vector_logic_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 util_vector_logic_0 ]
set_property -dict [ list \
    CONFIG.C_OPERATION {not} \
    CONFIG.C_SIZE {1} \
    CONFIG.LOGO_FILE {data/sym_notgate.png} \
] $util_vector_logic_0

set xlconcat_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0 ]
set_property CONFIG.NUM_PORTS {2} $xlconcat_0

connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins sgmii_sfp] [get_bd_intf_pins axi_ethernet_sfp/sgmii]
connect_bd_intf_net -intf_net Conn2 [get_bd_intf_pins eth_sfp] [get_bd_intf_pins port_stream_sfp/Eth]
connect_bd_intf_net -intf_net axi_crossbar_0_M00_AXI [get_bd_intf_pins axi_crossbar_0/M00_AXI] [get_bd_intf_pins axi_ethernet_rj45/s_axi]
connect_bd_intf_net -intf_net axi_crossbar_0_M01_AXI [get_bd_intf_pins axi_crossbar_0/M01_AXI] [get_bd_intf_pins axi_ethernet_sfp/s_axi]
connect_bd_intf_net -intf_net axi_ethernet_rj45_m_axis_rx [get_bd_intf_pins axi_ethernet_rj45/m_axis_rx] [get_bd_intf_pins port_stream_rj45/Rx]
connect_bd_intf_net -intf_net axi_ethernet_rj45_sgmii [get_bd_intf_pins sgmii_rj45] [get_bd_intf_pins axi_ethernet_rj45/sgmii]
connect_bd_intf_net -intf_net axi_ethernet_sfp_m_axis_rx [get_bd_intf_pins axi_ethernet_sfp/m_axis_rx] [get_bd_intf_pins port_stream_sfp/Rx]
connect_bd_intf_net -intf_net ctrl_axi_1 [get_bd_intf_pins ctrl_axi] [get_bd_intf_pins axi_crossbar_0/S00_AXI]
connect_bd_intf_net -intf_net mgt_clk_1 [get_bd_intf_pins mgt_clk] [get_bd_intf_pins axi_ethernet_rj45/mgt_clk]
connect_bd_intf_net -intf_net port_stream_rj45_Eth [get_bd_intf_pins eth_rj45] [get_bd_intf_pins port_stream_rj45/Eth]
connect_bd_intf_net -intf_net port_stream_rj45_Tx [get_bd_intf_pins axi_ethernet_rj45/s_axis_tx] [get_bd_intf_pins port_stream_rj45/Tx]
connect_bd_intf_net -intf_net port_stream_sfp_Tx [get_bd_intf_pins axi_ethernet_sfp/s_axis_tx] [get_bd_intf_pins port_stream_sfp/Tx]
connect_bd_net -net axi_ethernet_rj45_gt0_qplloutclk_out [get_bd_pins axi_ethernet_rj45/gt0_qplloutclk_out] [get_bd_pins axi_ethernet_sfp/gt0_qplloutclk_in]
connect_bd_net -net axi_ethernet_rj45_gt0_qplloutrefclk_out [get_bd_pins axi_ethernet_rj45/gt0_qplloutrefclk_out] [get_bd_pins axi_ethernet_sfp/gt0_qplloutrefclk_in]
connect_bd_net -net axi_ethernet_rj45_gtref_clk_buf_out [get_bd_pins axi_ethernet_rj45/gtref_clk_buf_out] [get_bd_pins axi_ethernet_sfp/gtref_clk_buf]
connect_bd_net -net axi_ethernet_rj45_gtref_clk_out [get_bd_pins axi_ethernet_rj45/gtref_clk_out] [get_bd_pins axi_ethernet_sfp/gtref_clk]
connect_bd_net -net axi_ethernet_rj45_mac_irq [get_bd_pins axi_ethernet_rj45/mac_irq] [get_bd_pins xlconcat_0/In0]
connect_bd_net -net axi_ethernet_rj45_mmcm_locked_out [get_bd_pins axi_ethernet_rj45/mmcm_locked_out] [get_bd_pins axi_ethernet_sfp/mmcm_locked]
connect_bd_net -net axi_ethernet_rj45_pma_reset_out [get_bd_pins axi_ethernet_rj45/pma_reset_out] [get_bd_pins axi_ethernet_sfp/pma_reset]
connect_bd_net -net axi_ethernet_rj45_rx_mac_aclk [get_bd_pins axi_ethernet_rj45/rx_mac_aclk] [get_bd_pins port_stream_rj45/rx_clk]
connect_bd_net -net axi_ethernet_rj45_rx_reset [get_bd_pins axi_ethernet_rj45/rx_reset] [get_bd_pins port_stream_rj45/rx_reset]
connect_bd_net -net axi_ethernet_rj45_rxuserclk2_out [get_bd_pins axi_ethernet_rj45/rxuserclk2_out] [get_bd_pins axi_ethernet_sfp/rxuserclk2]
connect_bd_net -net axi_ethernet_rj45_rxuserclk_out [get_bd_pins axi_ethernet_rj45/rxuserclk_out] [get_bd_pins axi_ethernet_sfp/rxuserclk]
connect_bd_net -net axi_ethernet_rj45_tx_mac_aclk [get_bd_pins axi_ethernet_rj45/tx_mac_aclk] [get_bd_pins port_stream_rj45/tx_clk]
connect_bd_net -net axi_ethernet_rj45_tx_reset [get_bd_pins axi_ethernet_rj45/tx_reset] [get_bd_pins port_stream_rj45/tx_reset]
connect_bd_net -net axi_ethernet_rj45_userclk2_out [get_bd_pins axi_ethernet_rj45/userclk2_out] [get_bd_pins axi_ethernet_sfp/userclk2]
connect_bd_net -net axi_ethernet_rj45_userclk_out [get_bd_pins axi_ethernet_rj45/userclk_out] [get_bd_pins axi_ethernet_sfp/userclk]
connect_bd_net -net axi_ethernet_sfp_mac_irq [get_bd_pins axi_ethernet_sfp/mac_irq] [get_bd_pins xlconcat_0/In1]
connect_bd_net -net axi_ethernet_sfp_rx_mac_aclk [get_bd_pins axi_ethernet_sfp/rx_mac_aclk] [get_bd_pins port_stream_sfp/rx_clk]
connect_bd_net -net axi_ethernet_sfp_rx_reset [get_bd_pins axi_ethernet_sfp/rx_reset] [get_bd_pins port_stream_sfp/rx_reset]
connect_bd_net -net axi_ethernet_sfp_tx_mac_aclk [get_bd_pins axi_ethernet_sfp/tx_mac_aclk] [get_bd_pins port_stream_sfp/tx_clk]
connect_bd_net -net axi_ethernet_sfp_tx_reset [get_bd_pins axi_ethernet_sfp/tx_reset] [get_bd_pins port_stream_sfp/tx_reset]
connect_bd_net -net clk_200_1 [get_bd_pins clk_200] [get_bd_pins axi_ethernet_rj45/ref_clk] [get_bd_pins axi_ethernet_sfp/ref_clk]
connect_bd_net -net cpu_clk_1 [get_bd_pins ctrl_clk] [get_bd_pins axi_crossbar_0/aclk] [get_bd_pins axi_ethernet_rj45/s_axi_lite_clk] [get_bd_pins axi_ethernet_sfp/s_axi_lite_clk]
connect_bd_net -net ublaze0_mig_aresetn [get_bd_pins ctrl_resetn] \
    [get_bd_pins axi_crossbar_0/aresetn] [get_bd_pins axi_ethernet_rj45/s_axi_lite_resetn] [get_bd_pins axi_ethernet_sfp/s_axi_lite_resetn] [get_bd_pins util_vector_logic_0/Op1]
connect_bd_net -net util_vector_logic_0_Res [get_bd_pins axi_ethernet_rj45/glbl_rst] [get_bd_pins axi_ethernet_sfp/glbl_rst] [get_bd_pins util_vector_logic_0/Res]
connect_bd_net -net xlconcat_0_dout [get_bd_pins ctrl_irq] [get_bd_pins xlconcat_0/dout]

# Create and connect top-level
# Note: ConfigBus DEV_ADDR fields are assigned sequentially.
current_bd_instance ..

set cfgbus_split_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_split:1.0 cfgbus_split_0 ]
set_property -dict [ list \
    CONFIG.DLY_BUFFER {true} \
    CONFIG.PORT_COUNT {9} \
] $cfgbus_split_0

set switch_core [ create_bd_cell -type ip -vlnv aero.org:satcat5:switch_core:1.0 switch_core ]
set_property -dict [ list \
    CONFIG.CFG_ENABLE {true} \
    CONFIG.CFG_DEV_ADDR {0} \
    CONFIG.STATS_ENABLE {true} \
    CONFIG.STATS_DEVADDR {1} \
    CONFIG.ALLOW_PRECOMMIT {true} \
    CONFIG.ALLOW_RUNT {false} \
    CONFIG.CORE_CLK_HZ {100000000} \
    CONFIG.DATAPATH_BYTES {3} \
    CONFIG.HBUF_KBYTES {2} \
    CONFIG.PORT_COUNT {4} \
    CONFIG.SUPPORT_PTP {true} \
    CONFIG.SUPPORT_VLAN {true} \
] $switch_core

set port_mailmap [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_mailmap:1.0 port_mailmap ]
set_property -dict [ list \
    CONFIG.DEV_ADDR {2} \
] $port_mailmap

set port_serial_uart [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_serial_uart_4wire:1.0 port_serial_uart ]
set_property -dict [ list \
    CONFIG.CFG_DEV_ADDR {3} \
    CONFIG.CFG_ENABLE {true} \
] $port_serial_uart

set cfgbus_i2c_controller_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_i2c_controller:1.0 cfgbus_i2c_controller_0 ]
set_property -dict [ list \
    CONFIG.DEV_ADDR {4} \
] $cfgbus_i2c_controller_0

set cfgbus_timer_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_timer:1.0 cfgbus_timer_0 ]
set_property -dict [ list \
    CONFIG.DEV_ADDR {5} \
    CONFIG.EVT_ENABLE {false} \
    CONFIG.TMR_ENABLE {true} \
] $cfgbus_timer_0

set cfgbus_mdio_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_mdio:1.0 cfgbus_mdio_0 ]
set_property -dict [ list \
    CONFIG.DEV_ADDR {6} \
] $cfgbus_mdio_0

set cfgbus_led_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_led:1.0 cfgbus_led_0 ]
set_property -dict [ list \
    CONFIG.DEV_ADDR {7} \
    CONFIG.LED_COUNT {8} \
] $cfgbus_led_0

set cfgbus_uart_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_uart:1.0 cfgbus_uart_0 ]
set_property -dict [ list \
    CONFIG.DEV_ADDR {8} \
] $cfgbus_uart_0

set cfgbus_text_lcd_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_text_lcd:1.0 cfgbus_text_lcd_0 ]
set_property -dict [ list \
    CONFIG.DEV_ADDR {9} \
] $cfgbus_text_lcd_0

set microblaze_0_xlconcat [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 microblaze_0_xlconcat ]
set_property -dict [ list \
    CONFIG.NUM_PORTS {1} \
] $microblaze_0_xlconcat

set switch_aux_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:switch_aux:1.0 switch_aux_0 ]
set_property -dict [ list \
    CONFIG.SCRUB_CLK_HZ {80000000} \
] $switch_aux_0

connect_bd_intf_net -intf_net cfgbus_split_0_Port00 [get_bd_intf_pins cfgbus_split_0/Port00] [get_bd_intf_pins switch_core/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port01 [get_bd_intf_pins cfgbus_split_0/Port01] [get_bd_intf_pins port_mailmap/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port02 [get_bd_intf_pins cfgbus_split_0/Port02] [get_bd_intf_pins port_serial_uart/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port03 [get_bd_intf_pins cfgbus_split_0/Port03] [get_bd_intf_pins cfgbus_i2c_controller_0/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port04 [get_bd_intf_pins cfgbus_split_0/Port04] [get_bd_intf_pins cfgbus_timer_0/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port05 [get_bd_intf_pins cfgbus_split_0/Port05] [get_bd_intf_pins cfgbus_mdio_0/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port06 [get_bd_intf_pins cfgbus_split_0/Port06] [get_bd_intf_pins cfgbus_led_0/Cfg] 
connect_bd_intf_net -intf_net cfgbus_split_0_Port07 [get_bd_intf_pins cfgbus_split_0/Port07] [get_bd_intf_pins cfgbus_uart_0/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port08 [get_bd_intf_pins cfgbus_split_0/Port08] [get_bd_intf_pins cfgbus_text_lcd_0/Cfg]
connect_bd_intf_net -intf_net ctrl_axi_1 [get_bd_intf_pins ublaze0/axi_ctrl] [get_bd_intf_pins xilinx_temac/ctrl_axi]
connect_bd_intf_net -intf_net port_mailmap_0_Eth [get_bd_intf_pins port_mailmap/Eth] [get_bd_intf_pins switch_core/Port00]
connect_bd_intf_net -intf_net port_serial_uart_4wi_0_Eth [get_bd_intf_pins port_serial_uart/Eth] [get_bd_intf_pins switch_core/Port01]
connect_bd_intf_net -intf_net sgmii_mgt_clk_1 [get_bd_intf_ports mgt_clk] [get_bd_intf_pins xilinx_temac/mgt_clk]
connect_bd_intf_net -intf_net switch_aux_0_text_lcd [get_bd_intf_ports text_lcd] [get_bd_intf_pins cfgbus_text_lcd_0/text_lcd]
connect_bd_intf_net -intf_net sys_clk_1 [get_bd_intf_ports sys_clk] [get_bd_intf_pins ublaze0/sys_clk]
connect_bd_intf_net -intf_net temac_sfp1_Eth [get_bd_intf_pins switch_core/Port03] [get_bd_intf_pins xilinx_temac/eth_rj45]
connect_bd_intf_net -intf_net temac_sfp1_sfp_sgmii [get_bd_intf_ports sgmii_rj45] [get_bd_intf_pins xilinx_temac/sgmii_rj45]
connect_bd_intf_net -intf_net ublaze0_CfgBus [get_bd_intf_pins cfgbus_split_0/Cfg] [get_bd_intf_pins ublaze0/CfgBus]
connect_bd_intf_net -intf_net ublaze0_ddr3_0 [get_bd_intf_ports ddr3] [get_bd_intf_pins ublaze0/ddr3]
connect_bd_intf_net -intf_net xilinx_temac_eth_sfp [get_bd_intf_pins switch_core/Port02] [get_bd_intf_pins xilinx_temac/eth_sfp]
connect_bd_intf_net -intf_net xilinx_temac_sfp_0 [get_bd_intf_ports sgmii_sfp] [get_bd_intf_pins xilinx_temac/sgmii_sfp]
connect_bd_net -net Net [get_bd_ports usb_uart] [get_bd_pins port_serial_uart/ext_pads]
connect_bd_net -net cfgbus_timer_0_wdog_resetp [get_bd_pins cfgbus_timer_0/wdog_resetp] [get_bd_pins ublaze0/wdog_resetp]
connect_bd_net -net clk200_1 [get_bd_pins ublaze0/clk_200] [get_bd_pins xilinx_temac/clk_200]
connect_bd_net -net cpu_clk_1 [get_bd_pins port_serial_uart/refclk] [get_bd_pins switch_core/core_clk] [get_bd_pins ublaze0/clk_100] [get_bd_pins xilinx_temac/ctrl_clk]
connect_bd_net -net cpu_reset_1 [get_bd_ports cpu_reset] [get_bd_pins ublaze0/cpu_reset]
connect_bd_net -net microblaze_0_intr [get_bd_pins microblaze_0_xlconcat/dout] [get_bd_pins ublaze0/intr]
connect_bd_net -net phy_mdio_sck [get_bd_ports phy_mdio_sck] [get_bd_pins cfgbus_mdio_0/mdio_clk]
connect_bd_net -net phy_mdio_sda [get_bd_ports phy_mdio_sda] [get_bd_pins cfgbus_mdio_0/mdio_data]
connect_bd_net -net scrub_clk_0_1 [get_bd_ports emc_clk] [get_bd_pins switch_aux_0/scrub_clk]
connect_bd_net -net sfp_sck [get_bd_ports sfp_i2c_sck] [get_bd_pins cfgbus_i2c_controller_0/i2c_sclk]
connect_bd_net -net sfp_sda [get_bd_ports sfp_i2c_sda] [get_bd_pins cfgbus_i2c_controller_0/i2c_sdata]
connect_bd_net -net status_led [get_bd_ports status_led] [get_bd_pins cfgbus_led_0/led_out]
connect_bd_net -net switch_aux_0_scrub_req_t [get_bd_pins switch_aux_0/scrub_req_t] [get_bd_pins switch_core/scrub_req_t]
connect_bd_net -net switch_aux_0_status_uart [get_bd_pins cfgbus_uart_0/uart_rxd] [get_bd_pins switch_aux_0/status_uart]
connect_bd_net -net switch_core_errvec_t [get_bd_pins switch_aux_0/errvec_00] [get_bd_pins switch_core/errvec_t]
connect_bd_net -net ublaze0_mig_aresetn [get_bd_pins ublaze0/axi_aresetn] [get_bd_pins xilinx_temac/ctrl_resetn]
connect_bd_net -net ublaze0_reset_p [get_bd_pins port_serial_uart/reset_p] [get_bd_pins switch_aux_0/reset_p] [get_bd_pins switch_core/reset_p] [get_bd_pins ublaze0/reset_p]
connect_bd_net -net xilinx_temac_ctrl_irq [get_bd_pins microblaze_0_xlconcat/In0] [get_bd_pins xilinx_temac/ctrl_irq]

# Create address segments
create_bd_addr_seg -range 0x00020000 -offset 0x40C00000 \
    [get_bd_addr_spaces ublaze0/microblaze_0/Data] \
    [get_bd_addr_segs xilinx_temac/axi_ethernet_sfp/s_axi/Reg0] SEG_axi_ethernet_sfp_Reg0
create_bd_addr_seg -range 0x00020000 -offset 0x40C20000 \
    [get_bd_addr_spaces ublaze0/microblaze_0/Data] \
    [get_bd_addr_segs xilinx_temac/axi_ethernet_rj45/s_axi/Reg0] SEG_axi_ethernet_rj45_Reg0
create_bd_addr_seg -range 0x00100000 -offset 0x44A00000 \
    [get_bd_addr_spaces ublaze0/microblaze_0/Data] \
    [get_bd_addr_segs ublaze0/cfgbus_host_axi_0/CtrlAxi/CtrlAxi_addr] SEG_cfgbus_host_axi_0_CtrlAxi_addr
create_bd_addr_seg -range 0x00040000 -offset 0x00000000 \
    [get_bd_addr_spaces ublaze0/microblaze_0/Data] \
    [get_bd_addr_segs ublaze0/microblaze_0_local_memory/dlmb_bram_if_cntlr/SLMB/Mem] SEG_dlmb_bram_if_cntlr_Mem
create_bd_addr_seg -range 0x00040000 -offset 0x00000000 \
    [get_bd_addr_spaces ublaze0/microblaze_0/Instruction] \
    [get_bd_addr_segs ublaze0/microblaze_0_local_memory/ilmb_bram_if_cntlr/SLMB/Mem] SEG_ilmb_bram_if_cntlr_Mem
create_bd_addr_seg -range 0x00010000 -offset 0x41200000 \
    [get_bd_addr_spaces ublaze0/microblaze_0/Data] \
    [get_bd_addr_segs ublaze0/microblaze_0_axi_intc/S_AXI/Reg] SEG_microblaze_0_axi_intc_Reg
create_bd_addr_seg -range 0x00001000 -offset 0x41400000 \
    [get_bd_addr_spaces ublaze0/microblaze_0/Data] \
    [get_bd_addr_segs ublaze0/mdm_1/S_AXI/Reg] SEG_mdm_1_Reg
create_bd_addr_seg -range 0x40000000 -offset 0x80000000 \
    [get_bd_addr_spaces ublaze0/microblaze_0/Data] \
    [get_bd_addr_segs ublaze0/mig_7series_0/memmap/memaddr] SEG_mig_7series_0_memaddr

# Cleanup
regenerate_bd_layout
save_bd_design
validate_bd_design

# Export block design in PDF and SVG form.
source ../../project/vivado/export_bd_image.tcl

# Suppress specific warnings in the Vivado GUI:
set_msg_config -suppress -id {[Common 17-55]};      # Timing constraints "set_property" is empty
set_msg_config -suppress -id {[DRC 23-20]};         # Unconstraineed pads (false alarm)
set_msg_config -suppress -id {[Place 30-574]};      # Clock on a non-clock IO pad (CLOCK_DEDICATED_ROUTE)
set_msg_config -suppress -id {[Project 1-486]};     # Block diagram black-box (false alarm)
set_msg_config -suppress -id {[Timing 38-316]};     # Block diagram clock mismatch
set_msg_config -suppress -id {[Vivado 12-1790]};    # Eval license warning (false alarm)

# Set implementation to use Performance_Explore flow to mitigate timing issues inside the TEMAC
# block with 1588 support
set_property flow {Vivado Implementation 2019} [get_runs impl_1]
set_property strategy Performance_Explore [get_runs impl_1]

# Create block-diagram wrapper and set as top level.
set wrapper [make_wrapper -files [get_files ${design_name}.bd] -top]
add_files -norecurse $wrapper
set_property "top" ${design_name}_wrapper [get_filesets sources_1]
