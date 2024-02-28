# Contributing to SatCat5

![SatCat5 Logo](images/satcat5.svg)

Would you like to help with SatCat5? We are excited to work with you.

# Code of Conduct

We strive to maintain a welcoming community for all potential contributors. By participating, you are expected to uphold this ideal. A written code of conduct may be added in a later release. Please report any unacceptable behavior by [emailing us here](open-source@aero.org).

# Bug reports

We track bugs, feature requests, and other issues on the project's [issues page](https://github.com/the-aerospace-corporation/satcat5/issues).

# Code contributions

Do you have code you would like to contribute to SatCat5? We are able to accept small changes immediately and require a Contributor License Agreement (CLA) for larger changesets. Generally documentation and other minor changes less than 10 lines do not require a CLA.

## Contributor License Agreement

The Aerospace Corporation CLA is based on the well-known Harmony Agreements CLA created by Canonical, and protects the rights of The Aerospace Corporation, our customers, and you as the contributor. [You can find our CLA and further instructions here](https://aerospace.org/cla). Please complete the CLA and send us the executed copy.

Once a CLA is on file, we can accept pull requests on GitHub or GitLab.

If you have any questions, please [e-mail us here](open-source@aero.org).

## Style Guidelines

* A CERN-OHL-W copyright notice is required in all files where it is practical to include one.
* We strive to maintain readable code.  Please adhere to the following guidelines:
  * Indent size four spaces, spaces only (no tab characters),
  * No trailing spaces at end of line.
  * Names such as "Tx" and "Rx" should usually refer to the switch FPGA context. (i.e., "Tx" should be an FPGA output.)
  * (Python only) All public methods should include a triple-quoted docstring.
  * (VHDL only) All reset signals indicate polarity (_p = Active High, _n = Active Low).
* Whenever practical, all VHDL functional blocks should include an automated unit test:
  * Test failures are indicated using "report" or "assert" statements with severity of "error" or higher.
  * A comment at the top of the file should indicate the runtime required to complete the test.
  * Add your unit test to the [Jenkins shell script](../sim/vhdl/xsim_run.sh).
* Whenever practical, all C++ functional blocks should include an automated unit test.
  * Our unit tests use the [Catch framework](https://github.com/catchorg/Catch2).
  * Code coverage is analyzed using gcov and gcovr.

# Copyright Notice

Copyright 2020, 2021 The Aerospace Corporation

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.
