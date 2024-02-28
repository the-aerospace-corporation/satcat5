# ------------------------------------------------------------------------
# Copyright 2021-2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This TCL script defines functions that are used by other scripts in this
# folder, to create and package Xilinx IP-cores.
#
# Since some IP-cores must be generated with part-specific parameters, this
# script must be called *after* creating the host project.  The new IP-core
# catalog entries are created in that project's working directory.
#
# Before calling this script, you MUST set the following:
#   ip_name = Short filename (e.g., "switch_dual")
#   ip_vers = Version number (e.g., "1.0")
#   ip_disp = Display name (e.g., "SatCat5 dual-port switch")
#   ip_desc = Longer description (e.g., "A two-port switch, typically used..."")
#

# Create the following variables in this namespace
variable ip
variable ip_root
variable ip_cat
variable ip_dir
variable src_dir
variable proj_dir
variable part_family
variable fg_syn
variable fg_sim

# Root folder contains this script, HDL wrappers, and port definitions.
set ip_root [file normalize [file dirname [info script]]]

# Relative path to most HDL source files, located under "src/vhdl":
set src_dir [file normalize "$ip_root/../../../src/vhdl/"]

# Target folder for the catalog and the newly-created IP-core.
set proj_dir [get_property DIRECTORY [current_project]]
set ip_cat [file normalize "$proj_dir/satcat5_ip"]
set ip_dir [file normalize "$proj_dir/satcat5_ip/$ip_name"]

# First-time setup of the IP-catalog?
variable ipcount [llength [get_ipdefs *satcat5*]]
if {$ipcount eq 0} {
    puts "First-time SatCat5 IP setup..."
    # Create an empty catalog folder and add it to search path.
    file mkdir $ip_cat
    variable old_path [get_property ip_repo_paths [current_fileset]]
    variable new_path [concat $old_path $ip_cat]
    set_property ip_repo_paths $new_path [current_fileset]
    # Add custom interface definitions to the IP-catalog.
    update_ip_catalog -rebuild -quiet
    update_ip_catalog -repo_path $ip_cat -add_interface $ip_root/ConfigBus.xml
    update_ip_catalog -repo_path $ip_cat -add_interface $ip_root/ConfigBus_rtl.xml
    update_ip_catalog -repo_path $ip_cat -add_interface $ip_root/EthPort.xml
    update_ip_catalog -repo_path $ip_cat -add_interface $ip_root/EthPort_rtl.xml
    update_ip_catalog -repo_path $ip_cat -add_interface $ip_root/EthPortX.xml
    update_ip_catalog -repo_path $ip_cat -add_interface $ip_root/EthPortX_rtl.xml
    update_ip_catalog -repo_path $ip_cat -add_interface $ip_root/PtpTime.xml
    update_ip_catalog -repo_path $ip_cat -add_interface $ip_root/PtpTime_rtl.xml
    update_ip_catalog -repo_path $ip_cat -add_interface $ip_root/TextLCD.xml
    update_ip_catalog -repo_path $ip_cat -add_interface $ip_root/TextLCD_rtl.xml
    update_ip_catalog -repo_path $ip_cat -add_interface $ip_root/VernierClk.xml
    update_ip_catalog -repo_path $ip_cat -add_interface $ip_root/VernierClk_rtl.xml
    update_ip_catalog -rebuild -quiet
}

# Identify the correct part family to use when instantiating primitives
source "$ip_root/../part_family.tcl"

# Create project, set description and related properties.
puts "Creating $ip_name..."
variable current_part [get_property part [current_project]]
create_project $ip_name -ip -in_memory -part $current_part
set_property ip_repo_paths $ip_cat [current_fileset]
set ip [ipx::create_core aero.org ip $ip_name $ip_vers]

