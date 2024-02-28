# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

# Synthesis constraints for switch_proto_v2
# Define pin locations and I/O standards only.

#####################################################################
### Set all I/O pin locations

# SGMII ports
set_property PACKAGE_PIN B7     [get_ports {sgmii_txp[1]}];
set_property PACKAGE_PIN A7     [get_ports {sgmii_txn[1]}];
set_property PACKAGE_PIN B6     [get_ports {sgmii_rxp[1]}];
set_property PACKAGE_PIN B5     [get_ports {sgmii_rxn[1]}];
set_property PACKAGE_PIN L4     [get_ports {sgmii_errb[1]}];
set_property PACKAGE_PIN M4     [get_ports {sgmii_pwren[1]}];

set_property PACKAGE_PIN B4     [get_ports {sgmii_txp[2]}];
set_property PACKAGE_PIN A3     [get_ports {sgmii_txn[2]}];
set_property PACKAGE_PIN C7     [get_ports {sgmii_rxp[2]}];
set_property PACKAGE_PIN C6     [get_ports {sgmii_rxn[2]}];
set_property PACKAGE_PIN M2     [get_ports {sgmii_errb[2]}];
set_property PACKAGE_PIN M1     [get_ports {sgmii_pwren[2]}];

set_property PACKAGE_PIN C3     [get_ports {sgmii_txp[3]}];
set_property PACKAGE_PIN C2     [get_ports {sgmii_txn[3]}];
set_property PACKAGE_PIN B2     [get_ports {sgmii_rxp[3]}];
set_property PACKAGE_PIN A2     [get_ports {sgmii_rxn[3]}];
set_property PACKAGE_PIN N3     [get_ports {sgmii_errb[3]}];
set_property PACKAGE_PIN N2     [get_ports {sgmii_pwren[3]}];

set_property PACKAGE_PIN E2     [get_ports {sgmii_rxp[4]}];
set_property PACKAGE_PIN D1     [get_ports {sgmii_rxn[4]}];
set_property PACKAGE_PIN E3     [get_ports {sgmii_txp[4]}];
set_property PACKAGE_PIN D3     [get_ports {sgmii_txn[4]}];
set_property PACKAGE_PIN N1     [get_ports {sgmii_errb[4]}];
set_property PACKAGE_PIN P1     [get_ports {sgmii_pwren[4]}];

# Note: AR8031 doesn't include PWREN or ERRB pins
set_property PACKAGE_PIN F5     [get_ports {sgmii_rxp[5]}];
set_property PACKAGE_PIN E5     [get_ports {sgmii_rxn[5]}];
set_property PACKAGE_PIN F4     [get_ports {sgmii_txp[5]}];
set_property PACKAGE_PIN F3     [get_ports {sgmii_txn[5]}];

# EOS ports
set_property PACKAGE_PIN P15    [get_ports {eos_pmod1[1]}];
set_property PACKAGE_PIN P16    [get_ports {eos_pmod2[1]}];
set_property PACKAGE_PIN R15    [get_ports {eos_pmod3[1]}];
set_property PACKAGE_PIN R16    [get_ports {eos_pmod4[1]}];
set_property PACKAGE_PIN T14    [get_ports {eos_errb[1]}];
set_property PACKAGE_PIN T15    [get_ports {eos_pwren[1]}];

set_property PACKAGE_PIN N14    [get_ports {eos_pmod1[2]}];
set_property PACKAGE_PIN P14    [get_ports {eos_pmod2[2]}];
set_property PACKAGE_PIN N11    [get_ports {eos_pmod3[2]}];
set_property PACKAGE_PIN N12    [get_ports {eos_pmod4[2]}];
set_property PACKAGE_PIN P10    [get_ports {eos_errb[2]}];
set_property PACKAGE_PIN P11    [get_ports {eos_pwren[2]}];

set_property PACKAGE_PIN R13    [get_ports {eos_pmod1[3]}];
set_property PACKAGE_PIN T13    [get_ports {eos_pmod2[3]}];
set_property PACKAGE_PIN R10    [get_ports {eos_pmod3[3]}];
set_property PACKAGE_PIN R11    [get_ports {eos_pmod4[3]}];
set_property PACKAGE_PIN N9     [get_ports {eos_errb[3]}];
set_property PACKAGE_PIN P9     [get_ports {eos_pwren[3]}];

