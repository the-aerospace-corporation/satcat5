# Copyright 2025 The Aerospace Corporation
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

### constants
PROJECT ?= pkt_viewer
BUILD_DIR := build_tmp
IGNORE_ERROR := 2>&1 || cd .

### environment
ifeq ($(OS),Windows_NT)
    MKDIR=mkdir
    REMOVE=del /q /f
    LDFLAGS=-lws2_32 -lpthread
else
    MKDIR=mkdir -p
    REMOVE=rm -rf
endif

### files
SRCS := \
	$(wildcard ./*.cc) \
	$(wildcard ../../src/cpp/hal_posix/*.cc) \
	$(wildcard ../../src/cpp/satcat5/*.cc)
BASENAME_SRCS := $(notdir $(SRCS))
VPATH += $(dir $(SRCS))
OBJS := $(BASENAME_SRCS:%=$(BUILD_DIR)/%.o)

INC_DIRS := \
	. \
	../../src/cpp

### flags
INC_FLAGS := $(addprefix -I,$(INC_DIRS))
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
	$(CXX) $^ $(LDFLAGS) $(LIBS) -o $@

# Forces rebuild of an object file if an included header is updated
-include $(OBJS:.o=.d)
