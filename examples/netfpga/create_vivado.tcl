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
# This script creates a new Vivado project for the Digilent NetFPGA dev board,
# with a block diagram as the top level (i.e., using packaged IP-cores).
# To re-create the project, source this file in the Vivado Tcl Shell.

puts {Running create_vivado.tcl}

# Change to example project folder.
cd [file normalize [file dirname [info script]]]

# Set project-level properties depending on the selected board.
set target_part "XC7K325TFFG676-1"
set target_proj "netfpga"
set constr_synth "netfpga_synth.xdc"
set constr_impl "netfpga_impl.xdc"
set override_postbit ""

# There's no source in this project except the IP-cores!
set files_main ""

# Run the main project-creation script and install IP-cores.
source ../../project/vivado/shared_create.tcl
source ../../project/vivado/shared_ipcores.tcl
set proj_dir [get_property directory [current_project]]

# Create the block diagram
set design_name netfpga
create_bd_design $design_name
current_bd_design $design_name

# Top-level I/O ports
set system_clk [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 system_clk ]
set_property CONFIG.FREQ_HZ {200000000} $system_clk
set system_rst [ create_bd_port -dir I -type rst system_rst ]
set_property CONFIG.POLARITY {ACTIVE_LOW} $system_rst
set ddr3 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 ddr3 ]
set leds [ create_bd_port -dir O -from 3 -to 0 leds ]
set mdio_sck [ create_bd_port -dir O mdio_sck ]
set mdio_sda [ create_bd_port -dir IO mdio_sda ]
set phyrst0 [ create_bd_port -dir O rgmii0_rstn ]
set phyrst1 [ create_bd_port -dir O rgmii1_rstn ]
set phyrst2 [ create_bd_port -dir O rgmii2_rstn ]
set phyrst3 [ create_bd_port -dir O rgmii3_rstn ]
set pmod_ja [ create_bd_port -dir IO -from 3 -to 0 pmod_ja ]
set pmod_jb [ create_bd_port -dir IO -from 3 -to 0 pmod_jb ]
set rgmii0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:rgmii_rtl:1.0 rgmii0 ]
set rgmii1 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:rgmii_rtl:1.0 rgmii1 ]
set rgmii2 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:rgmii_rtl:1.0 rgmii2 ]
set rgmii3 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:rgmii_rtl:1.0 rgmii3 ]

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
# Note: Manually set clock buffers for MIG/IDELAYCTRL as a workaround for placement constraints.
#   https://support.xilinx.com/s/article/61601?language=en_US
current_bd_instance ..

create_bd_intf_pin -mode Master -vlnv aero.org:satcat5:ConfigBus_rtl:1.0 CfgBus
create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR3
create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 system_clk
create_bd_pin -dir O -type clk clk_100_00
create_bd_pin -dir O -type clk clk_125_00
create_bd_pin -dir O -type clk clk_125_90
create_bd_pin -dir O -type clk clk_200_00
create_bd_pin -dir O -from 0 -to 0 -type rst reset_p
create_bd_pin -dir I -type rst system_rst
create_bd_pin -dir I -type rst wdog_reset

set axi_crossbar_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_crossbar:2.1 axi_crossbar_0 ]
set_property -dict [ list \
    CONFIG.NUM_MI {3} \
] $axi_crossbar_0

set cfgbus_host_axi_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_host_axi:1.0 cfgbus_host_axi_0 ]

set clk_wiz_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_1 ]
set_property -dict [ list \
    CONFIG.CLKOUT1_DRIVES {BUFG} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {125} \
    CONFIG.CLKOUT2_DRIVES {BUFG} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125} \
    CONFIG.CLKOUT2_REQUESTED_PHASE {90} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.NUM_OUT_CLKS {2} \
    CONFIG.PRIM_IN_FREQ {100} \
    CONFIG.PRIM_SOURCE {No_buffer} \
    CONFIG.RESET_PORT {resetn} \
    CONFIG.RESET_TYPE {ACTIVE_LOW} \
    CONFIG.USE_PHASE_ALIGNMENT {true} \
] $clk_wiz_1

