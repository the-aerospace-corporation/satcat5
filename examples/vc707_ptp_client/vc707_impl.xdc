# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

# Implementation constraints for vc707_ptp_client
# This file is for added constraints required ONLY during implementation.

#####################################################################
### Bitstream generation

set_property BITSTREAM.CONFIG.BPI_SYNC_MODE DISABLE [current_design];
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design];
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN DISABLE [current_design];
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup [current_design];
set_property CONFIG_MODE BPI16 [current_design];

#####################################################################
### Timing constraints

# Input clocks at 80, 100, and 125 MHz.
# (200 MHz SYSCLK is defined by MIG constraints)
create_clock -period 12.500 -name clk_emc_ref [get_ports emc_clk]
create_clock -period 10.000 -name clk_fmc_ref [get_ports fmc_ref_clk_p]
create_clock -period 8.000 -name clk_mgt_ref [get_ports mgt_ref_clk_p]

# Rename certain generated clocks for readability.
set clk_mgt_125 \
    [get_pin -hier -filter {NAME =~ vc707_ptp_i/port_sgmii_raw_gtx_0/*/TXOUTCLK}]
create_generated_clock -name clk_fmc_fb \
    [get_pin -hier -filter {NAME =~ vc707_ptp_i/synth_mgt_from_rtc_0/*/CLKFBOUT}]
create_generated_clock -name clk_fmc_125 \
    [get_pin -hier -filter {NAME =~ vc707_ptp_i/synth_mgt_from_rtc_0/*/CLKOUT0}]
create_generated_clock -name clk_fmc_250 \
    [get_pin -hier -filter {NAME =~ vc707_ptp_i/synth_mgt_from_rtc_0/*/CLKOUT1}]
create_generated_clock -name clk_vref_a \
    -master_clock clk_fmc_125 [get_pin vc707_ptp_i/ptp_reference_0/U0/u_clk/u_mmcm/CLKOUT0]
create_generated_clock -name clk_vref_b \
    -master_clock clk_fmc_125 [get_pin vc707_ptp_i/ptp_reference_0/U0/u_clk/u_mmcm/CLKOUT1]
create_generated_clock -name clk_vref_c \
    -master_clock $clk_mgt_125 [get_pin vc707_ptp_i/ptp_reference_0/U0/u_clk/u_mmcm/CLKOUT0]
create_generated_clock -name clk_vref_d \
    -master_clock $clk_mgt_125 [get_pin vc707_ptp_i/ptp_reference_0/U0/u_clk/u_mmcm/CLKOUT1]

# Suppress error regarding unroutable cascaded clock.
# (SGMII clocks in bottom half, FMC clocks in top half; no common BUFGMUX.)
# See also: UG472 Fig 2-2, https://support.xilinx.com/s/question/0D52E00006hpZ98SAE/
# TODO: What is the jitter impact of this change?
# TODO: Better to use external loopback from FMC-TX3 to USER_SMA_CLOCK?
set_property CLOCK_DEDICATED_ROUTE FALSE \
    [get_nets -hier -filter {NAME =~ vc707_ptp_i/synth_mgt_from_rtc_0/*/gt3_txusrclk2_out}]

# Mark the primary and secondary reference clocks as mutually exclusive.
# (Automatic failover using BUFGMUX in "synth_mgt_from_rtc.vhd".)
set_clock_groups -physically_exclusive \
    -group [get_clocks clk_fmc_125 -include_generated_clocks] \
    -group [get_clocks $clk_mgt_125 -include_generated_clocks]

# Mark all input clocks as mutually asynchronous, including synchronous
# clocks for which we've designed explicit clock-domain-crossings.
# (Same as adding calling set_false_path on all pairwise permutations.)
# See also: https://www.xilinx.com/support/answers/44651.html
set_clock_groups -asynchronous \
    -group [get_clocks clk_emc_ref -include_generated_clocks] \
    -group [get_clocks clk_fmc_ref -include_generated_clocks] \
    -group [get_clocks clk_fmc_125 -include_generated_clocks] \
    -group [get_clocks clk_mgt_ref -include_generated_clocks] \
    -group [get_clocks clk_vref_a -include_generated_clocks] \
    -group [get_clocks clk_vref_b -include_generated_clocks] \
    -group [get_clocks clk_vref_c -include_generated_clocks] \
    -group [get_clocks clk_vref_d -include_generated_clocks] \
    -group [get_clocks *gtxe2* -include_generated_clocks] \
    -group [get_clocks sys_clk_clk_p -include_generated_clocks];

# Explicit delay constraints on clock-crossing signals.
set_max_delay -datapath_only 5.0 -from [get_cells -hier -filter {satcat5_cross_clock_src > 0}]
set_max_delay -datapath_only 5.0 -to   [get_cells -hier -filter {satcat5_cross_clock_dst > 0}]