set_property display_name           $ip_disp $ip
set_property vendor_display_name    "The Aerospace Corporation" $ip
set_property description            $ip_desc $ip
set_property company_url            {https://www.aero.org} $ip
set_property library                {satcat5} $ip
set_property taxonomy               {{/SatCat5}} $ip

# IP requires a list of { family Production family Production ... }
set_msg_config -suppress -id {[IP_Flow 19-4623]}
variable supported_families_ip {}
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
variable logo_file [ipx::add_file util/satcat5.png $fg_util]
set_property type LOGO $logo_file

# Suppress various spurious warnings:
# TODO: Better fix for false-alarm warnings about custom bus types?
set_msg_config -new_severity INFO -id {[IP_Flow 19-569]};       # Missing bus abstraction
set_msg_config -new_severity INFO -id {[IP_Flow 19-570]};       # Missing bus definition
set_msg_config -new_severity INFO -id {[DesignUtils 20-1280]};  # Unused nested IP-core
set_msg_config -suppress -id {[IP_Flow 19-2181]};               # Payment required flag
set_msg_config -suppress -id {[IP_Flow 19-2187]};               # Missing product guide
set_msg_config -suppress -id {[IP_Flow 19-2403]};               # TODO: What is this?

# Copy file(s) to the working folder and add them to the source list.
# (Copying is the recommended best practice for packaging IP cores.)
proc ipcore_add_file { src_pattern {folder src} } {
    global ip ip_dir fg_syn fg_sim
    # Create the target folder if it doesn't already exist.
    file mkdir "${ip_dir}/${folder}"
    # For each file matching the specified pattern...
    # (Glob will throw an error for zero matches, as desired.)
    set dst_list {}
    foreach src_file [glob ${src_pattern}] {
        # Copy the file to the IP folder.
        file copy -force "${src_file}" "${ip_dir}/${folder}"
        # Add to project using the new relative path.
        set dst_file "${folder}/[file tail ${src_file}]"
        ipx::add_file "${dst_file}" $fg_syn
        ipx::add_file "${dst_file}" $fg_sim
        # Separate list of new files returned to user.
        lappend dst_list "${dst_file}"
    }
    return $dst_list
}

# Add XCI files from a third-party IP-core to the project.
proc ipcore_add_xci { xci_name {export_files 0} } {
    # Find the matching XCI in the project.
    set xci_file [get_files $xci_name.xci]
    # Generate files for the new core.
    generate_target {instantiation_template} $xci_file
    # Split path/filename to add a copy to the package.
    set dst_file [ipcore_add_file $xci_file $xci_name]]
    # Some cores require additional files through the export tool.
    if {$export_files} {
        set more_files [export_ip_user_files -of_objects $xci_file -no_script -sync -force -quiet]
        foreach file $more_files {ipcore_add_file $file $xci_name}
    }
    return $dst_file
}

# Set top-level module given path and entity name.
proc ipcore_add_top { top_file } {
    global ip fg_syn fg_sim part_family src_dir
    # Add IO, memory, and synchronization primitives for the designated family.
    ipcore_add_file ${src_dir}/xilinx/${part_family}_*.vhd
    # Extract entity name from the filename
    # (Filename is required to match entity name + extension.)
    set top_entity [file rootname [file tail $top_file]]
    # Add the requested top-level file.
    set dst_file [ipcore_add_file ${top_file}]
    # Set top-level entity for this IP-core.
    set_property model_name $top_entity $fg_syn
    set_property model_name $top_entity $fg_sim
    ipx::import_top_level_hdl -top_level_hdl_file $dst_file $ip
    ipx::add_model_parameters_from_hdl -top_level_hdl_file $dst_file $ip
    return $dst_file
}

# Create and associate a clock port.
proc ipcore_add_clock { clk_name bus_names {clk_type slave} {clk_freq 0} } {
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
    # Set the clock frequency for validation and clarity, if requested
    if {$clk_freq > 0} {
        set_property value $clk_freq [ipx::add_bus_parameter FREQ_HZ $intf]
    }
    return $intf
}

