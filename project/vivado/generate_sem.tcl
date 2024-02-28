# ------------------------------------------------------------------------
# Copyright 2021-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This file declares a function generate_sem which can be called to
# instantiate a SEM IP with the given name (usually sem_0)
#

proc generate_sem { sem_name } {

    # Check part family. Current SEM core is 7 series only.
    # TODO: Add Ultrascale SEM support using sem_ultra core with different interface.
    set part_family [get_property family [get_parts -of_objects [current_project]]]
    if {[lsearch -exact {spartan7 artix7 kintex7 virtex7 zynq} $part_family] < 0} {
        puts {Unsupported part family for SEM core, not generating.}
        return
    }

    # Create IP
    create_ip -name sem -vendor xilinx.com -library ip -module_name $sem_name
    set_property -dict [list\
        CONFIG.ENABLE_INJECTION {false}\
        CONFIG.ENABLE_CORRECTION {true}\
        CONFIG.ENABLE_CLASSIFICATION {false}\
        CONFIG.INJECTION_SHIM {none}\
        CONFIG.CLOCK_FREQ {100}\
    ] [get_ips $sem_name]

    # Generate IP
    generate_target {instantiation_template} [get_files $sem_name.xci]
    generate_target all [get_files $sem_name.xci]
    catch { config_ip_cache -export [get_ips -all $sem_name] }
    export_ip_user_files -of_objects [get_files $sem_name.xci] -no_script -sync -force -quiet
    create_ip_run [get_files -of_objects [get_fileset sources_1] $sem_name.xci]
}
