# Folder Contents

![SatCat5 Logo](../../doc/images/satcat5.svg)

The files in this folder are used in VHDL unit tests.  (e.g., config_mdio_rom_tb)

* test_bin.dat (Binary test sequence 0x00, 0x01, ... 0xFF)
* test_hex.txt (Plaintext hexadecimal, same sequence, random mix of lowercase and uppercase)
* random_ethernet.txt (ascii hexadecimal random ethernet frames, one per line, without the FCS)
* random_macsec.txt (ascii hexadecimal macsec frames, one per line, generated from
    the frames in random_ethernet.txt using the configuration from macsec_config.txt)
* macsec_config.txt (the macsec configuration used to generate random_macsec.txt from random_ethernet.txt)

# Copyright Notice

Copyright 2019-2024 The Aerospace Corporation.

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.