set mdm_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:mdm:3.2 mdm_1 ]
set_property -dict [ list \
    CONFIG.C_ADDR_SIZE {32} \
    CONFIG.C_M_AXI_ADDR_WIDTH {32} \
    CONFIG.C_USE_UART {1} \
] $mdm_1

set microblaze_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze:11.0 microblaze_0 ]
set_property -dict [ list \
    CONFIG.C_ADDR_TAG_BITS {0} \
    CONFIG.C_DEBUG_ENABLED {1} \
    CONFIG.C_D_AXI {1} \
    CONFIG.C_D_LMB {1} \
    CONFIG.C_I_LMB {1} \
    CONFIG.C_MMU_ZONES {2} \
    CONFIG.C_USE_BARREL {1} \
    CONFIG.C_USE_BRANCH_TARGET_CACHE {1} \
    CONFIG.C_USE_DCACHE {0} \
    CONFIG.C_USE_DIV {1} \
    CONFIG.C_USE_FPU {2} \
    CONFIG.C_USE_HW_MUL {2} \
    CONFIG.C_USE_ICACHE {0} \
    CONFIG.C_USE_MSR_INSTR {1} \
    CONFIG.C_USE_PCMP_INSTR {1} \
    CONFIG.G_TEMPLATE_LIST {2} \
] $microblaze_0

set microblaze_0_axi_intc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:4.1 microblaze_0_axi_intc ]
set_property -dict [ list \
    CONFIG.C_HAS_FAST {1} \
] $microblaze_0_axi_intc

set microblaze_0_axi_periph [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 microblaze_0_axi_periph ]
set_property -dict [ list \
    CONFIG.NUM_MI {2} \
] $microblaze_0_axi_periph

# Note: Name here must be short to prevent total-path-length errors on Windows.
set mig_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:mig_7series:4.2 mig_0 ]
set_property -dict [ list \
    CONFIG.BOARD_MIG_PARAM {Custom} \
    CONFIG.MIG_DONT_TOUCH_PARAM {Custom} \
    CONFIG.RESET_BOARD_INTERFACE {Custom} \
    CONFIG.XML_INPUT_FILE [file normalize ./netfpga_mig.prj] \
] $mig_0

set rst_clk_wiz_1_100M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_clk_wiz_1_100M ]
set_property -dict [list \
    CONFIG.C_AUX_RESET_HIGH {1} \
] $rst_clk_wiz_1_100M

set util_clkbuf0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.1 util_ds_buf_0 ]
set_property -dict [list CONFIG.C_BUF_TYPE {IBUFDS}] $util_clkbuf0
set util_clkbuf1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.1 util_ds_buf_1 ]
set_property -dict [list CONFIG.C_BUF_TYPE {BUFG}] $util_clkbuf1
set util_dlyctrl [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_idelay_ctrl:1.0 util_idelay_ctrl_0 ]

set xlconcat_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0 ]
set_property -dict [ list \
    CONFIG.NUM_PORTS {2} \
] $xlconcat_0

connect_bd_intf_net -intf_net system_clk \
    [get_bd_intf_pins system_clk] [get_bd_intf_pins util_ds_buf_0/CLK_IN_D]
connect_bd_intf_net -intf_net axi_crossbar_0_M00_AXI \
    [get_bd_intf_pins axi_crossbar_0/M00_AXI] [get_bd_intf_pins microblaze_0_axi_intc/s_axi]
connect_bd_intf_net -intf_net axi_crossbar_0_M01_AXI \
    [get_bd_intf_pins axi_crossbar_0/M01_AXI] [get_bd_intf_pins cfgbus_host_axi_0/CtrlAxi]
connect_bd_intf_net -intf_net axi_crossbar_0_M02_AXI \
    [get_bd_intf_pins axi_crossbar_0/M02_AXI] [get_bd_intf_pins mdm_1/S_AXI]
