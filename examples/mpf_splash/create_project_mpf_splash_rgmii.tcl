# ------------------------------------------------------------------------
# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------


puts "In create project tcl script"

set target_proj switch_mpf_splash_rgmii
set target_top "switch_top_mpf_splash_rgmii"
set constr_synth "./mpf_splash_rgmii_synth.pdc"
set constr_impl "./mpf_splash_rgmii_impl.sdc"

set die   MPF300T
set range EXT


# If the argument "100T" is passed, the project will be built for the MPF100T part.
# This does not correspond to any board hardware, but allows us to test the build
# without upgrading to either a gold license or libero 12.5
if {(([llength $argv] == 1) && ([lindex $argv 0] == "100T"))} {
    puts "Creating for 100T device"

    set target_proj ${target_proj}_100T
    set die MPF100T
    set range IND
} 

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
            -die $die \
            -package {FCG484} \
            -speed {-1} \
            -die_voltage {1.0} \
            -part_range $range \
            -adv_options {IO_DEFT_STD:LVCMOS 3.3V} \
            -adv_options {RESTRICTPROBEPINS:1} \
            -adv_options {RESTRICTSPIPINS:0} \
            -adv_options {SYSTEM_CONTROLLER_SUSPEND_MODE:0} \
            -adv_options TEMPR:$range \
            -adv_options VCCI_1.2_VOLTR:$range \
            -adv_options VCCI_1.5_VOLTR:$range \
            -adv_options VCCI_1.8_VOLTR:$range \
            -adv_options VCCI_2.5_VOLTR:$range \
            -adv_options VCCI_3.3_VOLTR:$range \
            -adv_options VOLTR:$range 

# Configure device
set_device -family {PolarFire} \
           -die $die \
           -package {FCG484} \
           -speed {-1} \
           -die_voltage {1.0} \
           -part_range $range \
           -adv_options {IO_DEFT_STD:LVCMOS 3.3V} \
           -adv_options {RESTRICTPROBEPINS:1} \
           -adv_options {RESTRICTSPIPINS:0} \
           -adv_options {SYSTEM_CONTROLLER_SUSPEND_MODE:0} \
           -adv_options TEMPR:$range \
           -adv_options VCCI_1.2_VOLTR:$range \
           -adv_options VCCI_1.5_VOLTR:$range \
           -adv_options VCCI_1.8_VOLTR:$range \
           -adv_options VCCI_2.5_VOLTR:$range \
           -adv_options VCCI_3.3_VOLTR:$range \
           -adv_options VOLTR:$range 
   
# Run IP generator script
source "../../project/libero/gen_ip.tcl"

