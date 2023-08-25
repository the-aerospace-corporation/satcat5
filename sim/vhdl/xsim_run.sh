#!/bin/bash -f
# ------------------------------------------------------------------------
# Copyright 2019, 2020, 2021, 2022, 2023 The Aerospace Corporation
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
# This shell script compiles and runs all VHDL unit tests.
# The "run_all" function must be updated to add any new unit test or to
# change the simulation duration for an existing one.
#

# Find relevant VHDL files, add to project, and compile them all.
compile_all()
{
    # Create a new working folder with an empty .prj file.
    echo "******************** CREATING PROJECT"
    rm -rf $work_folder
    mkdir $work_folder
    echo -n > $work_folder/vhdl.prj

    # Define some helper functions:
    find_vhdl () {
        find $1 -name \*.vhd
    }
    add_to_prj () {
        sed -r 's/(.*)/vhdl xil_defaultlib \"..\/\1\"/' >> $work_folder/vhdl.prj
    }

    # Find source files in each folder.
    # Use "grep -v" to ignore specific filenames.
    find_vhdl "../../src/vhdl/common" | add_to_prj
    find_vhdl "../../src/vhdl/xilinx" | \
        egrep -v "(converter_zed_top|port_sgmii_gtx|scrub_xilinx|ultraplus_|ultrascale_)" | \
        add_to_prj
    find_vhdl "../../sim/vhdl" | add_to_prj

    # Compile design files
    echo "******************** COMPILING PROJECT"
    logfile=$work_folder/compile_vhdl.log
    opts_xvhdl="-m64 -relax -prj vhdl.prj -work $work_folder"
    (cd $work_folder && xvhdl $opts_xvhdl) 2>&1 | tee $logfile

    # Check for errors in the log.
    if grep ERROR $logfile; then
        echo "******************** COMPILE FAILED"
        return 1  # Compilation errors, can't run simulation
    else
        echo "******************** COMPILE SUCCESS"
        return 0  # No compile errors, proceed with simulation
    fi
}

