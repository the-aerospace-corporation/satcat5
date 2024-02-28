# ModelSim Project Folder

The main file in this folder is "create_project.tcl", which is a script that creates a new Modelsim project. This project isn't required, but can be used for simulations and verification if you prefer that environment. It has been tested with ModelSim 10.0a, but should work with most other versions as well.

The ModelSim project requires the Xilinx UNISIM library. Compile this first, using [the instructions provided by Xilinx](https://www.xilinx.com/support/answers/64083.html).

When ready, create the ModelSim project by providing the UNISIM path:

    do create_project.tcl "path/to/unisim/library"

# Waveform Files

The other files in this folder are ".do" files for selected unit-test simulations. These can be loaded (File->Load...) before running to display salient signals and keep them logically organized. We have found these particular signals helpful in understanding operation (or debugging non-operation) of each block.

# Copyright Notice

Copyright 2021 The Aerospace Corporation.

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.