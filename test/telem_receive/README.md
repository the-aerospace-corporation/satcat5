# Telem_recieve README
This folder contains utilities to extract telemetry data from raw network packets.

## ptp_telem.py
    Extracts all telemetry packets (udpport 0x5A63) from the network.  The script detects multiple 
    telemetry types and creates a csv file for each.
    ### Requirements
    ### Testbench
        - test_ptp_telem.py

## telem2csv.py
    Extracts telemetry data from pcap files and writes to csv.
    A yaml config file is used to specify both packets of interest and the telemetry fields to 
    be written to the csv file.
    ### Requirements
    ```
    sudo apt install tshark
    pip install pyshark
    ```
    ### Example Configuration Files
    - example_traffic_and_mactbl.yaml:   prints out only rxb, rxf, txb, txf, and mactbl fields in switch telemetry data
    - example_ptp_status.yaml:           prints out all the fields of the ptp telemetry data


# Copyright Notice

Copyright 2024 The Aerospace Corporation.

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.

