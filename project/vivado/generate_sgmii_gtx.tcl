# ------------------------------------------------------------------------
# Copyright 2020, 2022 The Aerospace Corporation
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
# This file declares a function generate_sgmii_gtx, which can be called to
# instantiate the Xilinx Ethernet IP core for use with a built-in GTX SERDES.
# (e.g., On the Kintex-7 and other devices.)  The core is configured for
# SGMII mode, with options suitable for use with the thin-wrapper defined
# in src/vhdl/xilinx/port_sgmii_gtx.vhd.  The user must indicate the desired
# GTX location, e.g., "X0Y0". The user can also specify external shared logic
# by setting include_shared_logic to 0 (not supported by the wrapper).
#
# Note that currently, due to the complexity of properly routing the
# gigabit transceiver COMMON primitives in a generic and convenient
# manner, only one SGMII link per quad is supported. This may change in
# future releases.

proc generate_sgmii_gtx {gt_loc {core_name sgmii_gtx0} {include_shared_logic 1} {refclk_freq_mhz 125}} {
    # Clear out any previous instances with the same name.
    set old_core [get_filesets -quiet $core_name]
    if {[llength $old_core] > 0} {
        remove_files [get_files -of $old_core]
    }
    # Create the new IP core and set all parameters.
    create_ip -name gig_ethernet_pcs_pma -vendor xilinx.com -library ip -module_name $core_name
    set ip_obj [get_ips $core_name]
    # Must enable Auto_Negotiation setting or the configuration_vector used in port_sgmii_gtx.vhd
    # does nothing.
    set_property -dict [list\
        CONFIG.Auto_Negotiation     true\
        CONFIG.RefClkRate           $refclk_freq_mhz\
        CONFIG.Management_Interface false\
        CONFIG.MaxDataRate          1G\
        CONFIG.SGMII_PHY_Mode       false\
        CONFIG.Standard             SGMII\
    ] $ip_obj
    if {$include_shared_logic} {
        set_property CONFIG.SupportLevel {Include_Shared_Logic_in_Core} $ip_obj
    } else {
        set_property CONFIG.SupportLevel {Include_Shared_Logic_in_Example_Design} $ip_obj
    }
    # Some additional properties are only set if present.
    # (Depends on installed LogiCORE IP version.)
    catch {set_property CONFIG.Physical_Interface Transceiver $ip_obj}
    catch {set_property CONFIG.GT_Location $gt_loc $ip_obj}
    # Generate files for the new core.
    generate_target {instantiation_template} [get_files $core_name.xci]
    generate_target all [get_files $core_name.xci]
    catch { config_ip_cache -export $ip_obj }
    export_ip_user_files -of_objects [get_files $core_name.xci] -no_script -sync -force -quiet
    create_ip_run [get_files -of_objects [get_fileset sources_1] $core_name.xci]
    return $core_name
}
