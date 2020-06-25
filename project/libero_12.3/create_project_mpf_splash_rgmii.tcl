##########################################################################
## Copyright 2019 The Aerospace Corporation
##
## This file is part of SatCat5.
##
## SatCat5 is free software: you can redistribute it and/or modify it under
## the terms of the GNU Lesser General Public License as published by the
## Free Software Foundation, either version 3 of the License, or (at your
## option) any later version.
##
## SatCat5 is distributed in the hope that it will be useful, but WITHOUT
## ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
## FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
## License for more details.
##
## You should have received a copy of the GNU Lesser General Public License
## along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
##########################################################################

puts "In build project tcl script"

set target_proj switch_mpf_splash_rgmii
set target_top "switch_top_mpf_splash_rgmii"
set constr_synth "./mpf_splash_rgmii_synth.pdc"
set constr_impl "./mpf_splash_rgmii_impl.sdc"

# Initialize project
new_project -location ./$target_proj \
            -name $target_proj \
            -project_description {} \
            -block_mode 0 \
            -standalone_peripheral_initialization 0 \
            -instantiate_in_smartdesign 1 \
            -ondemand_build_dh 1 \
            -hdl {VHDL} \
            -family {PolarFire} \
            -die {MPF300TS_ES} \
            -package {FCG484} \
            -speed {-1} \
            -die_voltage {1.0} \
            -part_range {EXT} \
            -adv_options {IO_DEFT_STD:LVCMOS 3.3V} \
            -adv_options {RESTRICTPROBEPINS:1} \
            -adv_options {RESTRICTSPIPINS:0} \
            -adv_options {SYSTEM_CONTROLLER_SUSPEND_MODE:0} \
            -adv_options {TEMPR:EXT} \
            -adv_options {VCCI_1.2_VOLTR:EXT} \
            -adv_options {VCCI_1.5_VOLTR:EXT} \
            -adv_options {VCCI_1.8_VOLTR:EXT} \
            -adv_options {VCCI_2.5_VOLTR:EXT} \
            -adv_options {VCCI_3.3_VOLTR:EXT} \
            -adv_options {VOLTR:EXT} 

# Configure device
set_device -family {PolarFire} \
           -die {MPF300TS_ES} \
           -package {FCG484} \
           -speed {-1} \
           -die_voltage {1.0} \
           -part_range {EXT} \
           -adv_options {IO_DEFT_STD:LVCMOS 3.3V} \
           -adv_options {RESTRICTPROBEPINS:1} \
           -adv_options {RESTRICTSPIPINS:0} \
           -adv_options {SYSTEM_CONTROLLER_SUSPEND_MODE:0} \
           -adv_options {TEMPR:EXT} \
           -adv_options {VCCI_1.2_VOLTR:EXT} \
           -adv_options {VCCI_1.5_VOLTR:EXT} \
           -adv_options {VCCI_1.8_VOLTR:EXT} \
           -adv_options {VCCI_2.5_VOLTR:EXT} \
           -adv_options {VCCI_3.3_VOLTR:EXT} \
           -adv_options {VOLTR:EXT} 
   
# Run IP generator script
source "./gen_ip.tcl"

