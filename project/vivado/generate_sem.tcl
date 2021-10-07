# ------------------------------------------------------------------------
# Copyright 2019 The Aerospace Corporation
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
# This file declares a function generate_sem which can be called to
# instantiate a SEM IP with the given name (usually sem_0)
#

proc generate_sem { sem_name } {
    create_ip -name sem -vendor xilinx.com -library ip -module_name $sem_name
    set_property -dict [list\
        CONFIG.ENABLE_INJECTION {false}\
        CONFIG.ENABLE_CORRECTION {true}\
        CONFIG.ENABLE_CLASSIFICATION {false}\
        CONFIG.INJECTION_SHIM {none}\
        CONFIG.CLOCK_FREQ {100}\
    ] [get_ips $sem_name]
    generate_target {instantiation_template} [get_files $sem_name.xci]
    generate_target all [get_files $sem_name.xci]
    catch { config_ip_cache -export [get_ips -all $sem_name] }
    export_ip_user_files -of_objects [get_files $sem_name.xci] -no_script -sync -force -quiet
    create_ip_run [get_files -of_objects [get_fileset sources_1] $sem_name.xci]
}
