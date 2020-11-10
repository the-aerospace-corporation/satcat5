# ------------------------------------------------------------------------
# Copyright 2019 The Aerospace Corporation
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
# This script creates a new Modelsim project, for running simulations.
# It has been tested with ModelSim 10.0a, but should work with most other
# versions as well.
#
# This project requires the Xilinx UNISIM library. Compile this first,
# using the instructions provided by Xilinx:
#    https://www.xilinx.com/support/answers/64083.html
#
# To create the project, provide the UNISIM path:
#    do create_project.tcl "path/to/unisim/library"
#

# Check that user provided unisim path:
if {$argc != 1} {
    return -code error "Usage: source create_project.tcl \"unisim library path\""
} else {
    set UNISIM_PATH $1
}

# Close active project if one is already open.
catch {project close}

# Flush contents of "work" library if it already exists.
catch {
    vmap work work
    vdel -lib work -all
}

# Create the new project and map WORK and UNISIM libraries.
project delete satcat5
project new . satcat5
vlib work
vmap work work
vmap unisim $UNISIM_PATH

# Shared libraries, including generic and platform-specific:
project addfolder common_lib
project addfile ../../src/vhdl/common/common_functions.vhd VHDL common_lib
project addfile ../../src/vhdl/common/eth_frame_common.vhd VHDL common_lib
project addfile ../../src/vhdl/common/router_common.vhd VHDL common_lib
project addfile ../../src/vhdl/xilinx/io_7series.vhd VHDL common_lib
project addfile ../../src/vhdl/common/led_types.vhd VHDL common_lib
project addfile ../../src/vhdl/xilinx/lutram_7series.vhd VHDL common_lib
project addfile ../../src/vhdl/common/bram_fifo.vhd VHDL common_lib
project addfile ../../src/vhdl/common/smol_fifo.vhd VHDL common_lib
project addfile ../../src/vhdl/common/slip_decoder.vhd VHDL common_lib
project addfile ../../src/vhdl/common/slip_encoder.vhd VHDL common_lib
project addfile ../../src/vhdl/common/switch_types.vhd VHDL common_lib
project addfile ../../src/vhdl/xilinx/synchronization.vhd VHDL common_lib

# Common VHDL (switch functions):
project addfolder common_sw
project addfile ../../src/vhdl/common/io_mdio_writer.vhd VHDL common_sw
project addfile ../../src/vhdl/common/io_spi_clkin.vhd VHDL common_sw
project addfile ../../src/vhdl/common/io_spi_clkout.vhd VHDL common_sw
project addfile ../../src/vhdl/common/io_uart.vhd VHDL common_sw
project addfile ../../src/vhdl/common/error_reporting.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_dec8b10b.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_enc8b10b_table.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_enc8b10b.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_frame_adjust.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_frame_check.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_preambles.vhd VHDL common_sw
project addfile ../../src/vhdl/common/config_file2rom.vhd VHDL common_sw
project addfile ../../src/vhdl/common/config_mdio_rom.vhd VHDL common_sw
project addfile ../../src/vhdl/common/config_read_command.vhd VHDL common_sw
project addfile ../../src/vhdl/common/config_send_status.vhd VHDL common_sw
project addfile ../../src/vhdl/common/config_port_eth.vhd VHDL common_sw
project addfile ../../src/vhdl/common/config_port_uart.vhd VHDL common_sw
project addfile ../../src/vhdl/common/mac_lookup_binary.vhd VHDL common_sw
project addfile ../../src/vhdl/common/mac_lookup_brute.vhd VHDL common_sw
project addfile ../../src/vhdl/common/mac_lookup_lutram.vhd VHDL common_sw
project addfile ../../src/vhdl/common/mac_lookup_parshift.vhd VHDL common_sw
project addfile ../../src/vhdl/common/mac_lookup_simple.vhd VHDL common_sw
project addfile ../../src/vhdl/common/mac_lookup_stream.vhd VHDL common_sw
project addfile ../../src/vhdl/common/mac_lookup_generic.vhd VHDL common_sw
project addfile ../../src/vhdl/common/packet_delay.vhd VHDL common_sw
project addfile ../../src/vhdl/common/packet_fifo.vhd VHDL common_sw
project addfile ../../src/vhdl/common/packet_inject.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_adapter.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_axi_mailbox.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_crosslink.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_inline_status.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_rgmii.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_rmii.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_sgmii_common.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_serial_auto.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_serial_spi_clkin.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_serial_spi_clkout.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_serial_uart_2wire.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_serial_uart_4wire.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_statistics.vhd VHDL common_sw
project addfile ../../src/vhdl/common/config_stats_axi.vhd VHDL common_sw
project addfile ../../src/vhdl/common/config_stats_uart.vhd VHDL common_sw
project addfile ../../src/vhdl/common/round_robin.vhd VHDL common_sw
project addfile ../../src/vhdl/common/router_icmp_send.vhd VHDL common_sw
project addfile ../../src/vhdl/common/router_mac_replace.vhd VHDL common_sw
project addfile ../../src/vhdl/common/router_arp_cache.vhd VHDL common_sw
project addfile ../../src/vhdl/common/router_arp_parse.vhd VHDL common_sw
project addfile ../../src/vhdl/common/router_arp_proxy.vhd VHDL common_sw
project addfile ../../src/vhdl/common/router_arp_request.vhd VHDL common_sw
project addfile ../../src/vhdl/common/router_arp_update.vhd VHDL common_sw
project addfile ../../src/vhdl/common/router_arp_wrapper.vhd VHDL common_sw
project addfile ../../src/vhdl/common/router_config_axi.vhd VHDL common_sw
project addfile ../../src/vhdl/common/router_config_static.vhd VHDL common_sw
project addfile ../../src/vhdl/common/router_ip_gateway.vhd VHDL common_sw
project addfile ../../src/vhdl/common/router_inline_top.vhd VHDL common_sw
project addfile ../../src/vhdl/common/scrub_placeholder.vhd VHDL common_sw
project addfile ../../src/vhdl/common/switch_aux.vhd VHDL common_sw
project addfile ../../src/vhdl/common/switch_core.vhd VHDL common_sw