connect_bd_intf_net -intf_net cfgbus_host_axi_0_Cfg \
    [get_bd_intf_pins CfgBus] [get_bd_intf_pins cfgbus_host_axi_0/Cfg]
connect_bd_intf_net -intf_net microblaze_0_axi_dp \
    [get_bd_intf_pins microblaze_0/M_AXI_DP] [get_bd_intf_pins microblaze_0_axi_periph/S00_AXI]
connect_bd_intf_net -intf_net microblaze_0_axi_periph_M00_AXI \
    [get_bd_intf_pins microblaze_0_axi_periph/M00_AXI] [get_bd_intf_pins mig_0/S_AXI]
connect_bd_intf_net -intf_net microblaze_0_axi_periph_M01_AXI \
    [get_bd_intf_pins axi_crossbar_0/S00_AXI] [get_bd_intf_pins microblaze_0_axi_periph/M01_AXI]
connect_bd_intf_net -intf_net microblaze_0_debug \
    [get_bd_intf_pins mdm_1/MBDEBUG_0] [get_bd_intf_pins microblaze_0/DEBUG]
connect_bd_intf_net -intf_net microblaze_0_dlmb_1 \
    [get_bd_intf_pins microblaze_0/DLMB] [get_bd_intf_pins microblaze_0_local_memory/DLMB]
connect_bd_intf_net -intf_net microblaze_0_ilmb_1 \
    [get_bd_intf_pins microblaze_0/ILMB] [get_bd_intf_pins microblaze_0_local_memory/ILMB]
connect_bd_intf_net -intf_net microblaze_0_interrupt \
    [get_bd_intf_pins microblaze_0/INTERRUPT] [get_bd_intf_pins microblaze_0_axi_intc/interrupt]
connect_bd_intf_net -intf_net mig_0_DDR3 \
    [get_bd_intf_pins DDR3] [get_bd_intf_pins mig_0/DDR3]
connect_bd_net -net M00_ACLK_1 \
    [get_bd_pins microblaze_0_axi_periph/M00_ACLK] [get_bd_pins mig_0/ui_clk]
connect_bd_net -net aresetn_0_1 [get_bd_pins system_rst] \
    [get_bd_pins mig_0/sys_rst] [get_bd_pins rst_clk_wiz_1_100M/ext_reset_in]
connect_bd_net -net aux_reset_in_0_1 \
    [get_bd_pins wdog_reset] [get_bd_pins rst_clk_wiz_1_100M/aux_reset_in]
connect_bd_net -net cfgbus_host_axi_0_irq_out \
    [get_bd_pins cfgbus_host_axi_0/irq_out] [get_bd_pins xlconcat_0/In1]
connect_bd_net -net clk_wiz_1_clk_out1 \
    [get_bd_pins clk_125_00] [get_bd_pins clk_wiz_1/clk_out1]
connect_bd_net -net clk_wiz_1_clk_out2 \
    [get_bd_pins clk_125_90] [get_bd_pins clk_wiz_1/clk_out2]
connect_bd_net -net mdm_1_Interrupt \
    [get_bd_pins mdm_1/Interrupt] [get_bd_pins xlconcat_0/In0]
connect_bd_net -net mdm_1_debug_sys_rst \
    [get_bd_pins mdm_1/Debug_SYS_Rst] [get_bd_pins rst_clk_wiz_1_100M/mb_debug_sys_rst]
connect_bd_net -net mig_0_mmcm_locked \
    [get_bd_pins clk_wiz_1/resetn] [get_bd_pins mig_0/mmcm_locked]
connect_bd_net -net clk_wiz_1_locked \
    [get_bd_pins clk_wiz_1/locked] [get_bd_pins rst_clk_wiz_1_100M/dcm_locked]
connect_bd_net -net ublaze0_clk_200_raw \
    [get_bd_pins mig_0/sys_clk_i] \
    [get_bd_pins util_ds_buf_1/BUFG_I] \
    [get_bd_pins util_ds_buf_0/IBUF_OUT]
