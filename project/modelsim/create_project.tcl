# ------------------------------------------------------------------------
# Copyright 2021-2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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

# Modify certain settings in "modelsim.ini"
# TODO: Does ModelSim provide an easier way to do this?
catch {
    # Copy original "modelsim.ini", line by line.
    set src [open "modelsim.ini" r]
    set dst [open "modelsim.tmp" w]
    while {[gets $src line] >= 0} {
        if {[string match "Resolution*" $line]} {
            # Force default simulation timestep to 1 ps.
            puts $dst "Resolution = ps"
        } else {
            puts $dst $line
        }
    }
    close $src
    close $dst
    # If we reach this point, replace original with modified version.
    file rename -force "modelsim.tmp" "modelsim.ini"
}

# Shared libraries, including generic and platform-specific:
project addfolder common_lib
project addfile ../../src/vhdl/common/common_functions.vhd VHDL common_lib
project addfile ../../src/vhdl/common/common_primitives.vhd VHDL common_lib
project addfile ../../src/vhdl/common/eth_frame_common.vhd VHDL common_lib
project addfile ../../src/vhdl/common/prng_lfsr_common.vhd VHDL common_lib
project addfile ../../src/vhdl/common/ptp_types.vhd VHDL common_lib
project addfile ../../src/vhdl/common/router_common.vhd VHDL common_lib
project addfile ../../src/vhdl/xilinx/7series_io.vhd VHDL common_lib
project addfile ../../src/vhdl/xilinx/7series_mem.vhd VHDL common_lib
project addfile ../../src/vhdl/xilinx/7series_sync.vhd VHDL common_lib
project addfile ../../src/vhdl/xilinx/7series_vernier.vhd VHDL common_lib
project addfile ../../src/vhdl/common/cfgbus_common.vhd VHDL common_lib
project addfile ../../src/vhdl/common/fifo_large_sync.vhd VHDL common_lib
project addfile ../../src/vhdl/common/fifo_smol_async.vhd VHDL common_lib
project addfile ../../src/vhdl/common/fifo_smol_sync.vhd VHDL common_lib
project addfile ../../src/vhdl/common/fifo_smol_bytes.vhd VHDL common_lib
project addfile ../../src/vhdl/common/fifo_smol_resize.vhd VHDL common_lib
project addfile ../../src/vhdl/common/fifo_packet.vhd VHDL common_lib
project addfile ../../src/vhdl/common/fifo_repack.vhd VHDL common_lib
project addfile ../../src/vhdl/common/io_leds.vhd VHDL common_lib
project addfile ../../src/vhdl/common/sine_table.vhd VHDL common_lib
project addfile ../../src/vhdl/common/sine_interp.vhd VHDL common_lib
project addfile ../../src/vhdl/common/slip_decoder.vhd VHDL common_lib
project addfile ../../src/vhdl/common/slip_encoder.vhd VHDL common_lib
project addfile ../../src/vhdl/common/switch_types.vhd VHDL common_lib