# Xilinx-specific VHDL:
project addfolder xilinx
project addfile ../../src/vhdl/xilinx/clkgen_rgmii.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/clkgen_sgmii.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/lcd_control.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/sgmii_data_slip.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/sgmii_data_sync.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/sgmii_input_fifo.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/sgmii_serdes_rx.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/sgmii_serdes_tx.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/port_sgmii_xilinx.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/switch_top_ac701_base.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/switch_top_ac701_rgmii.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/switch_top_ac701_sgmii.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/switch_top_proto_v2.vhd VHDL xilinx

# Unit tests:
project addfolder test
project addfile ../../sim/vhdl/eth_traffic_gen.vhd VHDL test
project addfile ../../sim/vhdl/lfsr_sim.vhd VHDL test
project addfile ../../sim/vhdl/port_test_common.vhd VHDL test
project addfile ../../sim/vhdl/bram_fifo_tb.vhd VHDL test
project addfile ../../sim/vhdl/config_file2rom_tb.vhd VHDL test
project addfile ../../sim/vhdl/config_mdio_rom_tb.vhd VHDL test
project addfile ../../sim/vhdl/config_port_eth_tb.vhd VHDL test
project addfile ../../sim/vhdl/config_port_uart_tb.vhd VHDL test
project addfile ../../sim/vhdl/config_send_status_tb.vhd VHDL test
project addfile ../../sim/vhdl/config_stats_src.vhd VHDL test
project addfile ../../sim/vhdl/config_stats_tb.vhd VHDL test
project addfile ../../sim/vhdl/error_reporting_tb.vhd VHDL test
project addfile ../../sim/vhdl/eth_all8b10b_tb.vhd VHDL test
project addfile ../../sim/vhdl/eth_frame_adjust_tb.vhd VHDL test
project addfile ../../sim/vhdl/eth_frame_check_tb.vhd VHDL test
project addfile ../../sim/vhdl/io_spi_tb.vhd VHDL test
project addfile ../../sim/vhdl/lcd_control_tb.vhd VHDL test
project addfile ../../sim/vhdl/mac_lookup_tb.vhd VHDL test
project addfile ../../sim/vhdl/packet_delay_tb.vhd VHDL test
project addfile ../../sim/vhdl/packet_fifo_tb.vhd VHDL test
project addfile ../../sim/vhdl/packet_inject_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_axi_mailbox_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_inline_status_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_rgmii_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_rmii_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_sgmii_common_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_serial_auto_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_serial_spi_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_serial_uart_2wire_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_serial_uart_4wire_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_statistics_tb.vhd VHDL test
project addfile ../../sim/vhdl/round_robin_tb.vhd VHDL test
project addfile ../../sim/vhdl/router_sim_tools.vhd VHDL test
project addfile ../../sim/vhdl/router_mac_replace_tb.vhd VHDL test
project addfile ../../sim/vhdl/router_arp_cache_tb.vhd VHDL test
project addfile ../../sim/vhdl/router_arp_proxy_tb.vhd VHDL test
project addfile ../../sim/vhdl/router_arp_request_tb.vhd VHDL test
project addfile ../../sim/vhdl/router_arp_update_tb.vhd VHDL test
project addfile ../../sim/vhdl/router_ip_gateway_tb.vhd VHDL test
project addfile ../../sim/vhdl/router_inline_top_tb.vhd VHDL test
project addfile ../../sim/vhdl/sgmii_data_slip_tb.vhd VHDL test
project addfile ../../sim/vhdl/sgmii_data_sync_tb.vhd VHDL test
project addfile ../../sim/vhdl/sgmii_serdes_rx_tb.vhd VHDL test
project addfile ../../sim/vhdl/slip_decoder_tb.vhd VHDL test
project addfile ../../sim/vhdl/slip_encoder_tb.vhd VHDL test
project addfile ../../sim/vhdl/smol_fifo_tb.vhd VHDL test
project addfile ../../sim/vhdl/switch_core_tb.vhd VHDL test

# Done!
puts "Project created!"