# Simulate a single file ($1) for a given time ($2)
# Optional: Set a single generic ($3) to specified value ($4)
simulate_one()
{
    # Parallel simulations enabled? Execute 1 in N, skip the rest.
    par_count=$(((par_count+1) % PARALLEL_SIMS))
    par_local=$(((PARALLEL_PHASE+1) % PARALLEL_SIMS))
    if [[ $PARALLEL_SIMS -gt 1 && $par_count -ne $par_local ]]; then return; fi

    # Does this simulation need to set any generic parameters?
    if [[ $# -eq 4 ]]; then
        vars_xelab="--generic_top $3=$4"
    else
        vars_xelab=""
    fi

    # Pre-simulation setup (aka "Elaboration")
    echo "******************** ELABORATING $1"
    opts_xelab="--relax --debug off --mt auto -m64 -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip --snapshot tb_snapshot"
    args_xelab="xil_defaultlib.$1 -log elaborate_$1.log"
    (cd $work_folder && xelab $vars_xelab $opts_xelab $args_xelab)

    # Prep a TCL script for Vivado to run.
    echo "******************** SIMULATING $1 for $2"
    simcmd=cmd_tmp.tcl
    simout=simulate_$1.log
    echo "run $2" > $work_folder/$simcmd
    echo "quit" >> $work_folder/$simcmd

    # Launch simulation in XSIM.
    # To avoid giant logs on failure, limit the console output to the first
    # 1000 lines and limit simulation output to 20,000 lines.
    opts_xsim="-tclbatch $simcmd -onerror quit"
    (cd $work_folder && xsim tb_snapshot $opts_xsim -log $simout) | head -n 1000
    sed -i '20001,$ d' $work_folder/$simout
}

simulate_all()
{
    # Run each unit test for the designated time:
    simulate_one cfgbus_common_tb 1ms
    simulate_one cfgbus_host_apb_tb 1ms
    simulate_one cfgbus_host_axi_tb 2ms
    simulate_one cfgbus_host_eth_tb 1ms
    simulate_one cfgbus_host_rom_tb 100us
    simulate_one cfgbus_host_uart_tb 11ms
    simulate_one cfgbus_host_wishbone_tb 1ms
    simulate_one cfgbus_i2c_tb 2ms
    simulate_one cfgbus_port_stats_tb 3ms
    simulate_one cfgbus_spi_tb 1ms
    simulate_one cfgbus_to_axilite_tb 100us
    simulate_one cfgbus_uart_tb 2ms
    simulate_one config_file2rom_tb 1us TEST_DATA_FOLDER $test_data_folder
    simulate_one config_mdio_rom_tb 30ms
    simulate_one config_port_test_tb 4ms
    simulate_one config_send_status_tb 1ms
    simulate_one eth_all8b10b_tb 2ms
    simulate_one eth_frame_adjust_tb 3ms
    simulate_one eth_frame_check_tb 10ms
    simulate_one eth_frame_parcrc_tb 1ms
    simulate_one eth_frame_vstrip_tb 1ms
    simulate_one eth_frame_vtag_tb 1ms
    simulate_one eth_pause_ctrl_tb 3ms
    simulate_one eth_preamble_tb 2ms
    simulate_one fifo_large_sync_tb 10ms
    simulate_one fifo_packet_tb 10ms
    simulate_one fifo_priority_tb 7ms
    simulate_one fifo_repack_tb 1ms
    simulate_one fifo_smol_async_tb 5ms
    simulate_one fifo_smol_resize_tb 1ms
    simulate_one fifo_smol_sync_tb 10ms
    simulate_one io_error_reporting_tb 10ms
    simulate_one io_i2c_tb 1ms
    simulate_one io_mdio_readwrite_tb 3ms
    simulate_one io_spi_tb 1ms
    simulate_one io_text_lcd_tb 280ms
    simulate_one mac_counter_tb 1ms
    simulate_one mac_igmp_simple_tb 4ms
    simulate_one mac_lookup_tb 2ms
    simulate_one mac_priority_tb 1ms
    simulate_one mac_query_tb 1ms
    simulate_one mac_vlan_mask_tb 2ms
    simulate_one mac_vlan_rate_tb 2ms
    simulate_one packet_delay_tb 1ms
    simulate_one packet_inject_tb 15ms
    simulate_one packet_round_robin_tb 20ms
    simulate_one port_inline_status_tb 4ms
    simulate_one port_mailbox_tb 2ms
    simulate_one port_mailmap_tb 3ms
    simulate_one port_rgmii_tb 11ms
    simulate_one port_rmii_tb 30ms
    simulate_one port_sgmii_common_tb 1ms
    simulate_one port_serial_auto_tb 200ms
    simulate_one port_serial_i2c_tb 400ms
    simulate_one port_serial_spi_tb 85ms
    simulate_one port_serial_uart_4wire_tb 700ms
    simulate_one port_serial_uart_2wire_tb 470ms
    simulate_one port_statistics_tb 2ms
    simulate_one port_stream_tb 1ms
    simulate_one ptp_adjust_tb 6ms
    simulate_one ptp_clksynth_tb 2ms
    simulate_one ptp_counter_tb 40ms
    simulate_one ptp_egress_tb 3ms
    simulate_one ptp_filter_tb 5ms
    simulate_one ptp_realsync_tb 7ms
    simulate_one ptp_realtime_tb 1ms
    simulate_one router_arp_cache_tb 2ms
    simulate_one router_arp_proxy_tb 2ms
    simulate_one router_arp_request_tb 1ms
    simulate_one router_arp_update_tb 1ms
    simulate_one router_config_tb 1ms
    simulate_one router_ip_gateway_tb 22ms
    simulate_one router_mac_replace_tb 11ms
    simulate_one router_inline_top_tb 2ms
    simulate_one sgmii_data_slip_tb 16ms
    simulate_one sgmii_serdes_rx_tb 1ms
    simulate_one sgmii_data_sync_tb 110ms
    simulate_one sine_interp_tb 2ms
    simulate_one sine_table_tb 250us
    simulate_one slip_decoder_tb 20us
    simulate_one slip_encoder_tb 4ms
    simulate_one switch_core_tb 12ms
    simulate_one tcam_cache_tb 2ms
    simulate_one tcam_core_tb 1ms
    simulate_one tcam_maxlen_tb 7ms
}

# Abort immediately on any non-zero return code.
set -e

# Optional configuration for parallel simulations.
# (Default = Run all simulations sequentially.)
par_count=0
PARALLEL_PHASE=${PARALLEL_PHASE:-0}
PARALLEL_SIMS=${PARALLEL_SIMS:-1}

# Set working folder.
work_folder=xsim_tmp_${PARALLEL_PHASE}

# Initial setup (default version if unspecified)
VIVADO_VERSION=${VIVADO_VERSION:-2015.4}
start_time=$(date +%T.%N)
test_data_folder=$(realpath ../data)
source /opt/Xilinx/Vivado/${VIVADO_VERSION}/settings64.sh

# Create project and compile VHDL source.
# If successful, run all simulations.
compile_all && simulate_all

# Print elapsed time
end_time=$(date +%T.%N)
echo "Started: " $start_time
echo "Finished:" $end_time