# Common VHDL (switch functions):
project addfolder common_sw
project addfile ../../src/vhdl/common/io_clock_detect.vhd VHDL common_sw
project addfile ../../src/vhdl/common/io_clock_tolerance.vhd VHDL common_sw
project addfile ../../src/vhdl/common/io_i2c_controller.vhd VHDL common_sw
project addfile ../../src/vhdl/common/io_i2c_peripheral.vhd VHDL common_sw
project addfile ../../src/vhdl/common/io_mdio_readwrite.vhd VHDL common_sw
project addfile ../../src/vhdl/common/io_mdio_writer.vhd VHDL common_sw
project addfile ../../src/vhdl/common/io_spi_controller.vhd VHDL common_sw
project addfile ../../src/vhdl/common/io_spi_peripheral.vhd VHDL common_sw
project addfile ../../src/vhdl/common/io_text_lcd.vhd VHDL common_sw
project addfile ../../src/vhdl/common/io_uart.vhd VHDL common_sw
project addfile ../../src/vhdl/common/io_error_reporting.vhd VHDL common_sw
project addfile ../../src/vhdl/common/packet_delay.vhd VHDL common_sw
project addfile ../../src/vhdl/common/packet_inject.vhd VHDL common_sw
project addfile ../../src/vhdl/common/packet_round_robin.vhd VHDL common_sw
project addfile ../../src/vhdl/common/prng_lfsr_gen.vhd VHDL common_lib
project addfile ../../src/vhdl/common/prng_lfsr_sync.vhd VHDL common_lib
project addfile ../../src/vhdl/common/ptp_dither.vhd VHDL common_sw
project addfile ../../src/vhdl/common/ptp_realsof.vhd VHDL common_sw
project addfile ../../src/vhdl/common/ptp_realsync.vhd VHDL common_sw
project addfile ../../src/vhdl/common/ptp_realtime.vhd VHDL common_sw
project addfile ../../src/vhdl/common/ptp_timestamp.vhd VHDL common_sw
project addfile ../../src/vhdl/common/tcam_constants.vhd VHDL common_sw
project addfile ../../src/vhdl/common/tcam_cache_nru2.vhd VHDL common_sw
project addfile ../../src/vhdl/common/tcam_cache_plru.vhd VHDL common_sw
project addfile ../../src/vhdl/common/tcam_maxlen.vhd VHDL common_sw
project addfile ../../src/vhdl/common/tcam_core.vhd VHDL common_sw
project addfile ../../src/vhdl/common/tcam_table.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_dec8b10b.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_enc8b10b_table.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_enc8b10b.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_frame_parcrc.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_frame_parcrc2.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_frame_adjust.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_frame_check.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_frame_vstrip.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_frame_vtag.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_pause_ctrl.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_preamble_rx.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_preamble_tx.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_statistics.vhd VHDL common_sw
project addfile ../../src/vhdl/common/eth_traffic_src.vhd VHDL common_sw
project addfile ../../src/vhdl/common/ptp_adjust.vhd VHDL common_sw
project addfile ../../src/vhdl/common/ptp_clksynth.vhd VHDL common_sw
project addfile ../../src/vhdl/common/ptp_filter.vhd VHDL common_sw
project addfile ../../src/vhdl/common/ptp_counter_free.vhd VHDL common_sw
project addfile ../../src/vhdl/common/ptp_counter_gen.vhd VHDL common_sw
project addfile ../../src/vhdl/common/ptp_counter_sync.vhd VHDL common_sw
project addfile ../../src/vhdl/common/ptp_egress.vhd VHDL common_sw
project addfile ../../src/vhdl/common/ptp_wavesynth.vhd VHDL common_sw
project addfile ../../src/vhdl/common/cfgbus_fifo.vhd VHDL common_sw
project addfile ../../src/vhdl/common/cfgbus_gpio.vhd VHDL common_sw
project addfile ../../src/vhdl/common/cfgbus_host_apb.vhd VHDL common_sw
project addfile ../../src/vhdl/common/cfgbus_host_axi.vhd VHDL common_sw
project addfile ../../src/vhdl/common/cfgbus_host_eth.vhd VHDL common_sw
project addfile ../../src/vhdl/common/cfgbus_host_rom.vhd VHDL common_sw
project addfile ../../src/vhdl/common/cfgbus_host_uart.vhd VHDL common_sw
project addfile ../../src/vhdl/common/cfgbus_host_wishbone.vhd VHDL common_sw
project addfile ../../src/vhdl/common/cfgbus_multiserial.vhd VHDL common_sw
project addfile ../../src/vhdl/common/cfgbus_i2c_controller.vhd VHDL common_sw
project addfile ../../src/vhdl/common/cfgbus_led.vhd VHDL common_sw
project addfile ../../src/vhdl/common/cfgbus_mdio.vhd VHDL common_sw
project addfile ../../src/vhdl/common/cfgbus_spi_controller.vhd VHDL common_sw
project addfile ../../src/vhdl/common/cfgbus_text_lcd.vhd VHDL common_sw
project addfile ../../src/vhdl/common/cfgbus_timer.vhd VHDL common_sw
project addfile ../../src/vhdl/common/cfgbus_to_axilite.vhd VHDL common_sw
project addfile ../../src/vhdl/common/cfgbus_uart.vhd VHDL common_sw
project addfile ../../src/vhdl/common/config_file2rom.vhd VHDL common_sw
project addfile ../../src/vhdl/common/config_mdio_rom.vhd VHDL common_sw
project addfile ../../src/vhdl/common/config_peripherals.vhd VHDL common_sw
project addfile ../../src/vhdl/common/config_port_test.vhd VHDL common_sw
project addfile ../../src/vhdl/common/config_send_status.vhd VHDL common_sw
project addfile ../../src/vhdl/common/fifo_priority.vhd VHDL common_sw
project addfile ../../src/vhdl/common/mac_counter.vhd VHDL common_sw
project addfile ../../src/vhdl/common/mac_igmp_simple.vhd VHDL common_sw
project addfile ../../src/vhdl/common/mac_lookup.vhd VHDL common_sw
project addfile ../../src/vhdl/common/mac_priority.vhd VHDL common_sw
project addfile ../../src/vhdl/common/mac_query.vhd VHDL common_sw
project addfile ../../src/vhdl/common/mac_vlan_mask.vhd VHDL common_sw
project addfile ../../src/vhdl/common/mac_vlan_rate.vhd VHDL common_sw
project addfile ../../src/vhdl/common/mac_core.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_adapter.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_cfgbus.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_crosslink.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_gmii_internal.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_inline_status.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_mailbox.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_mailmap.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_nullsink.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_passthrough.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_rgmii.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_rmii.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_sgmii_common.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_serial_auto.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_serial_i2c_controller.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_serial_i2c_peripheral.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_serial_spi_controller.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_serial_spi_peripheral.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_serial_uart_2wire.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_serial_uart_4wire.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_statistics.vhd VHDL common_sw
project addfile ../../src/vhdl/common/port_stream.vhd VHDL common_sw
project addfile ../../src/vhdl/common/portx_statistics.vhd VHDL common_sw
project addfile ../../src/vhdl/common/cfgbus_port_stats.vhd VHDL common_sw
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
project addfile ../../src/vhdl/common/switch_aux.vhd VHDL common_sw
project addfile ../../src/vhdl/common/switch_port_rx.vhd VHDL common_sw
project addfile ../../src/vhdl/common/switch_port_tx.vhd VHDL common_sw
project addfile ../../src/vhdl/common/switch_core.vhd VHDL common_sw
project addfile ../../src/vhdl/common/switch_dual.vhd VHDL common_sw

