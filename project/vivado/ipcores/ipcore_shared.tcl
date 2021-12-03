# ------------------------------------------------------------------------
# Copyright 2020, 2021 The Aerospace Corporation
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
# This TCL script defines functions that are used by other scripts in this
# folder, to create and package Xilinx IP-cores.
#
# Before calling this script, you MUST set the following:
#   ip_name = Short filename (e.g., "switch_dual")
#   ip_vers = Version number (e.g., "1.0")
#   ip_disp = Display name (e.g., "SatCat5 dual-port switch")
#   ip_desc = Longer description (e.g., "A two-port switch, typically used..."")
#   ip_root = The folder containing this file.
#

# Set various global parameters:
set ip_dir  [file normalize $ip_root/$ip_name]

# Most source files are located under "src/vhdl":
set src_dir [file normalize "$ip_root/../../../src/vhdl/"]

# Register path so Vivado will find the EthPort XML and the new core.
set_property IP_REPO_PATHS $ip_root [current_fileset]
update_ip_catalog
update_ip_catalog -repo_path $ip_root -add_interface $ip_root/ConfigBus.xml
update_ip_catalog -repo_path $ip_root -add_interface $ip_root/ConfigBus_rtl.xml
update_ip_catalog -repo_path $ip_root -add_interface $ip_root/EthPort.xml
update_ip_catalog -repo_path $ip_root -add_interface $ip_root/EthPort_rtl.xml
update_ip_catalog -repo_path $ip_root -add_interface $ip_root/TextLCD.xml
update_ip_catalog -repo_path $ip_root -add_interface $ip_root/TextLCD_rtl.xml
update_ip_catalog

# Identify the correct part family to use when instantiating primitives
set families_7series {spartan7 artix7 kintex7 virtex7 zynq}
set families_ultrascale {kintexu kintexuplus virtexu virtexuplus zynquplus}
set part_family [get_property family [get_parts -of_objects [current_project]]]
if {[lsearch -exact $families_7series $part_family] >= 0} {
    set part_family "7series"
    set supported_families $families_7series
} elseif {[lsearch -exact $families_ultrascale $part_family] >= 0} {
    set part_family "ultrascale"
    set supported_families $families_ultrascale
} else {
    error "Unsupported part family: $part_family"
}

# Create project, set description and related properties.
create_project $ip_name -ip -in_memory
set ip [ipx::create_core aero.org ip $ip_name $ip_vers]

