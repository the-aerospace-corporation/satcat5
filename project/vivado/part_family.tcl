# ------------------------------------------------------------------------
# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This TCL script sets global variable "part_family", inferring the family
# from the current project's target part. The options are:
#   "7series"       Spartan-7, Artix-7, Kintex-7, Virtex-7, Zynq-7xxx
#   "ultrascale"    Kintex-Ultrascale, Virtex-Ultrascale, Zynq-Ultrascale
#   "ultraplus"     Kintex-Ultrascale+, Virtex-Ultrascale+, Zynq-Ultrascale+
#

# Define parts associated with each family:
variable families_7series {spartan7 artix7 kintex7 virtex7 zynq}
variable families_ultrascale {kintexu virtexu}
variable families_ultraplus {kintexuplus virtexuplus zynquplus zynquplusRFSOC}

# Check the target part against each of the above lists.
set part_family [get_property family [get_parts -of_objects [current_project]]]
if {[lsearch -exact $families_7series $part_family] >= 0} {
    set part_family "7series"
    set supported_families $families_7series
} elseif {[lsearch -exact $families_ultrascale $part_family] >= 0} {
    set part_family "ultrascale"
    set supported_families $families_ultrascale
} elseif {[lsearch -exact $families_ultraplus $part_family] >= 0} {
    set part_family "ultraplus"
    set supported_families $families_ultraplus
} else {
    error "Unsupported part family: $part_family"
}
