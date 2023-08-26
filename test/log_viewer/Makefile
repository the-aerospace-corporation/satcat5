# Copyright 2022 The Aerospace Corporation
#
# This file is part of SatCat5.
#
# SatCat5 is free software: you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# SatCat5 is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
# License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.

### constants
PROJECT ?= log_viewer
BUILD_DIR := build_tmp
IGNORE_ERROR := 2>&1 || cd .

### environment
ifeq ($(OS),Windows_NT)
    MKDIR=mkdir
    REMOVE=del /q /f
    PCAP_INC=./npcap/Include
    PCAP_LIB=-L./npcap/Lib/x64 -lws2_32 -lwpcap
else
    MKDIR=mkdir -p
    REMOVE=rm -rf
    PCAP_INC=
    PCAP_LIB=-lpcap
endif

### files
SRCS := \
	$(wildcard ./*.cc) \
	$(wildcard ../../src/cpp/hal_pcap/*.cc) \
	$(wildcard ../../src/cpp/hal_posix/*.cc) \
	$(wildcard ../../src/cpp/satcat5/*.cc)
BASENAME_SRCS := $(notdir $(SRCS))
VPATH += $(dir $(SRCS)) 
OBJS := $(BASENAME_SRCS:%=$(BUILD_DIR)/%.o)

INC_DIRS := \
	. \
	../../src/cpp \
	$(PCAP_INC)

### flags
INC_FLAGS := $(addprefix -I,$(INC_DIRS))
LDFLAGS := $(PCAP_LIB)
COMMON_FLAGS := -Wall -Wextra -Wno-unused-parameter \
	-DHAVE_REMOTE -DSATCAT5_LOG_EMOJI=0 $(INC_FLAGS)
CFLAGS := $(COMMON_FLAGS)
CXXFLAGS := $(COMMON_FLAGS) -std=c++11

### targets
.PHONY: all clean run

all: $(OBJS) $(PROJECT).bin

clean:
	$(REMOVE) $(BUILD_DIR)

run: all
	@$(PROJECT).bin

# Working folder
$(BUILD_DIR):
	$(MKDIR) $(BUILD_DIR)

# C++ source
$(BUILD_DIR)/%.cc.o: %.cc | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@

# C source
$(BUILD_DIR)/%.c.o: %.c | $(BUILD_DIR)
	$(CXX) $(CFLAGS) -c $< -o $@

# Binary
%.bin: $(OBJS)
	$(CXX) $^ $(LDFLAGS) -o $@
