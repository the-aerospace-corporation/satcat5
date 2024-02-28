# ------------------------------------------------------------------------
# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------

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
