# Copyright 2021-2025 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

.PHONY: test verbose valgrind_test build clean coverage coverage_test precov

### constants
PROJECT ?= test_main
BUILD_DIR := build_tmp
SIM_DIR := simulations
COVERAGE_DIR := coverage
IGNORE_ERROR := 2>&1 || cd .

### environment
ifeq ($(OS),Windows_NT)
    COPY=copy /Y
    LIBS=-lWs2_32 -lpthread
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
	-fno-exceptions \
	-fno-inline \
	-fno-inline-functions \
	-fno-inline-small-functions
INC_FLAGS := $(addprefix -I,$(INC_DIRS))
LDFLAGS := --coverage
COVERAGE := --coverage -g -O0 $(NOINLINE)
COMMON_FLAGS := -MD -MP \
	-Wall -Wextra -Wno-unused-parameter \
	$(INC_FLAGS) \
	-DSATCAT5_CBOR_ENABLE=1 \
	-DSATCAT5_CHECK_DUPIRQ=1 \
	-DSATCAT5_CRC_TABLE_BITS=8 \
	-DSATCAT5_GCC_INTRINSICS=0 \
	-DSATCAT5_GCM_FAST=1 \
	-DSATCAT5_LOG_CONCISE=0 \
	-DSATCAT5_LOG_MAXLEN=1023 \
	-DSATCAT5_UDP_MAXDYN=256
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
coverage: $(COVERAGE_DIR)/coverage.txt $(COVERAGE_DIR)/coverage.html

test: build
	@echo Running tests...
	@$(REMOVE) $(BUILD_DIR)/*.gcda > $(NULL) $(IGNORE_ERROR)
	@$(BUILD_DIR)/$(PROJECT).bin

verbose: build
	@echo Running tests (verbose mode)...
	@$(BUILD_DIR)/$(PROJECT).bin -d yes

valgrind_test: build
	@echo Running tests with Valgrind...
	@valgrind --leak-check=full $(BUILD_DIR)/$(PROJECT).bin

build: $(SIM_DIR) $(OBJS) $(BUILD_DIR)/$(PROJECT).bin

clean:
	@$(REMOVE) $(BUILD_DIR)
	@$(REMOVE) $(SIM_DIR)
	@$(REMOVE) $(COVERAGE_DIR)

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

$(COVERAGE_DIR)/coverage.txt: precov
	@echo Preparing coverage.txt...
	@$(MKDIR) $(COVERAGE_DIR) > $(NULL) $(IGNORE_ERROR)
	@$(GCOVR) -o $(COVERAGE_DIR)/coverage.txt

$(COVERAGE_DIR)/coverage.html: precov
	@echo Preparing coverage.html...
	@$(REMOVE) $(COVERAGE_DIR)/*.html > $(NULL) $(IGNORE_ERROR)
	@$(MKDIR) $(COVERAGE_DIR) > $(NULL) $(IGNORE_ERROR)
	@$(GCOVR) --html --html-details --html-high-threshold $(REQUIRED_COVERAGE) -o $(COVERAGE_DIR)/coverage.html

coverage_test: precov
	@echo Coverage pass/fail?
	@$(GCOVR) --fail-under-line $(REQUIRED_COVERAGE) > $(NULL)
	@echo OK

# Forces rebuild of an object file if an included header is updated
-include $(OBJS:.o=.d)