create_links \
         -convert_EDN_to_HDL 0 \
         -hdl_source {./switch_top_mpf_splash_rgmii.vhd} \
         -hdl_source {../../src/vhdl/microsemi/clkgen_rgmii.vhd} \
         -hdl_source {../../src/vhdl/microsemi/polarfire_io.vhd} \
         -hdl_source {../../src/vhdl/microsemi/polarfire_sync.vhd} \
         -hdl_source {../../src/vhdl/microsemi/polarfire_mem.vhd} \
         -hdl_source {../../src/vhdl/common/cfgbus_common.vhd} \
         -hdl_source {../../src/vhdl/common/common_functions.vhd} \
         -hdl_source {../../src/vhdl/common/common_primitives.vhd} \
         -hdl_source {../../src/vhdl/common/config_mdio_rom.vhd} \
         -hdl_source {../../src/vhdl/common/eth_frame_adjust.vhd} \
         -hdl_source {../../src/vhdl/common/eth_frame_check.vhd} \
         -hdl_source {../../src/vhdl/common/eth_frame_common.vhd} \
         -hdl_source {../../src/vhdl/common/eth_frame_parcrc.vhd} \
         -hdl_source {../../src/vhdl/common/eth_frame_vstrip.vhd} \
         -hdl_source {../../src/vhdl/common/eth_frame_vtag.vhd} \
         -hdl_source {../../src/vhdl/common/eth_pause_ctrl.vhd} \
         -hdl_source {../../src/vhdl/common/eth_preamble_rx.vhd} \
         -hdl_source {../../src/vhdl/common/eth_preamble_tx.vhd} \
         -hdl_source {../../src/vhdl/common/fifo_packet.vhd} \
         -hdl_source {../../src/vhdl/common/fifo_priority.vhd} \
         -hdl_source {../../src/vhdl/common/fifo_repack.vhd} \
         -hdl_source {../../src/vhdl/common/fifo_smol_async.vhd} \
         -hdl_source {../../src/vhdl/common/fifo_smol_sync.vhd} \
         -hdl_source {../../src/vhdl/common/io_clock_detect.vhd}\
         -hdl_source {../../src/vhdl/common/io_error_reporting.vhd} \
         -hdl_source {../../src/vhdl/common/io_leds.vhd} \
         -hdl_source {../../src/vhdl/common/io_mdio_writer.vhd} \
         -hdl_source {../../src/vhdl/common/io_uart.vhd} \
         -hdl_source {../../src/vhdl/common/mac_core.vhd} \
         -hdl_source {../../src/vhdl/common/mac_igmp_simple.vhd} \
         -hdl_source {../../src/vhdl/common/mac_lookup.vhd} \
         -hdl_source {../../src/vhdl/common/mac_priority.vhd} \
         -hdl_source {../../src/vhdl/common/mac_vlan_mask.vhd} \
         -hdl_source {../../src/vhdl/common/packet_delay.vhd} \
         -hdl_source {../../src/vhdl/common/packet_inject.vhd} \
         -hdl_source {../../src/vhdl/common/packet_round_robin.vhd} \
         -hdl_source {../../src/vhdl/common/port_adapter.vhd} \
         -hdl_source {../../src/vhdl/common/port_rgmii.vhd} \
         -hdl_source {../../src/vhdl/common/port_serial_uart_4wire.vhd} \
         -hdl_source {../../src/vhdl/common/scrub_placeholder.vhd} \
         -hdl_source {../../src/vhdl/common/slip_decoder.vhd} \
         -hdl_source {../../src/vhdl/common/slip_encoder.vhd} \
         -hdl_source {../../src/vhdl/common/switch_aux.vhd} \
         -hdl_source {../../src/vhdl/common/switch_core.vhd} \
         -hdl_source {../../src/vhdl/common/switch_port_rx.vhd} \
         -hdl_source {../../src/vhdl/common/switch_port_tx.vhd} \
         -hdl_source {../../src/vhdl/common/switch_types.vhd} \
         -hdl_source {../../src/vhdl/common/tcam_cache_nru2.vhd} \
         -hdl_source {../../src/vhdl/common/tcam_cache_plru.vhd} \
         -hdl_source {../../src/vhdl/common/tcam_core.vhd} \
         -hdl_source {../../src/vhdl/common/tcam_maxlen.vhd}

# Import timing and physical constraints
create_links \
         -convert_EDN_to_HDL 0 \
         -io_pdc ${constr_synth} \
         -sdc ${constr_impl}

build_design_hierarchy 
set_root -module ${target_top}::work

# Set constraint usage
organize_tool_files -tool {SYNTHESIZE}   -file ${constr_impl}                       -module ${target_top}::work -input_type {constraint} 
organize_tool_files -tool {PLACEROUTE}   -file ${constr_impl} -file ${constr_synth} -module ${target_top}::work -input_type {constraint} 
organize_tool_files -tool {VERIFYTIMING} -file ${constr_impl}                       -module ${target_top}::work -input_type {constraint} 

# Derive additional constraints from IP blocks
# We have already specified all derived constraints in mpf_splash_rgmii_impl.sdc
#derive_constraints_sdc

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

save_project
