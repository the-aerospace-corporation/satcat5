#!/bin/bash
# ------------------------------------------------------------------------
# Copyright 2021-2022 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
# ------------------------------------------------------------------------
#
# This script starts a Docker session, including X-windows GUI support
# for interactive sessions (or for non-interactive Xilinx tools that
# require it regardless), network support for contacting license servers,
# and other required hooks and workarounds.
#
# By default it pulls from a local Aerospace registry; outside users
# must specify their own DOCKER_REG.  For more information, refer to
# "../docs/DEVOPS.md".
#

# Abort immediately on any non-zero return code.
set -e

# Set default VIVADO_VERSION, if not already set.
if [[ -z "${VIVADO_VERSION}" ]]; then
    export VIVADO_VERSION="2016.3"
fi

# Set default Docker Registry (hostname:port), if not already set.
# (Note: Users outside of The Aerospace Corporation will need to change this.)
if [[ -z "${DOCKER_REG}" ]]; then
    export DOCKER_REG="e3-devops.aero.org"
fi

# Set license server for Microchip and Vivado tools.
# (Note: Users outside of The Aerospace Corporation will need to change this.)
if [[ -z "${XILINXD_LICENSE_FILE}" ]]; then
    export XILINXD_LICENSE_FILE="2100@dcid-licenses00.aero.org:2100@dcid-licenses01.aero.org:2100@dcid-licenses02.aero.org"
fi

# Name of Docker image is the first argument, if there is one.
# Otherwise, default to the designated version of Vivado.
if [[ $# -ne 0 ]]; then
    IMAGE=$DOCKER_REG/$1
    shift
else
    IMAGE=$DOCKER_REG/csaps/vivado:${VIVADO_VERSION}_latest
fi

# Fetch current user-ID
USER_ID=$(id -u)

# Print hostname for Jenkins troubleshooting.
echo "Starting Docker: ${IMAGE} on $(hostname)"

# Command to start docker
if [[ $IMAGE == $DOCKER_REG/libero:12.3 ]]; then
    # Libero image requires different options than all others
    # Working directory is mapped as /hdl
    DOCKER_CMD="docker run \
        --rm \
        -v ${PWD}:/hdl/ \
        --mac-address=84:a9:3e:6c:f3:b2 \
        -w /hdl"
else
    # Start docker with GUI support (also needed to build ELF)
    # Pass in user id to avoid file permissions issues
    # Working directory is mapped as ${USER}/hdl
    # Must also pass in /etc/passwd so USER_IDs can be resolved
    # Must also mount $HOME for things like .Xilinx and .Xauthority
    DOCKER_CMD="docker run \
        --rm --init \
        --network=host \
        -u ${USER_ID} \
        -v ${PWD}:/home/${USER}/hdl/ \
        -v ${HOME}:/home/${USER} \
        -v /etc/passwd:/etc/passwd:ro \
        -e DISPLAY=${DISPLAY} \
        -e PARALLEL_PHASE=${PARALLEL_PHASE} \
        -e PARALLEL_SIMS=${PARALLEL_SIMS} \
        -e VIVADO_VERSION=${VIVADO_VERSION} \
        -e XILINXD_LICENSE_FILE=${XILINXD_LICENSE_FILE} \
        -w /home/${USER}/hdl"
fi

# Run command if specified, otherwise interactive mode.
if [[ $# -ne 0 ]]; then
    ${DOCKER_CMD} ${IMAGE} "$@"
else
    ${DOCKER_CMD} -it ${IMAGE} bash
fi
