# ModelSim Project Folder

The main file in this folder is "create_project.tcl", which is a script that creates a new Modelsim project. This project isn't required, but can be used for simulations and verification if you prefer that environment. It has been tested with ModelSim 10.0a, but should work with most other versions as well.

The ModelSim project requires the Xilinx UNISIM library. Compile this first, using [the instructions provided by Xilinx](https://www.xilinx.com/support/answers/64083.html).

When ready, create the ModelSim project by providing the UNISIM path:

    do create_project.tcl "path/to/unisim/library"

# Waveform Files

The other files in this folder are ".do" files for selected unit-test simulations. These can be loaded (File->Load...) before running to display salient signals and keep them logically organized. We have found these particular signals helpful in understanding operation (or debugging non-operation) of each block.

# Copyright Notice

Copyright 2019 The Aerospace Corporation

This file is part of SatCat5.

SatCat5 is free software: you can redistribute it and/or modify it under
the terms of the GNU Lesser General Public License as published by the
Free Software Foundation, either version 3 of the License, or (at your
option) any later version.

SatCat5 is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
License for more details.

You should have received a copy of the GNU Lesser General Public License
along with SatCat5.  If not, see [https://www.gnu.org/licenses/](https://www.gnu.org/licenses/).
