##########################################################################
# Copyright 2021 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
##########################################################################

ctx.addClock("clk_12", 12)
ctx.addClock("rmii_refclk", 50)

# Correctly derived - manual definition not required
#ctx.addClock("clk_25_00", 25)