# Xilinx-specific VHDL:
project addfolder xilinx
project addfile ../../src/vhdl/xilinx/clkgen_rmii.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/clkgen_rgmii.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/clkgen_sgmii.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/sgmii_data_slip.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/sgmii_data_sync.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/sgmii_input_fifo.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/sgmii_serdes_rx.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/sgmii_serdes_tx.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/port_sgmii_gpio.vhd VHDL xilinx
project addfile ../../src/vhdl/xilinx/port_sgmii_gtx.vhd VHDL xilinx
project addfile ../../examples/ac701_proto_v1/switch_top_ac701_base.vhd VHDL xilinx
project addfile ../../examples/ac701_proto_v1/switch_top_ac701_rgmii.vhd VHDL xilinx
project addfile ../../examples/ac701_proto_v1/switch_top_ac701_sgmii.vhd VHDL xilinx
project addfile ../../examples/proto_v2/switch_top_proto_v2.vhd VHDL xilinx

# Unit tests:
project addfolder test
project addfile ../../sim/vhdl/cfgbus_sim_tools.vhd VHDL test
project addfile ../../sim/vhdl/cfgbus_multiserial_helper.vhd VHDL test
project addfile ../../sim/vhdl/eth_traffic_sim.vhd VHDL test
project addfile ../../sim/vhdl/fifo_sim_throttle.vhd VHDL test
project addfile ../../sim/vhdl/lfsr_sim.vhd VHDL test
project addfile ../../sim/vhdl/port_test_common.vhd VHDL test
project addfile ../../sim/vhdl/port_stats_refsrc.vhd VHDL test
project addfile ../../sim/vhdl/router_sim_tools.vhd VHDL test
project addfile ../../sim/vhdl/cfgbus_common_tb.vhd VHDL test
project addfile ../../sim/vhdl/cfgbus_host_apb_tb.vhd VHDL test
project addfile ../../sim/vhdl/cfgbus_host_axi_tb.vhd VHDL test
project addfile ../../sim/vhdl/cfgbus_host_eth_tb.vhd VHDL test
project addfile ../../sim/vhdl/cfgbus_host_rom_tb.vhd VHDL test
project addfile ../../sim/vhdl/cfgbus_host_uart_tb.vhd VHDL test
project addfile ../../sim/vhdl/cfgbus_host_wishbone_tb.vhd VHDL test
project addfile ../../sim/vhdl/cfgbus_i2c_tb.vhd VHDL test
project addfile ../../sim/vhdl/cfgbus_port_stats_tb.vhd VHDL test
project addfile ../../sim/vhdl/cfgbus_spi_tb.vhd VHDL test
project addfile ../../sim/vhdl/cfgbus_uart_tb.vhd VHDL test
project addfile ../../sim/vhdl/config_file2rom_tb.vhd VHDL test
project addfile ../../sim/vhdl/config_mdio_rom_tb.vhd VHDL test
project addfile ../../sim/vhdl/config_port_test_tb.vhd VHDL test
project addfile ../../sim/vhdl/config_send_status_tb.vhd VHDL test
project addfile ../../sim/vhdl/eth_all8b10b_tb.vhd VHDL test
project addfile ../../sim/vhdl/eth_frame_adjust_tb.vhd VHDL test
project addfile ../../sim/vhdl/eth_frame_check_tb.vhd VHDL test
project addfile ../../sim/vhdl/eth_frame_parcrc_tb.vhd VHDL test
project addfile ../../sim/vhdl/eth_frame_vstrip_tb.vhd VHDL test
project addfile ../../sim/vhdl/eth_frame_vtag_tb.vhd VHDL test
project addfile ../../sim/vhdl/eth_pause_ctrl_tb.vhd VHDL test
project addfile ../../sim/vhdl/eth_preamble_tb.vhd VHDL test
project addfile ../../sim/vhdl/fifo_large_sync_tb.vhd VHDL test
project addfile ../../sim/vhdl/fifo_packet_tb.vhd VHDL test
project addfile ../../sim/vhdl/fifo_priority_tb.vhd VHDL test
project addfile ../../sim/vhdl/fifo_repack_tb.vhd VHDL test
project addfile ../../sim/vhdl/fifo_smol_async_tb.vhd VHDL test
project addfile ../../sim/vhdl/fifo_smol_resize_tb.vhd VHDL test
project addfile ../../sim/vhdl/fifo_smol_sync_tb.vhd VHDL test
project addfile ../../sim/vhdl/io_error_reporting_tb.vhd VHDL test
project addfile ../../sim/vhdl/io_i2c_tb.vhd VHDL test
project addfile ../../sim/vhdl/io_mdio_readwrite_tb.vhd VHDL test
project addfile ../../sim/vhdl/io_spi_tb.vhd VHDL test
project addfile ../../sim/vhdl/io_text_lcd_tb.vhd VHDL test
project addfile ../../sim/vhdl/mac_counter_tb.vhd VHDL test
project addfile ../../sim/vhdl/mac_igmp_simple_tb.vhd VHDL test
project addfile ../../sim/vhdl/mac_lookup_tb.vhd VHDL test
project addfile ../../sim/vhdl/mac_priority_tb.vhd VHDL test
project addfile ../../sim/vhdl/mac_query_tb.vhd VHDL test
project addfile ../../sim/vhdl/mac_vlan_mask_tb.vhd VHDL test
project addfile ../../sim/vhdl/mac_vlan_rate_tb.vhd VHDL test
project addfile ../../sim/vhdl/packet_delay_tb.vhd VHDL test
project addfile ../../sim/vhdl/packet_inject_tb.vhd VHDL test
project addfile ../../sim/vhdl/packet_round_robin_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_inline_status_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_mailbox_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_mailmap_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_rgmii_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_rmii_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_sgmii_common_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_serial_auto_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_serial_i2c_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_serial_spi_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_serial_uart_2wire_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_serial_uart_4wire_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_statistics_tb.vhd VHDL test
project addfile ../../sim/vhdl/port_stream_tb.vhd VHDL test
project addfile ../../sim/vhdl/prng_lfsr_tb.vhd VHDL test
project addfile ../../sim/vhdl/ptp_adjust_tb.vhd VHDL test
project addfile ../../sim/vhdl/ptp_clksynth_tb.vhd VHDL test
project addfile ../../sim/vhdl/ptp_counter_tb.vhd VHDL test
project addfile ../../sim/vhdl/ptp_egress_tb.vhd VHDL test
project addfile ../../sim/vhdl/ptp_filter_tb.vhd VHDL test
project addfile ../../sim/vhdl/ptp_realsync_tb.vhd VHDL test
project addfile ../../sim/vhdl/ptp_realtime_tb.vhd VHDL test
project addfile ../../sim/vhdl/router_arp_cache_tb.vhd VHDL test
project addfile ../../sim/vhdl/router_arp_proxy_tb.vhd VHDL test
project addfile ../../sim/vhdl/router_arp_request_tb.vhd VHDL test
project addfile ../../sim/vhdl/router_arp_update_tb.vhd VHDL test
project addfile ../../sim/vhdl/router_config_tb.vhd VHDL test
project addfile ../../sim/vhdl/router_mac_replace_tb.vhd VHDL test
project addfile ../../sim/vhdl/router_ip_gateway_tb.vhd VHDL test
project addfile ../../sim/vhdl/router_inline_top_tb.vhd VHDL test
project addfile ../../sim/vhdl/sgmii_data_slip_tb.vhd VHDL test
project addfile ../../sim/vhdl/sgmii_data_sync_tb.vhd VHDL test
project addfile ../../sim/vhdl/sgmii_serdes_rx_tb.vhd VHDL test
project addfile ../../sim/vhdl/sine_interp_tb.vhd VHDL test
project addfile ../../sim/vhdl/sine_table_tb.vhd VHDL test
project addfile ../../sim/vhdl/slip_decoder_tb.vhd VHDL test
project addfile ../../sim/vhdl/slip_encoder_tb.vhd VHDL test
project addfile ../../sim/vhdl/switch_core_tb.vhd VHDL test
project addfile ../../sim/vhdl/tcam_cache_tb.vhd VHDL test
project addfile ../../sim/vhdl/tcam_maxlen_tb.vhd VHDL test
project addfile ../../sim/vhdl/tcam_core_tb.vhd VHDL test

# Done!
puts "Project created!"