create_links \
         -convert_EDN_to_HDL 0 \
         -hdl_source {../../src/vhdl/microsemi/clkgen_rgmii.vhd} \
         -hdl_source {../../src/vhdl/microsemi/io_polarfire.vhd} \
         -hdl_source {../../src/vhdl/microsemi/switch_top_mpf_splash_rgmii.vhd} \
         -hdl_source {../../src/vhdl/microsemi/synchronization_polarfire.vhd} \
         -hdl_source {../../src/vhdl/microsemi/lutram_polarfire.vhd} \
         -hdl_source {../../src/vhdl/common/common_functions.vhd} \
         -hdl_source {../../src/vhdl/common/config_file2rom.vhd} \
         -hdl_source {../../src/vhdl/common/config_mdio_rom.vhd} \
         -hdl_source {../../src/vhdl/common/config_port_eth.vhd} \
         -hdl_source {../../src/vhdl/common/config_port_uart.vhd} \
         -hdl_source {../../src/vhdl/common/config_read_command.vhd} \
         -hdl_source {../../src/vhdl/common/config_send_status.vhd} \
         -hdl_source {../../src/vhdl/common/error_reporting.vhd} \
         -hdl_source {../../src/vhdl/common/eth_dec8b10b.vhd} \
         -hdl_source {../../src/vhdl/common/eth_enc8b10b.vhd} \
         -hdl_source {../../src/vhdl/common/eth_enc8b10b_table.vhd} \
         -hdl_source {../../src/vhdl/common/eth_frame_adjust.vhd} \
         -hdl_source {../../src/vhdl/common/eth_frame_check.vhd} \
         -hdl_source {../../src/vhdl/common/eth_frame_common.vhd} \
         -hdl_source {../../src/vhdl/common/eth_preambles.vhd} \
         -hdl_source {../../src/vhdl/common/io_mdio_writer.vhd} \
         -hdl_source {../../src/vhdl/common/io_spi_clkin.vhd} \
         -hdl_source {../../src/vhdl/common/io_spi_clkout.vhd} \
         -hdl_source {../../src/vhdl/common/io_uart.vhd} \
         -hdl_source {../../src/vhdl/common/led_types.vhd} \
         -hdl_source {../../src/vhdl/common/mac_lookup_binary.vhd} \
         -hdl_source {../../src/vhdl/common/mac_lookup_brute.vhd} \
         -hdl_source {../../src/vhdl/common/mac_lookup_generic.vhd} \
         -hdl_source {../../src/vhdl/common/mac_lookup_parshift.vhd} \
         -hdl_source {../../src/vhdl/common/mac_lookup_simple.vhd} \
         -hdl_source {../../src/vhdl/common/mac_lookup_stream.vhd} \
         -hdl_source {../../src/vhdl/common/mac_lookup_lutram.vhd} \
         -hdl_source {../../src/vhdl/common/packet_delay.vhd} \
         -hdl_source {../../src/vhdl/common/packet_fifo.vhd} \
         -hdl_source {../../src/vhdl/common/port_adapter.vhd} \
         -hdl_source {../../src/vhdl/common/port_axi_mailbox.vhd} \
         -hdl_source {../../src/vhdl/common/port_crosslink.vhd} \
         -hdl_source {../../src/vhdl/common/port_passthrough.vhd} \
         -hdl_source {../../src/vhdl/common/port_rgmii.vhd} \
         -hdl_source {../../src/vhdl/common/port_rmii.vhd} \
         -hdl_source {../../src/vhdl/common/port_serial_auto.vhd} \
         -hdl_source {../../src/vhdl/common/port_serial_spi_clkin.vhd} \
         -hdl_source {../../src/vhdl/common/port_serial_spi_clkout.vhd} \
         -hdl_source {../../src/vhdl/common/port_serial_uart_2wire.vhd} \
         -hdl_source {../../src/vhdl/common/port_serial_uart_4wire.vhd} \
         -hdl_source {../../src/vhdl/common/port_sgmii_common.vhd} \
         -hdl_source {../../src/vhdl/common/port_statistics.vhd} \
         -hdl_source {../../src/vhdl/common/round_robin.vhd} \
         -hdl_source {../../src/vhdl/common/scrub_placeholder.vhd} \
         -hdl_source {../../src/vhdl/common/slip_decoder.vhd} \
         -hdl_source {../../src/vhdl/common/slip_encoder.vhd} \
         -hdl_source {../../src/vhdl/common/smol_fifo.vhd} \
         -hdl_source {../../src/vhdl/common/switch_aux.vhd} \
         -hdl_source {../../src/vhdl/common/switch_core.vhd} \
         -hdl_source {../../src/vhdl/common/switch_dual.vhd} \
         -hdl_source {../../src/vhdl/common/switch_types.vhd} 

# Import timing and physical constraints
create_links \
         -convert_EDN_to_HDL 0 \
         -io_pdc ${constr_synth} \
         -sdc ${constr_impl}

build_design_hierarchy 
set_root -module ${target_top}::work

# Set constraint usage
organize_tool_files -tool {SYNTHESIZE}   -file ${constr_impl}                       -module {switch_top_mpf_splash_rgmii::work} -input_type {constraint} 
organize_tool_files -tool {PLACEROUTE}   -file ${constr_impl} -file ${constr_synth} -module {switch_top_mpf_splash_rgmii::work} -input_type {constraint} 
organize_tool_files -tool {VERIFYTIMING} -file ${constr_impl}                       -module {switch_top_mpf_splash_rgmii::work} -input_type {constraint} 

# Enable hold fix in p&r
configure_tool -name {PLACEROUTE} \
               -params {DELAY_ANALYSIS:MAX} \
               -params {EFFORT_LEVEL:false} \
               -params {GB_DEMOTION:true} \
               -params {INCRPLACEANDROUTE:false} \
               -params {IOREG_COMBINING:false} \
               -params {MULTI_PASS_CRITERIA:VIOLATIONS} \
               -params {MULTI_PASS_LAYOUT:false} \
               -params {NUM_MULTI_PASSES:5} \
               -params {PDPR:false} \
               -params {RANDOM_SEED:0} \
               -params {REPAIR_MIN_DELAY:true} \
               -params {REPLICATION:false} \
               -params {SLACK_CRITERIA:WORST_SLACK} \
               -params {SPECIFIC_CLOCK:} \
               -params {START_SEED_INDEX:1} \
               -params {STOP_ON_FIRST_PASS:false} \
               -params {TDPR:true} 