set_property display_name           $ip_disp $ip
set_property vendor_display_name    "The Aerospace Corporation" $ip
set_property description            $ip_desc $ip
set_property company_url            {https://www.aero.org} $ip
set_property library                {satcat5} $ip
set_property taxonomy               {{/SatCat5}} $ip

# IP requires a list of { family Production family Production ... }
set supported_families_ip {}
foreach family $supported_families {
    lappend supported_families_ip $family
    lappend supported_families_ip Production
}
set_property supported_families $supported_families_ip $ip

# Create project subfolder.
file delete -force $ip_dir
file mkdir $ip_dir/src
file mkdir $ip_dir/util
set_property root_directory $ip_dir $ip

set fg_syn [ipx::add_file_group -type vhdl:synthesis {} $ip]
set fg_sim [ipx::add_file_group -type vhdl:simulation {} $ip]

# Add the SatCat5 icon.
set fg_util [ipx::add_file_group -type utility {} $ip]
file copy -force $ip_root/satcat5.png $ip_dir/util
set logo_file [ipx::add_file util/satcat5.png $fg_util]
set_property type LOGO $logo_file

# Copy a file to the working folder and add it to the source list.
# (Copying is the recommended best practice for packaging IP cores.)
proc ipcore_add_file { src_path src_name } {
    global ip ip_dir fg_syn fg_sim
    # Copy the file to the IP folder.
    file copy -force ${src_path}/${src_name} $ip_dir/src
    # Add to project using the new relative path.
    set dst_file src/${src_name}
    ipx::add_file $dst_file $fg_syn
    ipx::add_file $dst_file $fg_sim
    return $dst_file
}

# Add XCI files from a third-party IP-core to the project.
proc ipcore_add_xci { xci_name } {
    # Find the matching XCI in the project.
    set xci_file [get_files $xci_name.xci]
    # Split path/filename to add a copy to the package.
    set dst_file [ipcore_add_file [file dirname $xci_file] [file tail $xci_file]]
    return $dst_file
}

# Set top-level module given path and entity name.
# (Requires that filename match entity name + ".vhd")
proc ipcore_add_top { src_path src_entity } {
    global ip fg_syn fg_sim
    set dst_file [ipcore_add_file $src_path $src_entity.vhd]
    set_property model_name $src_entity $fg_syn
    set_property model_name $src_entity $fg_sim
    ipx::import_top_level_hdl -top_level_hdl_file $dst_file $ip
    ipx::add_model_parameters_from_hdl -top_level_hdl_file $dst_file $ip
    return $dst_file
}

# Create and associate a clock port.
proc ipcore_add_clock { clk_name bus_names {clk_type slave} } {
    global ip
    # Create the clock port.
    set intf [ipx::add_bus_interface $clk_name $ip]
    set_property -dict "
        abstraction_type_vlnv xilinx.com:signal:clock_rtl:1.0
        bus_type_vlnv xilinx.com:signal:clock:1.0
        interface_mode $clk_type
    " $intf
    set_property physical_name $clk_name [ipx::add_port_map CLK $intf]
    # Associate this clock with the given bus(es).
    foreach bus $bus_names {
        set_property value $bus [ipx::add_bus_parameter ASSOCIATED_BUSIF $intf]
    }
    return $intf
}

# Create and associate a level-sensitive interrupt port.
proc ipcore_add_irq { irq_name } {
    global ip
    set intf [ipx::add_bus_interface $irq_name $ip]
    set_property -dict "
        abstraction_type_vlnv xilinx.com:signal:interrupt_rtl:1.0
        bus_type_vlnv xilinx.com:signal:interrupt:1.0
        interface_mode master
    " $intf
    set_property physical_name $irq_name [ipx::add_port_map INTERRUPT $intf]
    set_property value LEVEL_HIGH [ipx::add_bus_parameter SENSITIVITY $intf]
    return $intf
}

# Create and associate a reset port.
# Polarity should be "ACTIVE_LOW" or "ACTIVE_HIGH".
proc ipcore_add_reset { rst_name polarity {mode slave} } {
    global ip
    set intf [ipx::add_bus_interface $rst_name $ip]
    set_property -dict "
        abstraction_type_vlnv xilinx.com:signal:reset_rtl:1.0
        bus_type_vlnv xilinx.com:signal:reset:1.0
        interface_mode $mode
    " $intf
    set_property physical_name $rst_name [ipx::add_port_map RST $intf]
    set_property value $polarity [ipx::add_bus_parameter POLARITY $intf]
    return $intf
}

# Create and associate a standard Ethernet port.
proc ipcore_add_ethport { label pname type } {
    global ip
    # Configure the high-level port object.
    set intf [ipx::add_bus_interface $label $ip]
    set_property abstraction_type_vlnv aero.org:satcat5:EthPort_rtl:1.0 $intf
    set_property bus_type_vlnv aero.org:satcat5:EthPort:1.0 $intf
    set_property interface_mode $type $intf
    # Associate individual signals.
    set_property physical_name ${pname}_rx_clk      [ipx::add_port_map "rx_clk"     $intf]
    set_property physical_name ${pname}_rx_data     [ipx::add_port_map "rx_data"    $intf]
    set_property physical_name ${pname}_rx_last     [ipx::add_port_map "rx_last"    $intf]
    set_property physical_name ${pname}_rx_write    [ipx::add_port_map "rx_write"   $intf]
    set_property physical_name ${pname}_rx_error    [ipx::add_port_map "rx_error"   $intf]
    set_property physical_name ${pname}_rx_rate     [ipx::add_port_map "rx_rate"    $intf]
    set_property physical_name ${pname}_rx_status   [ipx::add_port_map "rx_status"  $intf]
    set_property physical_name ${pname}_rx_reset    [ipx::add_port_map "rx_reset"   $intf]
    set_property physical_name ${pname}_tx_clk      [ipx::add_port_map "tx_clk"     $intf]
    set_property physical_name ${pname}_tx_data     [ipx::add_port_map "tx_data"    $intf]
    set_property physical_name ${pname}_tx_last     [ipx::add_port_map "tx_last"    $intf]
    set_property physical_name ${pname}_tx_valid    [ipx::add_port_map "tx_valid"   $intf]
    set_property physical_name ${pname}_tx_ready    [ipx::add_port_map "tx_ready"   $intf]
    set_property physical_name ${pname}_tx_error    [ipx::add_port_map "tx_error"   $intf]
    set_property physical_name ${pname}_tx_reset    [ipx::add_port_map "tx_reset"   $intf]
    return $intf
}

# Create and associate a 10-gigabit Ethernet port.
proc ipcore_add_xgeport { label pname type } {
    global ip
    # Configure the high-level port object.
    set intf [ipx::add_bus_interface $label $ip]
    set_property abstraction_type_vlnv aero.org:satcat5:EthPortX_rtl:1.0 $intf
    set_property bus_type_vlnv aero.org:satcat5:EthPortX:1.0 $intf
    set_property interface_mode $type $intf
    # Associate individual signals.
    set_property physical_name ${pname}_rx_clk      [ipx::add_port_map "rx_clk"     $intf]
    set_property physical_name ${pname}_rx_data     [ipx::add_port_map "rx_data"    $intf]
    set_property physical_name ${pname}_rx_nlast    [ipx::add_port_map "rx_nlast"   $intf]
    set_property physical_name ${pname}_rx_write    [ipx::add_port_map "rx_write"   $intf]
    set_property physical_name ${pname}_rx_error    [ipx::add_port_map "rx_error"   $intf]
    set_property physical_name ${pname}_rx_rate     [ipx::add_port_map "rx_rate"    $intf]
    set_property physical_name ${pname}_rx_status   [ipx::add_port_map "rx_status"  $intf]
    set_property physical_name ${pname}_rx_reset    [ipx::add_port_map "rx_reset"   $intf]
    set_property physical_name ${pname}_tx_clk      [ipx::add_port_map "tx_clk"     $intf]
    set_property physical_name ${pname}_tx_data     [ipx::add_port_map "tx_data"    $intf]
    set_property physical_name ${pname}_tx_nlast    [ipx::add_port_map "tx_nlast"   $intf]
    set_property physical_name ${pname}_tx_valid    [ipx::add_port_map "tx_valid"   $intf]
    set_property physical_name ${pname}_tx_ready    [ipx::add_port_map "tx_ready"   $intf]
    set_property physical_name ${pname}_tx_error    [ipx::add_port_map "tx_error"   $intf]
    set_property physical_name ${pname}_tx_reset    [ipx::add_port_map "tx_reset"   $intf]
    return $intf
}

# Create and associate an AXI4-Lite port.
# Reserves space in the AXI memory-map, default size 64 kbytes.
proc ipcore_add_axilite { label clk rst pname {msize "64k"} } {
    global ip
    # Create the AXI4-Lite high-level port.
    set intf [ipx::add_bus_interface $label $ip]
    set_property abstraction_type_vlnv xilinx.com:interface:aximm_rtl:1.0 $intf
    set_property bus_type_vlnv xilinx.com:interface:aximm:1.0 $intf
    set_property interface_mode slave $intf
    # Connect clock and reset ports.
    ipcore_add_clock $clk $label
    ipcore_add_reset $rst ACTIVE_LOW
    # Connect the AXI4-Lite port.
    set_property physical_name ${pname}_awaddr      [ipx::add_port_map AWADDR   $intf]
    set_property physical_name ${pname}_awvalid     [ipx::add_port_map AWVALID  $intf]
    set_property physical_name ${pname}_awready     [ipx::add_port_map AWREADY  $intf]
    set_property physical_name ${pname}_wdata       [ipx::add_port_map WDATA    $intf]
    set_property physical_name ${pname}_wstrb       [ipx::add_port_map WSTRB    $intf]
    set_property physical_name ${pname}_wvalid      [ipx::add_port_map WVALID   $intf]
    set_property physical_name ${pname}_wready      [ipx::add_port_map WREADY   $intf]
    set_property physical_name ${pname}_bresp       [ipx::add_port_map BRESP    $intf]
    set_property physical_name ${pname}_bvalid      [ipx::add_port_map BVALID   $intf]
    set_property physical_name ${pname}_bready      [ipx::add_port_map BREADY   $intf]
    set_property physical_name ${pname}_araddr      [ipx::add_port_map ARADDR   $intf]
    set_property physical_name ${pname}_arvalid     [ipx::add_port_map ARVALID  $intf]
    set_property physical_name ${pname}_arready     [ipx::add_port_map ARREADY  $intf]
    set_property physical_name ${pname}_rdata       [ipx::add_port_map RDATA    $intf]
    set_property physical_name ${pname}_rresp       [ipx::add_port_map RRESP    $intf]
    set_property physical_name ${pname}_rvalid      [ipx::add_port_map RVALID   $intf]
    set_property physical_name ${pname}_rready      [ipx::add_port_map RREADY   $intf]
    # Associate clock and reset with the AXI bus.
    set_property value $clk [ipx::add_bus_parameter ASSOCIATED_BUSIF $intf]
    set_property value $rst [ipx::add_bus_parameter ASSOCIATED_BUSIF $intf]
    # Register for a space in the address map.
    set mmap [ipx::add_memory_map $label $ip]
    set_property slave_memory_map_ref $label $intf
    set mblock [ipx::add_address_block ${label}_addr $mmap]
    set_property range $msize $mblock
}

# Create and associate a ConfigBus port.
proc ipcore_add_cfgbus { label pname type } {
    global ip
    # Configure the high-level port object.
    set intf [ipx::add_bus_interface $label $ip]
    set_property abstraction_type_vlnv aero.org:satcat5:ConfigBus_rtl:1.0 $intf
    set_property bus_type_vlnv aero.org:satcat5:ConfigBus:1.0 $intf
    set_property interface_mode $type $intf
    # Associate individual signals.
    set_property physical_name ${pname}_clk     [ipx::add_port_map "clk"     $intf]
    set_property physical_name ${pname}_devaddr [ipx::add_port_map "devaddr" $intf]
    set_property physical_name ${pname}_regaddr [ipx::add_port_map "regaddr" $intf]
    set_property physical_name ${pname}_wdata   [ipx::add_port_map "wdata"   $intf]
    set_property physical_name ${pname}_wstrb   [ipx::add_port_map "wstrb"   $intf]
    set_property physical_name ${pname}_wrcmd   [ipx::add_port_map "wrcmd"   $intf]
    set_property physical_name ${pname}_rdcmd   [ipx::add_port_map "rdcmd"   $intf]
    set_property physical_name ${pname}_reset_p [ipx::add_port_map "reset_p" $intf]
    set_property physical_name ${pname}_rdata   [ipx::add_port_map "rdata"   $intf]
    set_property physical_name ${pname}_rdack   [ipx::add_port_map "rdack"   $intf]
    set_property physical_name ${pname}_rderr   [ipx::add_port_map "rderr"   $intf]
    set_property physical_name ${pname}_irq     [ipx::add_port_map "irq"     $intf]
    # Optional "sysaddr" signal.
    catch {set_property physical_name ${pname}_sysaddr [ipx::add_port_map "sysaddr" $intf]}
    return $intf
}

# Create an optional ConfigBus endpoint with user configuration options.
proc ipcore_add_cfgopt { label pname } {
    # Create and associate the port.
    set cfgbus [ipcore_add_cfgbus $label $pname slave]
    # Add bus-enable and device-address parameters.
    ipcore_add_param CFG_ENABLE bool false
    set cfgaddr [ipcore_add_param CFG_DEV_ADDR devaddr 0]
    # Enable ports and parameters depending on configuration.
    set_property enablement_dependency {$CFG_ENABLE} $cfgbus
    set_property enablement_tcl_expr {$CFG_ENABLE} $cfgaddr
    return $cfgbus
}

# Create a generic port (i.e., std_logic or std_logic_vector)
proc ipcore_add_gpio { port_name } {
    global ip
    set intf [ipx::add_port $port_name $ip]
    return $intf
}

# Add IO primitives for the correct series part
proc ipcore_add_io { src_dir part_family } {
    if {$part_family == "7series"} {
        ipcore_add_file $src_dir    7series_io.vhd
    } elseif {$part_family == "ultrascale"} {
        ipcore_add_file $src_dir    ultrascale_io.vhd
    } else {
        error "Unsupported part family: $part_family"
    }
}

# Add synchronization primitives for the correct series part
proc ipcore_add_sync { src_dir part_family } {
    if {$part_family == "7series"} {
        ipcore_add_file $src_dir    7series_sync.vhd
    } elseif {$part_family == "ultrascale"} {
        ipcore_add_file $src_dir    ultrascale_sync.vhd
    } else {
        error "Unsupported part family: $part_family"
    }
}

# Add memory primitives for the correct series part
proc ipcore_add_mem { src_dir part_family } {
    if {$part_family == "7series"} {
        ipcore_add_file $src_dir    7series_mem.vhd
    } elseif {$part_family == "ultrascale"} {
        ipcore_add_file $src_dir    ultrascale_mem.vhd
    } else {
        error "Unsupported part family: $part_family"
    }
}

# Add a user-configured customizable parameter.
proc ipcore_add_param { param_name param_type param_default } {
    global ip
    # Create and bind the parameter.
    set param_hdl [ipx::get_hdl_parameters $param_name -of_objects $ip]
    set param_obj [ipx::add_user_parameter $param_name $ip]
    set param_gui [ipgui::add_param -name $param_name -component $ip]
    # Set value first.
    set_property value $param_default $param_obj
    set_property value $param_default $param_hdl
    # Special formatting for specific types.
    if {$param_type eq "bitstring"} {
        # Set fixed length (do not include "0b" or other prefix.
        set plen [string length $param_default]
        set_property value_bit_string_length $plen $param_obj
        set_property value_bit_string_length $plen $param_hdl
        # Reformat string to match Vivado requirements.
        set param_default \"$param_default\"
        set param_type bitstring
    } elseif {$param_type eq "hexstring"} {
        # Set fixed length (do not include "0x" other prefix)
        set plen [expr [string length $param_default] * 4]
        set_property value_bit_string_length $plen $param_obj
        set_property value_bit_string_length $plen $param_hdl
        set_property widget {hexEdit} $param_gui
        # Reformat string to match Vivado requirements.
        set param_default 0x$param_default
        set param_type bitstring
    } elseif {$param_type eq "devaddr"} {
        # Set upper and lower limits.
        set_property value_validation_type range_long $param_obj
        set_property value_validation_range_minimum 0 $param_obj
        set_property value_validation_range_maximum 255 $param_obj
        set param_type long
    }
    # Set remaining type parameters.
    set_property display_name $param_name $param_obj
    set_property value_resolve_type user $param_obj
    set_property value_format $param_type $param_obj
    set_property value_format $param_type $param_hdl
    set_property value $param_default $param_obj
    set_property value $param_default $param_hdl
    return $param_obj
}

# Package up the IP-core.
proc ipcore_finished {} {
    global ip
    ipx::create_xgui_files $ip
    ipx::check_integrity $ip
    ipx::save_core $ip
    close_project
    update_ip_catalog
    set ipname [get_property NAME $ip]
    puts "Finished creating $ipname"
}
