# Vivado TCL Scripts

These scripts are specific to the Xilinx toolchain, primarily for project
creation and IP Integrator... integration.

## Generic

### Project Creation

The [shared_create.tcl](shared_create.tcl) script will create a Vivado project.
It is intended to simplify the process by providing a small set of parameters
as TCL global variables:

| Variable Name         | Description                           | Example Value             | Required?     |
| :-------------------- | :------------------------------------ | :------------------------ | :-----------: |
| target_proj           | Project name                          | vc707_managed             | &#9745; Yes   |
| target_part           | FPGA part and speed grade             | xc7vx485tffg1761-2        | &#9745; Yes   |
| target_board          | FPGA board, if a definition exists    | em.avnet.com:zed:part0:1.3| &#9744; No    |
| target_top            | Top-level file, if cannot be inferred | converter_zed_top         | &#9744; No    |
| files_main            | List of source files                  | ../src/my_file.vhd        | &#9745; Yes   |
| constr_synth          | File for synthesis constraints        | vc707_synth.xdc           | &#9745; Yes   |
| constr_impl           | File for implementation constraints   | vc707_impl.xdc            | &#9745; Yes   |
| override_script_dir   | Override for script working directory | /home/user/project        | &#9744; No    |
| override_postbit      | TCL script to be run after bitgen     | /home/user/bit_backup.tcl | &#9744; No    |

All file locations may be absolute or relative.  Relative paths are referenced
from the directory of the script *calling* `shared_create.tcl`. Wildcards may
be used in `files_main`.

### Project Build

Project build is much simpler. The script takes a single argument, the
directory at the root of the Vivado project. It will run synthesis,
implementation, and bitstream generation, returning a failure code if any
of the steps is not successful.

### Pre-Synthesis, Post-Bitgen

Projects created with [shared_create.tcl](shared_create.tcl) will
automatically run [shared_presynth.tcl](shared_presynth.tcl) before synthesis
launches and [shared_postbit.tcl](shared_postbit.tcl) after bitstream
generation completes. The pre-synthesis script sets the `BUILD_DATE` generic as
a string and passes it to the toplevel, allowing it to be passed to (typically)
`switch_aux` as part of the startup message. The post-bitgen script mostly
serves to automatically timestamp and backup builds to a `backups/` folder.
These scripts help reduce the possibility of "losing" working bitfiles.

## IP Integrator

The majority of SatCat5 IP, whose sources are found in
[/src/vhdl](../../src/vhdl), typically in the platform-agnostic
[common](../../src/vhdl/common) folder, have wrappers for convenient usage in
IP Integrator (block diagram) designs. More information on *usage* of these
blocks can be found in the
[IP Integrator Flow Documentation](../../doc/IPI_FLOW.md).
Documented here is the organization of the scripts and VHDL wrappers required
to facilitate this integration.

The [ipcores](ipcores) folder contains:

1. TCL scripts for the creation of IP Integrator cores
1. Xilinx-specific VHDL wrappers for the underlying SatCat5 source code
1. Interface definitions for EthPort and ConfigBus types

The TCL scripts for IP core creation typically add the required source files,
define all interfaces for the block, and add GUI options to control the generic
parameters listed in the source file. The majority of this is handled by
functions in [ipcore_shared.tcl](ipcores/ipcore_shared.tcl). The TCL script for
each IP core will add its VHDL wrapper in the same folder. These wrappers are
required, as Xilinx IP cores do not support record types on interfaces - thus
they mostly just map record types to `std_logic` and `std_logic_vector`.

Finally, the interface defintions provide the required definitions to provide
convenient single-wire interfaces between SatCat5 IP. It should be noted that
the authors have generally found these definitions to be termperamental -
please report any bugs found with these interfaces.

# Copyright Notice

Copyright 2022 The Aerospace Corporation.

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.
