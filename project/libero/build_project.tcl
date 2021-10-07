##########################################################################
## Copyright 2019, 2021 The Aerospace Corporation
##
## This file is part of SatCat5.
##
## SatCat5 is free software: you can redistribute it and/or modify it under
## the terms of the GNU Lesser General Public License as published by the
## Free Software Foundation, either version 3 of the License, or (at your
## option) any later version.
##
## SatCat5 is distributed in the hope that it will be useful, but WITHOUT
## ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
## FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
## License for more details.
##
## You should have received a copy of the GNU Lesser General Public License
## along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
##########################################################################

# Open the specified project
open_project [lindex $argv 0]
set PRJ_NAME [file rootname [file tail [lindex $argv 0]]]
puts "Opened Project $PRJ_NAME"

# Run build steps
update_and_run_tool -name {SYNTHESIZE}
run_tool -name {PLACEROUTE}
run_tool -name {VERIFYTIMING}
run_tool -name {GENERATEPROGRAMMINGDATA}

# Any RAM initialization goes here

# Finalize and generate bitstream
generate_design_initialization_data 
run_tool -name {GENERATEPROGRAMMINGFILE} 

# Generate FlashPro Express programming job to project/libero/$PRJ_NAME.job and $PRJ_NAME_job.digest
export_prog_job \
         -job_file_name $PRJ_NAME \
         -export_dir ./$PRJ_NAME \
         -bitstream_file_type {TRUSTED_FACILITY} \
         -bitstream_file_components {FABRIC SNVM} \
         -zeroization_likenew_action 0 \
         -zeroization_unrecoverable_action 0 \
         -program_design 1 \
         -program_spi_flash 0 \
         -include_plaintext_passkey 0 \
         -design_bitstream_format {STP} \
         -prog_optional_procedures {} \
         -skip_recommended_procedures {}
