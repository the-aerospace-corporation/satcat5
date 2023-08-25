# Copyright 2023 The Aerospace Corporation
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

# This script creates a new Vivado project for the Xilinx VC707 dev board.
# To re-create the project, source this file in the Vivado Tcl Shell.

puts {Running create_vivado.tcl}

# Change to example project folder.
cd [file normalize [file dirname [info script]]]

# Set project-level properties depending on the selected board.
set target_part "XCZU48DR-FSVG1517-2-E"
set target_proj "zcu208_clksynth"
set target_top "zcu208_clksynth"
set constr_synth "zcu208_synth.xdc"
set constr_impl "zcu208_impl.xdc"
set override_postbit ""

# Add source files:
set files_main [list \
    "[file normalize "../../src/vhdl/common/*.vhd"]"\
    "[file normalize "../../src/vhdl/xilinx/ultraplus_*.vhd"]"\
    "[file normalize "./*.vhd"]"\
]

# Run the main script.
source ../../project/vivado/shared_create.tcl

# Create the RF DAta Converter IP-core.
create_ip -name usp_rf_data_converter \
    -vendor xilinx.com -library ip \
    -module_name usp_rf_data_converter_0
set rfdac [get_ips usp_rf_data_converter_0]
set_property -dict [list \
    CONFIG.Converter_Setup {0} \
    CONFIG.DAC230_En {true} \
    CONFIG.DAC231_En {true} \
    CONFIG.ADC0_Enable {0} \
    CONFIG.ADC0_Fabric_Freq {0.0} \
    CONFIG.ADC_Slice00_Enable {false} \
    CONFIG.ADC_Decimation_Mode00 {0} \
    CONFIG.ADC_Mixer_Type00 {3} \
    CONFIG.ADC_Slice01_Enable {false} \
    CONFIG.ADC_Decimation_Mode01 {0} \
    CONFIG.ADC_Mixer_Type01 {3} \
    CONFIG.ADC_OBS01 {0} \
    CONFIG.ADC_OBS02 {0} \
    CONFIG.ADC_OBS03 {0} \
    CONFIG.ADC_OBS11 {0} \
    CONFIG.ADC_OBS12 {0} \
    CONFIG.ADC_OBS13 {0} \
    CONFIG.ADC_OBS21 {0} \
    CONFIG.ADC_OBS22 {0} \
    CONFIG.ADC_OBS23 {0} \
    CONFIG.ADC_OBS31 {0} \
    CONFIG.ADC_OBS32 {0} \
    CONFIG.ADC_OBS33 {0} \
    CONFIG.mADC_OBS02 {0} \
    CONFIG.DAC_Mixer_Mode00 {0} \
    CONFIG.DAC_Mixer_Mode01 {0} \
    CONFIG.DAC_Mixer_Mode03 {0} \
    CONFIG.DAC_Mixer_Mode10 {0} \
    CONFIG.DAC_Mixer_Mode11 {0} \
    CONFIG.DAC_Mixer_Mode13 {0} \
    CONFIG.DAC2_Enable {1} \
    CONFIG.DAC2_PLL_Enable {true} \
    CONFIG.DAC2_Refclk_Freq {400.000} \
    CONFIG.DAC2_Outclk_Freq {200.000} \
    CONFIG.DAC2_Fabric_Freq {200.000} \
    CONFIG.DAC2_Clock_Dist {1} \
    CONFIG.DAC_Slice20_Enable {true} \
    CONFIG.DAC_Interpolation_Mode20 {2} \
    CONFIG.DAC_Mixer_Type20 {1} \
    CONFIG.DAC_Mixer_Mode20 {2} \
    CONFIG.DAC_Coarse_Mixer_Freq20 {3} \
    CONFIG.DAC_Mixer_Mode21 {2} \
    CONFIG.DAC_Slice22_Enable {true} \
    CONFIG.DAC_Interpolation_Mode22 {2} \
    CONFIG.DAC_Mixer_Type22 {1} \
    CONFIG.DAC_Coarse_Mixer_Freq22 {3} \
    CONFIG.DAC3_Enable {1} \
    CONFIG.DAC3_PLL_Enable {true} \
    CONFIG.DAC3_Refclk_Freq {400.000} \
    CONFIG.DAC3_Outclk_Freq {200.000} \
    CONFIG.DAC3_Fabric_Freq {200.000} \
    CONFIG.DAC3_Clock_Source {6} \
    CONFIG.DAC_Slice30_Enable {true} \
    CONFIG.DAC_Interpolation_Mode30 {2} \
    CONFIG.DAC_Mixer_Type30 {1} \
    CONFIG.DAC_Mixer_Mode30 {2} \
    CONFIG.DAC_Coarse_Mixer_Freq30 {3} \
    CONFIG.DAC_Mixer_Mode31 {2} \
    CONFIG.DAC_Slice32_Enable {true} \
    CONFIG.DAC_Interpolation_Mode32 {2} \
    CONFIG.DAC_Mixer_Type32 {1} \
    CONFIG.DAC_Coarse_Mixer_Freq32 {3} \
    CONFIG.mDAC_Enable {1} \
    CONFIG.mDAC_PLL_Enable {true} \
    CONFIG.mDAC_Refclk_Freq {400.000} \
    CONFIG.mDAC_Outclk_Freq {200.000} \
    CONFIG.mDAC_Fabric_Freq {200.000} \
    CONFIG.mDAC_Slice00_Enable {true} \
    CONFIG.mDAC_Interpolation_Mode00 {2} \
    CONFIG.mDAC_Mixer_Type00 {1} \
    CONFIG.mDAC_Coarse_Mixer_Freq00 {3} \
    CONFIG.mDAC_Slice02_Enable {true} \
    CONFIG.mDAC_Interpolation_Mode02 {2} \
    CONFIG.mDAC_Mixer_Type02 {1} \
    CONFIG.mDAC_Coarse_Mixer_Freq02 {3} \
] $rfdac

# Suppress specific warnings triggered by Vivado IP:
set_msg_config -suppress -id {[Common 17-576]};     # "use_project_ipc" deprecated
set_msg_config -suppress -id {[Synth 8-589]};       # Replace case/wildcard
set_msg_config -suppress -id {[Vivado_Tcl 4-1400]}; # "ultrathreads" deprecated

# Suppress warnings triggered by code in our design:
set_msg_config -suppress -id {[DRC DPIP-2]};        # DSP48 pipelining
set_msg_config -suppress -id {[DRC RTSTAT-10]};     # No routable loads
set_msg_config -suppress -id {[Synth 8-3295]};      # Typing undriven pin to constant
set_msg_config -suppress -id {[Synth 8-5396]};      # Keep attribute / extra logic
set_msg_config -suppress -id {[Synth 8-6774]};      # Null subtype declaration

# Final cleanup before project is ready to use.
update_compile_order -fileset sources_1

# Execute the build and write out the .bin file.
source ../../project/vivado/shared_build.tcl
satcat5_launch_run