connect_bd_net -net ublaze0_clk_200_buf \
    [get_bd_pins clk_200_00] \
    [get_bd_pins mig_0/clk_ref_i] \
    [get_bd_pins util_idelay_ctrl_0/ref_clk] \
    [get_bd_pins util_ds_buf_1/BUFG_O]
connect_bd_net -net mig_0_ui_addn_clk_0 \
    [get_bd_pins clk_100_00] \
    [get_bd_pins axi_crossbar_0/aclk] \
    [get_bd_pins cfgbus_host_axi_0/axi_clk] \
    [get_bd_pins clk_wiz_1/clk_in1] \
    [get_bd_pins mdm_1/S_AXI_ACLK] \
    [get_bd_pins microblaze_0/Clk] \
    [get_bd_pins microblaze_0_axi_intc/processor_clk] \
    [get_bd_pins microblaze_0_axi_intc/s_axi_aclk] \
    [get_bd_pins microblaze_0_axi_periph/ACLK] \
    [get_bd_pins microblaze_0_axi_periph/M01_ACLK] \
    [get_bd_pins microblaze_0_axi_periph/S00_ACLK] \
    [get_bd_pins microblaze_0_local_memory/LMB_Clk] \
    [get_bd_pins mig_0/ui_addn_clk_0] \
    [get_bd_pins rst_clk_wiz_1_100M/slowest_sync_clk]
connect_bd_net -net rst_clk_wiz_1_100M_bus_struct_reset \
    [get_bd_pins microblaze_0_local_memory/SYS_Rst] \
    [get_bd_pins rst_clk_wiz_1_100M/bus_struct_reset]
connect_bd_net -net rst_clk_wiz_1_100M_mb_reset \
    [get_bd_pins microblaze_0/Reset] \
    [get_bd_pins microblaze_0_axi_intc/processor_rst] \
    [get_bd_pins rst_clk_wiz_1_100M/mb_reset]
connect_bd_net -net rst_clk_wiz_1_100M_peripheral_aresetn \
    [get_bd_pins axi_crossbar_0/aresetn] \
    [get_bd_pins cfgbus_host_axi_0/axi_aresetn] \
    [get_bd_pins mdm_1/S_AXI_ARESETN] \
    [get_bd_pins microblaze_0_axi_intc/s_axi_aresetn] \
    [get_bd_pins microblaze_0_axi_periph/ARESETN] \
    [get_bd_pins microblaze_0_axi_periph/M00_ARESETN] \
    [get_bd_pins microblaze_0_axi_periph/M01_ARESETN] \
    [get_bd_pins microblaze_0_axi_periph/S00_ARESETN] \
    [get_bd_pins mig_0/aresetn] \
    [get_bd_pins rst_clk_wiz_1_100M/peripheral_aresetn]
connect_bd_net -net rst_clk_wiz_1_100M_peripheral_reset \
    [get_bd_pins reset_p] \
    [get_bd_pins util_idelay_ctrl_0/rst] \
    [get_bd_pins rst_clk_wiz_1_100M/peripheral_reset]
connect_bd_net -net xlconcat_0_dout \
    [get_bd_pins microblaze_0_axi_intc/intr] \
    [get_bd_pins xlconcat_0/dout]

# Create and connect top-level
current_bd_instance ..

set cfgbus_split_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_split:1.0 cfgbus_split_0 ]
set_property -dict [ list \
    CONFIG.DLY_BUFFER {true} \
    CONFIG.PORT_COUNT {9} \
] $cfgbus_split_0

set port_mailmap_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_mailmap:1.0 port_mailmap_0 ]
set_property -dict [ list \
    CONFIG.DEV_ADDR {0} \
    CONFIG.PTP_ENABLE {true} \
    CONFIG.PTP_REF_HZ {100000000} \
] $port_mailmap_0

set cfgbus_led_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_led:1.0 cfgbus_led_0 ]
set_property -dict [ list \
    CONFIG.DEV_ADDR {1} \
] $cfgbus_led_0

set cfgbus_uart_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_uart:1.0 cfgbus_uart_0 ]
set_property -dict [ list \
    CONFIG.DEV_ADDR {2} \
] $cfgbus_uart_0

