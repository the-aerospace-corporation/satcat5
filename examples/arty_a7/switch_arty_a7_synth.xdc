# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

# Synthesis constraints for switch_top_arty_a7
# Define pin locations and I/O standards only.

#####################################################################
### Set all I/O pin locations
set_property PACKAGE_PIN E3 [get_ports ref_clk100]

# Eth0 = Uplink RMII interface.
# (Tx/Rx direct connection for MAC-to-PHY interface.)
set_property PACKAGE_PIN F16 [get_ports {mdio_clk[0]}]
set_property PACKAGE_PIN K13 [get_ports {mdio_data[0]}]
set_property PACKAGE_PIN G14 [get_ports rmii_rxen]
set_property PACKAGE_PIN C17 [get_ports rmii_rxer]
set_property PACKAGE_PIN D18 [get_ports {rmii_rxd[0]}]
set_property PACKAGE_PIN E17 [get_ports {rmii_rxd[1]}]
set_property PACKAGE_PIN H15 [get_ports rmii_txen]
set_property PACKAGE_PIN H14 [get_ports {rmii_txd[0]}]
set_property PACKAGE_PIN J14 [get_ports {rmii_txd[1]}]
set_property PACKAGE_PIN G18 [get_ports rmii_refclk]
set_property PACKAGE_PIN G16 [get_ports rmii_mode]
set_property PACKAGE_PIN C16 [get_ports rmii_resetn]
#set_property PACKAGE_PIN B8     [get_ports { ETH_INTN }];      #IO_L12P_T1_MRCC_16 Sch=eth_intn TODO: We don't care about interrupts

## ChipKit SPI = EoS-SPI0 (FPGA is slave / peripheral)
## Pin 1/2/3/4 = CSb, SDI(MOSI), SDO(MISO), SCK
#set_property PACKAGE_PIN C1     [get_ports {spi_csb[0]}];       # FMC_LA29N = PMOD1_IO1
#set_property PACKAGE_PIN H1     [get_ports {spi_sdi[0]}];       # FMC_LA31P = PMOD1_IO2
#set_property PACKAGE_PIN G1     [get_ports {spi_sdo[0]}];       # FMC_LA31N = PMOD1_IO3
#set_property PACKAGE_PIN F1     [get_ports {spi_sclk[0]}];      # FMC_LA01N = PMOD1_IO4

# PMOD JA = EoS-AUTO0
# Pin 1/2/3/4 = RTSb, RXD, TXD, CTSb = Out, In, Out, In wrt USB-UART
# Pin 1/2/3/4 = CTSb, TXD, RXD, RTSb = In, Out, In, Out wrt FPGA
set_property PACKAGE_PIN G13 [get_ports {eos_pmod1[0]}]
set_property PACKAGE_PIN B11 [get_ports {eos_pmod2[0]}]
set_property PACKAGE_PIN A11 [get_ports {eos_pmod3[0]}]
set_property PACKAGE_PIN D12 [get_ports {eos_pmod4[0]}]

# PMOD JB = EoS-AUTO1
set_property PACKAGE_PIN E15 [get_ports {eos_pmod1[1]}]
set_property PACKAGE_PIN E16 [get_ports {eos_pmod2[1]}]
set_property PACKAGE_PIN D15 [get_ports {eos_pmod3[1]}]
set_property PACKAGE_PIN C15 [get_ports {eos_pmod4[1]}]

# PMOD JC = EoS-AUTO2
set_property PACKAGE_PIN U12 [get_ports {eos_pmod1[2]}]
set_property PACKAGE_PIN V12 [get_ports {eos_pmod2[2]}]
set_property PACKAGE_PIN V10 [get_ports {eos_pmod3[2]}]
set_property PACKAGE_PIN V11 [get_ports {eos_pmod4[2]}]

# PMOD JC = EoS-AUTO2
set_property PACKAGE_PIN D4 [get_ports {eos_pmod1[3]}]
set_property PACKAGE_PIN D3 [get_ports {eos_pmod2[3]}]
set_property PACKAGE_PIN F4 [get_ports {eos_pmod3[3]}]
set_property PACKAGE_PIN F3 [get_ports {eos_pmod4[3]}]

# Status indicators and other control.
set_property PACKAGE_PIN F6 [get_ports stat_led_g]
set_property PACKAGE_PIN G3 [get_ports stat_led_r]

# USB RS232 Interface
set_property PACKAGE_PIN D10 [get_ports host_tx]
set_property PACKAGE_PIN A9 [get_ports host_rx]

set_property PACKAGE_PIN C2 [get_ports ext_reset_n]

# Debug LCD on ChipKit header
set_property PACKAGE_PIN V15 [get_ports {lcd_db[0]}]
set_property PACKAGE_PIN U16 [get_ports {lcd_db[1]}]
set_property PACKAGE_PIN P14 [get_ports {lcd_db[2]}]
set_property PACKAGE_PIN T11 [get_ports {lcd_db[3]}]
set_property PACKAGE_PIN R12 [get_ports lcd_e]
set_property PACKAGE_PIN T14 [get_ports lcd_rw]
set_property PACKAGE_PIN T15 [get_ports lcd_rs]

#####################################################################
### Set all voltages and signaling standards
set_property IOSTANDARD LVCMOS33 [get_ports ref_clk100]

# The LCD and status LEDs are at 3.3V.
set_property IOSTANDARD LVCMOS33 [get_ports lcd_*]
set_property IOSTANDARD LVCMOS33 [get_ports stat_led_*]

# RMII Uplink/SPI/UART are at 3.3V.
set_property IOSTANDARD LVCMOS33 [get_ports rmii_*]
set_property IOSTANDARD LVCMOS33 [get_ports eos_pmod*]
set_property IOSTANDARD LVCMOS33 [get_ports mdio_*]

# USB-UART interface is at 3.3V.
set_property IOSTANDARD LVCMOS33 [get_ports host_*]

# The "CPU reset" button is at 3.3V (active low)
set_property IOSTANDARD LVCMOS33 [get_ports ext_reset_n]

# CFGBVS pin = 3.3V.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

##############################################################################
# Note: Timing constraints are specified in separate implementation-only file.
##############################################################################


