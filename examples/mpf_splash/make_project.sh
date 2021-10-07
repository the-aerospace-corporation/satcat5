#!/bin/bash
# ------------------------------------------------------------------------
# Copyright 2021 The Aerospace Corporation
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

# Create and build libero projects

set -e

cd $(dirname ${BASH_SOURCE[0]})
pwd

rm -rf ./switch_mpf_splash_rgmii_100T

xvfb-run -d libero SCRIPT:create_project_mpf_splash_rgmii.tcl "SCRIPT_ARGS:100T"
xvfb-run -d libero SCRIPT:../../project/libero/build_project.tcl "SCRIPT_ARGS:./switch_mpf_splash_rgmii_100T/switch_mpf_splash_rgmii_100T.prjx"

# allow reading outside the container
chmod -R a+rw ./switch_mpf_splash_rgmii_100T