set port_serial_auto_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_serial_auto:1.0 port_serial_auto_0 ]
set_property -dict [ list \
    CONFIG.CFG_DEV_ADDR {3} \
    CONFIG.CFG_ENABLE {true} \
] $port_serial_auto_0

set port_serial_auto_1 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_serial_auto:1.0 port_serial_auto_1 ]
set_property -dict [ list \
    CONFIG.CFG_DEV_ADDR {4} \
    CONFIG.CFG_ENABLE {true} \
] $port_serial_auto_1

set cfgbus_timer_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_timer:1.0 cfgbus_timer_0 ]
set_property -dict [ list \
    CONFIG.DEV_ADDR {5} \
    CONFIG.EVT_ENABLE {false} \
] $cfgbus_timer_0

set ptp_reference_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:ptp_reference:1.0 ptp_reference_0 ]
set_property -dict [ list \
    CONFIG.CFG_DEV_ADDR {6} \
    CONFIG.CFG_ENABLE {true} \
] $ptp_reference_0

set cfgbus_mdio_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:cfgbus_mdio:1.0 cfgbus_mdio_0 ]
set_property -dict [ list \
    CONFIG.DEV_ADDR {7} \
] $cfgbus_mdio_0

set switch_core_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:switch_core:1.0 switch_core_0 ]
set_property -dict [ list \
    CONFIG.ALLOW_PRECOMMIT {true} \
    CONFIG.CFG_DEV_ADDR {8} \
    CONFIG.CFG_ENABLE {true} \
    CONFIG.CORE_CLK_HZ {125000000} \
    CONFIG.DATAPATH_BYTES {4} \
    CONFIG.PORT_COUNT {7} \
    CONFIG.STATS_DEVADDR {9} \
    CONFIG.STATS_ENABLE {true} \
    CONFIG.SUPPORT_PTP {true} \
    CONFIG.SUPPORT_VLAN {true} \
] $switch_core_0

set port_rgmii_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_rgmii:1.0 port_rgmii_0 ]
set_property -dict [ list \
    CONFIG.PTP_ENABLE {true} \
    CONFIG.PTP_REF_HZ {100000000} \
    CONFIG.RXCLK_LOCAL {true} \
    CONFIG.RXCLK_GLOBL {false} \
] $port_rgmii_0

set port_rgmii_1 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_rgmii:1.0 port_rgmii_1 ]
set_property -dict [ list \
    CONFIG.PTP_ENABLE {true} \
    CONFIG.PTP_REF_HZ {100000000} \
    CONFIG.RXCLK_LOCAL {true} \
    CONFIG.RXCLK_GLOBL {false} \
] $port_rgmii_1

set port_rgmii_2 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_rgmii:1.0 port_rgmii_2 ]
set_property -dict [ list \
    CONFIG.PTP_ENABLE {true} \
    CONFIG.PTP_REF_HZ {100000000} \
    CONFIG.RXCLK_LOCAL {true} \
    CONFIG.RXCLK_GLOBL {false} \
] $port_rgmii_2

set port_rgmii_3 [ create_bd_cell -type ip -vlnv aero.org:satcat5:port_rgmii:1.0 port_rgmii_3 ]
set_property -dict [ list \
    CONFIG.PTP_ENABLE {true} \
    CONFIG.PTP_REF_HZ {100000000} \
    CONFIG.RXCLK_LOCAL {true} \
    CONFIG.RXCLK_GLOBL {false} \
] $port_rgmii_3

set reset_hold_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:reset_hold:1.0 reset_hold_0 ]
set_property -dict [ list \
    CONFIG.RESET_HIGH {true} \
    CONFIG.RESET_HOLD {1000000} \
] $reset_hold_0

set switch_aux_0 [ create_bd_cell -type ip -vlnv aero.org:satcat5:switch_aux:1.0 switch_aux_0 ]
set_property -dict [ list \
    CONFIG.SCRUB_ENABLE {false} \
] $switch_aux_0