# Create and associate a differential clock port.
proc ipcore_add_diffclock { label pname {type slave} {clk_freq 0} } {
    global ip
    # Create the port.
    set intf [ipx::add_bus_interface $label $ip]
    set_property abstraction_type_vlnv xilinx.com:interface:diff_clock_rtl:1.0 $intf
    set_property bus_type_vlnv xilinx.com:interface:diff_clock:1.0 $intf
    set_property interface_mode $type $intf
    # Associate individual signals.
    set_property physical_name ${pname}_p   [ipx::add_port_map CLK_P $intf]
    set_property physical_name ${pname}_n   [ipx::add_port_map CLK_N $intf]
    # Set the clock frequency for validation and clarity, if requested
    if {$clk_freq > 0} {
        set_property value $clk_freq [ipx::add_bus_parameter FREQ_HZ $intf]
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
    set_property physical_name ${pname}_rx_tsof     [ipx::add_port_map "rx_tsof"    $intf]
    set_property physical_name ${pname}_rx_reset    [ipx::add_port_map "rx_reset"   $intf]
    set_property physical_name ${pname}_tx_clk      [ipx::add_port_map "tx_clk"     $intf]
    set_property physical_name ${pname}_tx_data     [ipx::add_port_map "tx_data"    $intf]
    set_property physical_name ${pname}_tx_last     [ipx::add_port_map "tx_last"    $intf]
    set_property physical_name ${pname}_tx_valid    [ipx::add_port_map "tx_valid"   $intf]
    set_property physical_name ${pname}_tx_ready    [ipx::add_port_map "tx_ready"   $intf]
    set_property physical_name ${pname}_tx_error    [ipx::add_port_map "tx_error"   $intf]
    set_property physical_name ${pname}_tx_pstart   [ipx::add_port_map "tx_pstart"  $intf]
    set_property physical_name ${pname}_tx_tnow     [ipx::add_port_map "tx_tnow"    $intf]
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
    set_property physical_name ${pname}_rx_tsof     [ipx::add_port_map "rx_tsof"    $intf]
    set_property physical_name ${pname}_rx_reset    [ipx::add_port_map "rx_reset"   $intf]
    set_property physical_name ${pname}_tx_clk      [ipx::add_port_map "tx_clk"     $intf]
    set_property physical_name ${pname}_tx_data     [ipx::add_port_map "tx_data"    $intf]
    set_property physical_name ${pname}_tx_nlast    [ipx::add_port_map "tx_nlast"   $intf]
    set_property physical_name ${pname}_tx_valid    [ipx::add_port_map "tx_valid"   $intf]
    set_property physical_name ${pname}_tx_ready    [ipx::add_port_map "tx_ready"   $intf]
    set_property physical_name ${pname}_tx_error    [ipx::add_port_map "tx_error"   $intf]
    set_property physical_name ${pname}_tx_pstart   [ipx::add_port_map "tx_pstart"  $intf]
    set_property physical_name ${pname}_tx_tnow     [ipx::add_port_map "tx_tnow"    $intf]
    set_property physical_name ${pname}_tx_reset    [ipx::add_port_map "tx_reset"   $intf]
    return $intf
}

# Create and associate a PTP real-time clock (i.e., date/time).
proc ipcore_add_ptptime { label pname type } {
    global ip
    # Configure the high-level port object.
    set intf [ipx::add_bus_interface $label $ip]
    set_property abstraction_type_vlnv aero.org:satcat5:PtpTime_rtl:1.0 $intf
    set_property bus_type_vlnv aero.org:satcat5:PtpTime:1.0 $intf
    set_property interface_mode $type $intf
    # Associate individual signals.
    # All ports required on master; only "clk" is required on slaves.
    set_property physical_name ${pname}_clk         [ipx::add_port_map "clk"    $intf]
    set hdl_port [ipx::get_ports ${pname}_sec -of_objects $ip]
    if {$type == "master" || $hdl_port != ""} {
        set_property physical_name ${pname}_sec     [ipx::add_port_map "sec"    $intf]
    }
    set hdl_port [ipx::get_ports ${pname}_nsec -of_objects $ip]
    if {$type == "master" || $hdl_port != ""} {
        set_property physical_name ${pname}_nsec    [ipx::add_port_map "nsec"   $intf]
    }
    set hdl_port [ipx::get_ports ${pname}_subns -of_objects $ip]
    if {$type == "master" || $hdl_port != ""} {
        set_property physical_name ${pname}_subns   [ipx::add_port_map "subns"  $intf]
    }
    return $intf
}

# Create and associate a SGMII interface.
proc ipcore_add_sgmii { label pname {type "master"} } {
    global ip
    # Configure the high-level port object.
    set intf [ipx::add_bus_interface $label $ip]
    set_property abstraction_type_vlnv xilinx.com:interface:sgmii_rtl:1.0 $intf
    set_property bus_type_vlnv xilinx.com:interface:sgmii:1.0 $intf
    set_property interface_mode $type $intf
    # Associate individual signals.
    set_property physical_name ${pname}_rxp     [ipx::add_port_map RXP  $intf]
    set_property physical_name ${pname}_rxn     [ipx::add_port_map RXN  $intf]
    set_property physical_name ${pname}_txp     [ipx::add_port_map TXP  $intf]
    set_property physical_name ${pname}_txn     [ipx::add_port_map TXN  $intf]
    return $intf
}

# Create and associate a Text-LCD interface.
proc ipcore_add_textlcd { label pname {type "master"} } {
    global ip
    # Configure the high-level port object.
    set intf [ipx::add_bus_interface $label $ip]
    set_property abstraction_type_vlnv aero.org:satcat5:TextLCD_rtl:1.0 $intf
    set_property bus_type_vlnv aero.org:satcat5:TextLCD:1.0 $intf
    set_property interface_mode $type $intf
    # Associate individual signals.
    set_property physical_name ${pname}_lcd_db  [ipx::add_port_map "lcd_db" $intf]
    set_property physical_name ${pname}_lcd_e   [ipx::add_port_map "lcd_e"  $intf]
    set_property physical_name ${pname}_lcd_rw  [ipx::add_port_map "lcd_rw" $intf]
    set_property physical_name ${pname}_lcd_rs  [ipx::add_port_map "lcd_rs" $intf]
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
    set hdl_sysaddr [ipx::get_ports ${pname}_sysaddr -of_objects $ip]
    if {$type == "master" || $hdl_sysaddr != ""} {
        set_property physical_name ${pname}_sysaddr [ipx::add_port_map "sysaddr" $intf]
    }
    return $intf
}

# Create an optional ConfigBus endpoint with user configuration options.
proc ipcore_add_cfgopt { label pname } {
    # Create and associate the port.
    set cfgbus [ipcore_add_cfgbus $label $pname slave]
    # Add bus-enable and device-address parameters.
    ipcore_add_param CFG_ENABLE bool false {ConfigBus enabled?}
    set cfgaddr [ipcore_add_param CFG_DEV_ADDR devaddr 0 {ConfigBus device address}]
    # Enable ports and parameters depending on configuration.
    set_property enablement_dependency {$CFG_ENABLE} $cfgbus
    set_property enablement_tcl_expr {$CFG_ENABLE} $cfgaddr
    return $cfgbus
}

# Create and associate a Vernier clock reference.
proc ipcore_add_reftime { label pname type } {
    global ip
    # Configure the high-level port object.
    set intf [ipx::add_bus_interface $label $ip]
    set_property abstraction_type_vlnv aero.org:satcat5:VernierClk_rtl:1.0 $intf
    set_property bus_type_vlnv aero.org:satcat5:VernierClk:1.0 $intf
    set_property interface_mode $type $intf
    # Associate individual signals.
    set_property physical_name ${pname}_vclka   [ipx::add_port_map "vclka"  $intf]
    set_property physical_name ${pname}_vclkb   [ipx::add_port_map "vclkb"  $intf]
    set_property physical_name ${pname}_tnext   [ipx::add_port_map "tnext"  $intf]
    set_property physical_name ${pname}_tstamp  [ipx::add_port_map "tstamp" $intf]
    return $intf
}

# Create an Vernier reference port with user configuration options.
# (Port is optional by default, but can be made mandatory if desired.)
proc ipcore_add_refopt { label pname {optional true} } {
    # Create and associate the port.
    # Note: Use "monitor" rather than "slave" to allow one-to-many connection.
    set refport [ipcore_add_reftime $label $pname monitor]
    # Add PTP-enable and reference-frequency parameters.
    if {$optional} {ipcore_add_param PTP_ENABLE bool false {Enable PTP timestamps?}}
    set vrefhz [ipcore_add_param PTP_REF_HZ long 0 {Vernier reference frequency}]
    set tau_ms [ipcore_add_param PTP_TAU_MS long 50 {Synchronizer filter constant}]
    set aux_en [ipcore_add_param PTP_AUX_EN bool true {Additional synchronizer filter}]
    # Enable ports and parameters depending on configuration?
    if {$optional} {
        set_property enablement_dependency {$PTP_ENABLE} $refport
        set_property enablement_tcl_expr {$PTP_ENABLE} $vrefhz
        set_property enablement_tcl_expr {$PTP_ENABLE} $tau_ms
        set_property enablement_tcl_expr {$PTP_ENABLE} $aux_en
    }
    return $refport
}

# Create a generic port (i.e., std_logic or std_logic_vector)
proc ipcore_add_gpio { port_name } {
    global ip
    set intf [ipx::add_port $port_name $ip]
    return $intf
}

# Add a user-configured customizable parameter.
# All types from UG1118 Chapter 4 are accepted except "float", plus a few
# custom types (see below) that automatically set formatting:
#     PARAM_TYPE    VHDL Type           Description
#   * bitstring     std_logic_vector    String of 1's and 0's.
#   * bool          boolean             Simple "true" or "false".
#   * devaddr       integer             ConfigBus device address.
#   * hexstring     std_logic_vector    Hexadecimal string (0-9, A-F).
#   * long          integer             General-purpose integer.
#   * string        string              General-purpose text string.
# If desired, caller can explicitly set min/max range as follows:
#   set param [ipcore_add_param MY_PARAM long 12 {Example tooltip}]
#   set_property value_validation_type range_long $param
#   set_property value_validation_range_minimum 1 $param
#   set_property value_validation_range_maximum 64 $param
proc ipcore_add_param { param_name param_type param_default param_tooltip {param_editable true} } {
    global ip
    # Create and bind the parameter.
    set param_obj [ipx::add_user_parameter $param_name $ip]
    set param_gui [ipgui::add_param -name $param_name -component $ip]
    set param_hdl [ipx::get_hdl_parameters $param_name -of_objects $ip]
    # Parameters with no HDL counterpart are for display purposes only.
    set has_hdl [expr {$param_hdl != ""}]
    if {!($has_hdl) && $param_editable} {
        puts "Error adding $param_name: Only HDL parameters can be editable."
        return -code error $param_hdl
    }
    # Set value first.
    set_property value $param_default $param_obj
    if {$has_hdl} {set_property value $param_default $param_hdl}
    # Special formatting for specific types.
    if {$param_type eq "bitstring"} {
        # Set fixed length (do not include "0b" or other prefix.
        set plen [string length $param_default]
        set_property value_bit_string_length $plen $param_obj
        if {$has_hdl} {set_property value_bit_string_length $plen $param_hdl}
        # Reformat string to match Vivado requirements.
        set param_default \"$param_default\"
        set param_type bitstring
    } elseif {$param_type eq "hexstring"} {
        # Set fixed length (do not include "0x" other prefix)
        set plen [expr [string length $param_default] * 4]
        set_property value_bit_string_length $plen $param_obj
        if {$has_hdl} {set_property value_bit_string_length $plen $param_hdl}
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
    set_property display_name $param_name $param_gui
    set_property tooltip $param_tooltip $param_gui
    set_property value_resolve_type user $param_obj
    set_property value_format $param_type $param_obj
    if {$has_hdl} {set_property value_format $param_type $param_hdl}
    set_property value $param_default $param_obj
    if {$has_hdl} {set_property value $param_default $param_hdl}
    set_property enablement_value $param_editable $param_obj
    return $param_obj
}

# Abort packaging of this core. (i.e, Exit without saving.)
proc ipcore_abort {} {
    global ip
    close_project
    set ipname [get_property NAME $ip]
    puts "Cancelled creation of $ipname"
}

# Package up the IP-core.
proc ipcore_finished {} {
    global ip ip_cat
    ipx::create_xgui_files $ip
    ipx::check_integrity $ip
    ipx::save_core $ip
    close_project
    update_ip_catalog -repo_path $ip_cat -rebuild
    set ipname [get_property NAME $ip]
    puts "Finished creating $ipname"
}
