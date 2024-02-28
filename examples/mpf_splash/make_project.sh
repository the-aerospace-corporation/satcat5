#!/bin/bash
# ------------------------------------------------------------------------
# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------

# Create and build libero projects

set -e

cd $(dirname ${BASH_SOURCE[0]})
pwd

rm -rf ./switch_mpf_splash_rgmii_100T

xvfb-run -d libero SCRIPT:create_project_mpf_splash_rgmii.tcl "SCRIPT_ARGS:100T"
xvfb-run -d libero SCRIPT:../../project/libero/build_project.tcl "SCRIPT_ARGS:./switch_mpf_splash_rgmii_100T/switch_mpf_splash_rgmii_100T.prjx"

# allow reading outside the container
chmod -R a+rw ./switch_mpf_splash_rgmii_100T