connect_bd_intf_net -intf_net system_clk \
    [get_bd_intf_ports system_clk] \
    [get_bd_intf_pins ublaze0/system_clk]
connect_bd_intf_net -intf_net cfgbus_split_0_Port00 \
    [get_bd_intf_pins cfgbus_split_0/Port00] \
    [get_bd_intf_pins port_mailmap_0/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port01 \
    [get_bd_intf_pins cfgbus_led_0/Cfg] [get_bd_intf_pins cfgbus_split_0/Port01]
connect_bd_intf_net -intf_net cfgbus_split_0_Port02 \
    [get_bd_intf_pins cfgbus_split_0/Port02] [get_bd_intf_pins cfgbus_uart_0/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port03 \
    [get_bd_intf_pins cfgbus_split_0/Port03] [get_bd_intf_pins port_serial_auto_0/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port04 \
    [get_bd_intf_pins cfgbus_split_0/Port04] [get_bd_intf_pins port_serial_auto_1/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port05 \
    [get_bd_intf_pins cfgbus_split_0/Port05] [get_bd_intf_pins cfgbus_timer_0/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port06 \
    [get_bd_intf_pins cfgbus_split_0/Port06] [get_bd_intf_pins ptp_reference_0/Cfg]
connect_bd_intf_net -intf_net cfgbus_split_0_Port07 \
    [get_bd_intf_pins cfgbus_mdio_0/Cfg] [get_bd_intf_pins cfgbus_split_0/Port07]
connect_bd_intf_net -intf_net cfgbus_split_0_Port08 \
    [get_bd_intf_pins cfgbus_split_0/Port08] [get_bd_intf_pins switch_core_0/Cfg]
connect_bd_intf_net -intf_net mig_0_DDR3 \
    [get_bd_intf_ports ddr3] [get_bd_intf_pins ublaze0/DDR3]
connect_bd_intf_net -intf_net port_mailmap_0_Eth \
    [get_bd_intf_pins port_mailmap_0/Eth] [get_bd_intf_pins switch_core_0/Port00]
connect_bd_intf_net -intf_net port_rgmii_0_Eth \
    [get_bd_intf_pins port_rgmii_0/Eth] [get_bd_intf_pins switch_core_0/Port01]
connect_bd_intf_net -intf_net port_rgmii_0_RGMII \
    [get_bd_intf_ports rgmii0] [get_bd_intf_pins port_rgmii_0/RGMII]
connect_bd_intf_net -intf_net port_rgmii_1_Eth \
    [get_bd_intf_pins port_rgmii_1/Eth] [get_bd_intf_pins switch_core_0/Port02]
connect_bd_intf_net -intf_net port_rgmii_1_RGMII \
    [get_bd_intf_ports rgmii1] [get_bd_intf_pins port_rgmii_1/RGMII]
connect_bd_intf_net -intf_net port_rgmii_2_Eth \
    [get_bd_intf_pins port_rgmii_2/Eth] [get_bd_intf_pins switch_core_0/Port03]
connect_bd_intf_net -intf_net port_rgmii_2_RGMII \
    [get_bd_intf_ports rgmii2] [get_bd_intf_pins port_rgmii_2/RGMII]
connect_bd_intf_net -intf_net port_rgmii_3_Eth \
    [get_bd_intf_pins port_rgmii_3/Eth] [get_bd_intf_pins switch_core_0/Port04]
connect_bd_intf_net -intf_net port_rgmii_3_RGMII \
    [get_bd_intf_ports rgmii3] [get_bd_intf_pins port_rgmii_3/RGMII]
connect_bd_intf_net -intf_net port_serial_auto_0_Eth \
    [get_bd_intf_pins port_serial_auto_0/Eth] [get_bd_intf_pins switch_core_0/Port05]
connect_bd_intf_net -intf_net port_serial_auto_1_Eth \
    [get_bd_intf_pins port_serial_auto_1/Eth] [get_bd_intf_pins switch_core_0/Port06]
connect_bd_intf_net -intf_net ptp_reference_0_PtpRef \
    [get_bd_intf_pins ptp_reference_0/PtpRef] [get_bd_intf_pins port_mailmap_0/PtpRef]
connect_bd_intf_net -intf_net ptp_reference_0_PtpRef \
    [get_bd_intf_pins ptp_reference_0/PtpRef] [get_bd_intf_pins port_rgmii_0/PtpRef]
connect_bd_intf_net -intf_net ptp_reference_0_PtpRef \
    [get_bd_intf_pins ptp_reference_0/PtpRef] [get_bd_intf_pins port_rgmii_1/PtpRef]
connect_bd_intf_net -intf_net ptp_reference_0_PtpRef \
    [get_bd_intf_pins ptp_reference_0/PtpRef] [get_bd_intf_pins port_rgmii_2/PtpRef]
connect_bd_intf_net -intf_net ptp_reference_0_PtpRef \
    [get_bd_intf_pins ptp_reference_0/PtpRef] [get_bd_intf_pins port_rgmii_3/PtpRef]
connect_bd_intf_net -intf_net ublaze0_CfgBus \
    [get_bd_intf_pins cfgbus_split_0/Cfg] [get_bd_intf_pins ublaze0/CfgBus]
connect_bd_net -net pmod_ja \
    [get_bd_ports pmod_ja] [get_bd_pins port_serial_auto_0/ext_pads]
connect_bd_net -net pmod_jb \
    [get_bd_ports pmod_jb] [get_bd_pins port_serial_auto_1/ext_pads]
connect_bd_net -net mdio_sda \
    [get_bd_ports mdio_sda] [get_bd_pins cfgbus_mdio_0/mdio_data]
connect_bd_net -net aresetn_0_1 \
    [get_bd_ports system_rst] [get_bd_pins ublaze0/system_rst]
connect_bd_net -net cfgbus_led_0_led_out \
    [get_bd_ports leds] [get_bd_pins cfgbus_led_0/led_out]
connect_bd_net -net cfgbus_mdio_0_mdio_sck \
    [get_bd_ports mdio_sck] [get_bd_pins cfgbus_mdio_0/mdio_clk]
connect_bd_net -net switch_aux_0_scrub_req_t \
    [get_bd_pins switch_aux_0/scrub_req_t] [get_bd_pins switch_core_0/scrub_req_t]
connect_bd_net -net switch_aux_0_status_uart \
    [get_bd_pins cfgbus_uart_0/uart_rxd] [get_bd_pins switch_aux_0/status_uart]
connect_bd_net -net switch_core_0_errvec_t \
    [get_bd_pins switch_aux_0/errvec_00] [get_bd_pins switch_core_0/errvec_t]
connect_bd_net -net ublaze0_clk_100_00 \
    [get_bd_pins port_serial_auto_0/refclk] \
    [get_bd_pins port_serial_auto_1/refclk] \
    [get_bd_pins ptp_reference_0/ref_clk] \
    [get_bd_pins reset_hold_0/clk] \
    [get_bd_pins switch_aux_0/scrub_clk] \
    [get_bd_pins ublaze0/clk_100_00]
connect_bd_net -net ublaze0_clk_125_00 \
    [get_bd_pins port_rgmii_0/clk_125] \
    [get_bd_pins port_rgmii_1/clk_125] \
    [get_bd_pins port_rgmii_2/clk_125] \
    [get_bd_pins port_rgmii_3/clk_125] \
    [get_bd_pins switch_core_0/core_clk] \
    [get_bd_pins ublaze0/clk_125_00]
connect_bd_net -net ublaze0_clk_125_90 \
    [get_bd_pins port_rgmii_0/clk_txc] \
    [get_bd_pins port_rgmii_1/clk_txc] \
    [get_bd_pins port_rgmii_2/clk_txc] \
    [get_bd_pins port_rgmii_3/clk_txc] \
    [get_bd_pins ublaze0/clk_125_90]
connect_bd_net -net ublaze0_reset_p \
    [get_bd_pins port_rgmii_0/reset_p] \
    [get_bd_pins port_rgmii_1/reset_p] \
    [get_bd_pins port_rgmii_2/reset_p] \
    [get_bd_pins port_rgmii_3/reset_p] \
    [get_bd_pins port_serial_auto_0/reset_p] \
    [get_bd_pins port_serial_auto_1/reset_p] \
    [get_bd_pins ptp_reference_0/reset_p] \
    [get_bd_pins reset_hold_0/aresetp] \
    [get_bd_pins switch_aux_0/reset_p] \
    [get_bd_pins switch_core_0/reset_p] \
    [get_bd_pins ublaze0/reset_p]
connect_bd_net -net phyrstn \
    [get_bd_ports rgmii0_rstn] \
    [get_bd_ports rgmii1_rstn] \
    [get_bd_ports rgmii2_rstn] \
    [get_bd_ports rgmii3_rstn] \
    [get_bd_pins reset_hold_0/reset_n]
connect_bd_net -net wdog_reset [get_bd_pins cfgbus_timer_0/wdog_resetp] [get_bd_pins ublaze0/wdog_reset]

# Create address segments
create_bd_addr_seg -range 0x00100000 -offset 0x44A00000 \
    [get_bd_addr_spaces ublaze0/microblaze_0/Data] \
    [get_bd_addr_segs ublaze0/cfgbus_host_axi_0/CtrlAxi/CtrlAxi_addr] SEG_cfgbus_host_axi_0_CtrlAxi_addr
create_bd_addr_seg -range 0x00040000 -offset 0x00000000 \
    [get_bd_addr_spaces ublaze0/microblaze_0/Data] \
    [get_bd_addr_segs ublaze0/microblaze_0_local_memory/dlmb_bram_if_cntlr/SLMB/Mem] SEG_dlmb_bram_if_cntlr_Mem
create_bd_addr_seg -range 0x00040000 -offset 0x00000000 \
    [get_bd_addr_spaces ublaze0/microblaze_0/Instruction] \
    [get_bd_addr_segs ublaze0/microblaze_0_local_memory/ilmb_bram_if_cntlr/SLMB/Mem] SEG_ilmb_bram_if_cntlr_Mem
create_bd_addr_seg -range 0x00001000 -offset 0x41400000 \
    [get_bd_addr_spaces ublaze0/microblaze_0/Data] \
    [get_bd_addr_segs ublaze0/mdm_1/S_AXI/Reg] SEG_mdm_1_Reg
create_bd_addr_seg -range 0x00010000 -offset 0x41200000 \
    [get_bd_addr_spaces ublaze0/microblaze_0/Data] \
    [get_bd_addr_segs ublaze0/microblaze_0_axi_intc/S_AXI/Reg] SEG_microblaze_0_axi_intc_Reg
create_bd_addr_seg -range 0x20000000 -offset 0x80000000 \
    [get_bd_addr_spaces ublaze0/microblaze_0/Data] \
    [get_bd_addr_segs ublaze0/mig_0/memmap/memaddr] SEG_mig_0_memaddr

# Cleanup
regenerate_bd_layout
save_bd_design
validate_bd_design

# Export block design in PDF and SVG form.
source ../../project/vivado/export_bd_image.tcl

# Suppress specific warnings in the Vivado GUI:
set_msg_config -suppress -id {[Common 17-55]};          # Timing constraints "set_property" is empty
set_msg_config -suppress -id {[Common 17-576]};         # Deprecated "use_project_ipc" warning
set_msg_config -suppress -id {[Constraints 18-5210]};   # No constraints warning (false alarm)
set_msg_config -suppress -id {[Project 1-498]};         # Block diagram black-box (false alarm)
set_msg_config -suppress -id {[Timing 38-316]};         # Block diagram clock mismatch

# Create block-diagram wrapper and set as top level.
set wrapper [make_wrapper -files [get_files ${design_name}.bd] -top]
add_files -norecurse $wrapper
set_property "top" ${design_name}_wrapper [get_filesets sources_1]
