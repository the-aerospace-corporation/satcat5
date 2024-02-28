# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

# Synthesis constraints for converter_zed
# Define pin locations and I/O standards only.

#####################################################################
### Set all I/O pin locations

# PMOD JA = EoS-AUTO0
# Pin 1/2/3/4 = RTSb, RXD, TXD, CTSb = Out, In, Out, In wrt USB-UART
# Pin 1/2/3/4 = CTSb, TXD, RXD, RTSb = In, Out, In, Out wrt FPGA
set_property PACKAGE_PIN Y11  [get_ports {eos_pmod1}]
set_property PACKAGE_PIN AA11 [get_ports {eos_pmod2}]
set_property PACKAGE_PIN Y10  [get_ports {eos_pmod3}]
set_property PACKAGE_PIN AA9  [get_ports {eos_pmod4}]

#####################################################################
### Set all voltages and signaling standards

# SPI/UART PMODs are at 3.3V.
set_property IOSTANDARD LVCMOS33 [get_ports eos_pmod*]

##############################################################################
# Note: Timing constraints are specified in separate implementation-only file.
##############################################################################


