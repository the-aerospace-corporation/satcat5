# Copyright 2021-2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

.PHONY: test build clean coverage coverage_test precov

### constants
PROJECT ?= test_main
BUILD_DIR := build_tmp
SIM_DIR := simulations
IGNORE_ERROR := 2>&1 || cd .

### environment
ifeq ($(OS),Windows_NT)
    COPY=copy /Y
    MKDIR=mkdir
    MOVE=move /Y
    NULL=NUL
    REMOVE=del /q /f
else
    COPY=cp -f
    MKDIR=mkdir -p
    MOVE=mv -f
    NULL=/dev/null
    REMOVE=rm -rf
endif

### files
SRCS := \
	$(wildcard ./*.cc) \
	$(wildcard ../../src/cpp/hal_devices/*.cc) \
	$(wildcard ../../src/cpp/hal_posix/*.cc) \
	$(wildcard ../../src/cpp/hal_test/*.cc) \
	$(wildcard ../../src/cpp/qcbor/*.c) \
	$(wildcard ../../src/cpp/satcat5/*.cc)
BASENAME_SRCS := $(notdir $(SRCS))
VPATH += $(dir $(SRCS)) 
OBJS := $(BASENAME_SRCS:%=$(BUILD_DIR)/%.o)

INC_DIRS := \
	. \
	../../src/cpp

### flags
# Note: GCC flags match common best practices for code-coverage tests.
NOINLINE := \
	-fno-default-inline \
	-fno-early-inlining \
	-fno-elide-constructors \
	-fno-inline \
	-fno-inline-functions \
	-fno-inline-small-functions
INC_FLAGS := $(addprefix -I,$(INC_DIRS))
LDFLAGS := --coverage
COVERAGE := --coverage -g -O0 $(NOINLINE)
COMMON_FLAGS := -Wall -Wextra -Wno-unused-parameter $(INC_FLAGS) \
	-DSATCAT5_CBOR_ENABLE=1 \
	-DSATCAT5_CHECK_DUPIRQ=1 \
	-DSATCAT5_CRC_TABLE_BITS=8 \
	-DSATCAT5_LOG_CONCISE=0
CFLAGS := $(COMMON_FLAGS)
CXXFLAGS := $(COMMON_FLAGS) -std=c++11
GCOVR := gcovr $(BUILD_DIR) -g -k -r ../.. \
	--exclude test_.* \
	--exclude ../../src/cpp/hal_devices/ \
	--exclude ../../src/cpp/hal_posix/ \
	--exclude ../../src/cpp/hal_test/ \
	--exclude ../../src/cpp/qcbor/ \
	--object-directory $(BUILD_DIR)

### targets
coverage: coverage.txt coverage.html coverage.xml

test: build
	@echo Running tests...
	@$(BUILD_DIR)/$(PROJECT).bin

valgrind_test: build
	@echo Running tests with Valgrind...
	@valgrind --leak-check=full $(BUILD_DIR)/$(PROJECT).bin

build: $(SIM_DIR) $(OBJS) $(BUILD_DIR)/$(PROJECT).bin

clean:
	@$(REMOVE) $(BUILD_DIR)
	@$(REMOVE) $(SIM_DIR)

### rules
# Working folders
$(BUILD_DIR):
	@$(MKDIR) $(BUILD_DIR)
$(SIM_DIR):
	@$(MKDIR) $(SIM_DIR)

# Special case for main.cc (disable coverage)
$(BUILD_DIR)/main.cc.o: main.cc | $(BUILD_DIR)
	@echo Compiling main.cc...
	@$(CXX) $(CPPFLAGS) $(CXXFLAGS) -O3 -c main.cc -o $@

# C++ source
$(BUILD_DIR)/%.cc.o: %.cc | $(BUILD_DIR)
	@echo Compiling $<...
	@$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(COVERAGE) -c $< -o $@

# C source
$(BUILD_DIR)/%.c.o: %.c | $(BUILD_DIR)
	@echo Compiling $<...
	@$(CXX) $(CFLAGS) $(COVERAGE) -c $< -o $@

# Binary
%.bin: $(OBJS)
	@echo Linking $@...
	@$(CXX) $^ $(LDFLAGS) $(LIBS) -o $@

### Required code-coverage percentage for pass/fail in "coverage_test"
REQUIRED_COVERAGE := 100.0

# Coverage reports (requires GCOVR)
precov: test | $(BUILD_DIR)
	@echo Coverage analysis...
	@gcov -mrx $(BUILD_DIR)/*.gcda > $(NULL)
	@$(MOVE) *.gcov $(BUILD_DIR) > $(NULL)

coverage.txt: precov
	@echo Preparing coverage.txt...
	@$(GCOVR) -o coverage.txt

coverage.html: precov
	@echo Preparing coverage.html...
	@$(REMOVE) coverage > $(NULL) $(IGNORE_ERROR)
	@$(MKDIR) coverage > $(NULL) $(IGNORE_ERROR)
	@$(GCOVR) --html --html-details --html-high-threshold $(REQUIRED_COVERAGE) -o coverage/coverage.html

coverage.xml: precov
	@echo Preparing coverage.xml...
	@$(GCOVR) --xml -o coverage.xml

coverage_test: precov
	@echo Coverage pass/fail?
	@$(GCOVR) --fail-under-line $(REQUIRED_COVERAGE) > $(NULL)
	@echo OK