set_property PACKAGE_PIN P8     [get_ports {eos_pmod1[4]}];
set_property PACKAGE_PIN R8     [get_ports {eos_pmod2[4]}];
set_property PACKAGE_PIN T7     [get_ports {eos_pmod3[4]}];
set_property PACKAGE_PIN T8     [get_ports {eos_pmod4[4]}];
set_property PACKAGE_PIN T9     [get_ports {eos_pwren[4]}];
set_property PACKAGE_PIN T10    [get_ports {eos_errb[4]}];

set_property PACKAGE_PIN C8     [get_ports {eos_pmod1[5]}];
set_property PACKAGE_PIN C9     [get_ports {eos_pmod2[5]}];
set_property PACKAGE_PIN A8     [get_ports {eos_pmod3[5]}];
set_property PACKAGE_PIN A9     [get_ports {eos_pmod4[5]}];
set_property PACKAGE_PIN B9     [get_ports {eos_pwren[5]}];
set_property PACKAGE_PIN A10    [get_ports {eos_errb[5]}];

set_property PACKAGE_PIN B12    [get_ports {eos_pmod1[6]}];
set_property PACKAGE_PIN A12    [get_ports {eos_pmod2[6]}];
set_property PACKAGE_PIN D8     [get_ports {eos_pmod3[6]}];
set_property PACKAGE_PIN D9     [get_ports {eos_pmod4[6]}];
set_property PACKAGE_PIN A13    [get_ports {eos_pwren[6]}];
set_property PACKAGE_PIN A14    [get_ports {eos_errb[6]}];

set_property PACKAGE_PIN B15    [get_ports {eos_pmod1[7]}];
set_property PACKAGE_PIN A15    [get_ports {eos_pmod2[7]}];
set_property PACKAGE_PIN C16    [get_ports {eos_pmod3[7]}];
set_property PACKAGE_PIN B16    [get_ports {eos_pmod4[7]}];
set_property PACKAGE_PIN C11    [get_ports {eos_pwren[7]}];
set_property PACKAGE_PIN C12    [get_ports {eos_errb[7]}];

set_property PACKAGE_PIN E12    [get_ports {eos_pmod1[8]}];
set_property PACKAGE_PIN E13    [get_ports {eos_pmod2[8]}];
set_property PACKAGE_PIN E11    [get_ports {eos_pmod3[8]}];
set_property PACKAGE_PIN D11    [get_ports {eos_pmod4[8]}];
set_property PACKAGE_PIN D14    [get_ports {eos_pwren[8]}];
set_property PACKAGE_PIN D15    [get_ports {eos_errb[8]}];

# Control and status
set_property PACKAGE_PIN D13    [get_ports {ext_clk25}];
set_property PACKAGE_PIN J16    [get_ports {psense_scl}];
set_property PACKAGE_PIN J15    [get_ports {psense_sda}];
set_property PACKAGE_PIN T4     [get_ports {phy_mdio}];
set_property PACKAGE_PIN T3     [get_ports {phy_mdc}];
set_property PACKAGE_PIN P5     [get_ports {phy_rstn}];

#####################################################################
### Set all voltages and signaling standards

# Note: IOSTANDARD for SGMII-related LVDS pins is set in HDL.
set_property IOSTANDARD LVCMOS25 [get_ports {sgmii_err*}];
set_property IOSTANDARD LVCMOS25 [get_ports {sgmii_pwr*}];
set_property IOSTANDARD LVCMOS25 [get_ports {phy_*}];

set_property IOSTANDARD LVCMOS33 [get_ports {eos_*}];
set_property IOSTANDARD LVCMOS33 [get_ports {ext_clk25}];
set_property IOSTANDARD LVCMOS33 [get_ports {psense_*}];

# CFGBVS pin = 3.3V.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

#####################################################################
### Other build settings

# Disable spurious error regarding clock-switchover compensation.
# (Frequency reference only; we simply don't care about source phase.)
# The REQP-119 check occurs before implementation constraints are read,
# so it's easiest to simply disable it during synthesis.
set_property is_enabled false [get_drc_checks REQP-119]

##############################################################################
# Note: Timing constraints are specified in separate implementation-only file.
##############################################################################
