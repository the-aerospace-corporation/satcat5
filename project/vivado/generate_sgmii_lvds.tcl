# ------------------------------------------------------------------------
# Copyright 2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This file declares a function generate_sgmii_lvds, which can be called to
# instantiate the Xilinx Ethernet IP core for use with LVDS GPIO pins an SERDES.
# (e.g., On the Kintex-7 and other devices.)  The core is configured for
# SGMII mode, with options suitable for use with the thin-wrapper defined
# in src/vhdl/xilinx/port_sgmii_lvds.vhd. The user can specify external shared logic
# by setting include_shared_logic to 0 (not supported by the wrapper).
#
# The refclk_freq_mhz must be one of: 125, 156.25, 625 (only 625 implemented so far)

proc generate_sgmii_lvds {{core_name sgmii_lvds0} {include_shared_logic 1} {refclk_freq_mhz 625}} {
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
        CONFIG.Standard SGMII\
        CONFIG.Physical_Interface LVDS\
        CONFIG.Management_Interface false\
        CONFIG.Auto_Negotiation true\
        CONFIG.LvdsRefClk $refclk_freq_mhz\
    ] $ip_obj

    if {$include_shared_logic} {
        set_property CONFIG.SupportLevel {Include_Shared_Logic_in_Core} $ip_obj
    } else {
        set_property CONFIG.SupportLevel {Include_Shared_Logic_in_Example_Design} $ip_obj
    }

    # Generate files for the new core.
    generate_target {instantiation_template} [get_files $core_name.xci]
    generate_target all [get_files $core_name.xci]
    catch { config_ip_cache -export $ip_obj }
    export_ip_user_files -of_objects [get_files $core_name.xci] -no_script -sync -force -quiet
    create_ip_run [get_files -of_objects [get_fileset sources_1] $core_name.xci]
    return $core_name
}
