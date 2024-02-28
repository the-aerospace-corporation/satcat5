#!/bin/bash
##########################################################################
## Copyright 2021 The Aerospace Corporation.
## This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
##########################################################################

set -e

# First argument should be the project name.
# Second argument should be the search path for project-specific HDL sources.
if [[ $# -lt 2 ]]; then
    echo "Missing DESIGN or SRC_PATH argument."
    exit 1
else
    DESIGN=$1
    SRC_PATH=$2
fi

# create work directory
WORKDIR=./$DESIGN
mkdir -p $WORKDIR

# analyze vhdl files
GHDL_OPTS="--warn-no-binding --workdir=$WORKDIR"
ghdl -i $GHDL_OPTS \
    $SRC_PATH/*.vhd \
    ../../src/vhdl/lattice/*.vhd \
    ../../src/vhdl/common/*.vhd

for x in $DESIGN_FILES; do ghdl -i $GHDL_OPTS $x; done

ghdl -m $GHDL_OPTS $DESIGN

# Run synthesis
# remove all assert statements after the "ghdl" step. They are not needed after that, 
# and yosys passes them straight through to pnr.
# Using the EXPERIMENTAL abc9 mapper gives a huge improvement in cell utilization (12%) and timing (200%). 
# TODO ensure that this is not removing critical logic
yosys -p "ghdl $GHDL_OPTS $DESIGN;
          read_verilog $SRC_PATH/*.v;
          delete t:\$assert;
          synth_ice40 -json $WORKDIR/$DESIGN.json;
          stat"

# place and route for iCE40HX-8K breakout board
# add some options to slightly improve timing with slightly longer runtime
# TODO: Add more arguments to support other device/package options.
nextpnr-ice40 --hx8k \
              --package ct256 \
              --freq 12 \
              --pcf $DESIGN.pcf \
              --pre-pack ${DESIGN}_timing.py \
              --asc $WORKDIR/$DESIGN.asc \
              --json $WORKDIR/$DESIGN.json \
              --opt-timing --promote-logic 
              #--timing-allow-fail

# pack ascii to binary bitstream
# icepack has no output
echo "running icepack"
icepack $WORKDIR/$DESIGN.asc $WORKDIR/$DESIGN.bin

# program - for user reference
#iceprog $DESIGN.bin
