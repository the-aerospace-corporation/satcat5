# SatCat5 DevOps

![SatCat5 Logo](images/satcat5.svg)

SatCat5 uses a "DevOps" deployment cycle where end-users always pull from the latest stable build.

Internally, we use Jenkins to perform automated builds and unit-tests for every new version of SatCat5.
This allows a rapid "Continuous Integration and Continuous Deployment" (CICD) build cycle.
Rigorous automated tests allow rapid deployment without compromising software quality.

The provided Jenkins script will not function outside our company LAN,
but can serve as a template for your own automated build systems.
This file documents the build system so that you can duplicate this functionality.

# Jenkins

A locally-hosted Git repository (aerosource2.aero.org) is used for internal development.
The contents are mirrored to GitHub for each public release.
For various reasons, the entire release is usually condensed to a single commit.

A Jenkins server (dcid.aero.org) monitors the internal Git repo for changes (new commits, new branches, etc.).
Most changes will automatically trigger a build as specified in the [Jenkinsfile](../Jenkinsfile).

Long FPGA builds are farmed out in parallel to an array of individual servers, called "agents".
We use Docker to simplify deployment of required software to each agent.
As a result, most agents are generic compute resources with only Docker and a simple host OS.

# Docker Registry

Most FPGA platforms require the use of proprietary vendor software.
To obtain this software, contact the FPGA vendor (Microsemi, Xilinx, etc.).

We maintain a locally-hosted Docker registry (also hosted at dcid.aero.org).
It is stocked with containers where these tools have been installed.
Some are installed using automated docker-files; others require manual intervention.
Each image installs a specific version of the vendor tool (e.g., "libero:12.3", "vivado:2019.1").

When loaded, commercial software tools are backed by floating licenses from an internally-hosted license server.

# Build process

The build process typically starts by pulling the appropriate Docker image,
then building a designated "make" target.
Some targets generate bitfiles for a specific FPGA design;
others run simulations or software unit tests.
Once the build is completed, artifacts such as bitfiles, logs, and reports are archived.

# Hardware-in-the-loop Testing

New features and bug-fixes are tested on various hardware platforms.
At present, these tests are performed manually, using the Jenkins build artifacts.
Future releases may include scripts for automated hardware testing.

# Review process

In both the internal and GitHub repositories, the main Git branch is never manipulated directly.

Instead, new features or bugfixes are added to a separate temporary branch.
Branches that pass the automated build process are eligible to open a pull request.
This request undergoes a peer-review process before it may be approved and merged into the main branch.

If you [contribute changes to SatCat5](CONTRIBUTING.md),
we will run the same tests on your behalf and follow the same review process.

# Copyright Notice

Copyright 2021 The Aerospace Corporation

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.
