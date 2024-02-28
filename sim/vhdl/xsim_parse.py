#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# Copyright 2019-2023 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

'''
Search directory for simulation logs and create
junit-compatible XML file that Jenkins can understand
Example:
<?xml version="1.0" encoding="utf-8"?>
<testsuite tests="3">
    <testcase classname="foo1" name="ASuccessfulTest"/>
    <testcase classname="foo2" name="AnotherSuccessfulTest"/>
    <testcase classname="foo3" name="AFailingTest">
        <failure type="NotEnoughFoo"> details about failure </failure>
    </testcase>
</testsuite>
'''
import glob
import os
import time
import junit_xml

# Set working folder for input and output data.
try:
    par_phase = int(os.environ.get('PARALLEL_PHASE'))
except:
    par_phase = 0   # Default if undefined or empty
work_folder = f'xsim_tmp_{par_phase}'

# Parse each of the simulation logs.
sim_logs = glob.glob(f'{work_folder}/simulate_*_tb.log')
test_cases = []
for log in sim_logs:
    # Some simulations print a "PASSED" message when done;
    # others do not.  For now, don't expect it to be there.
    IGNORE_MISSING_PASS_MSG = True
    # Set initial state, then attempt to open the log file.
    sim_started = False     # Started simulation
    sim_completed = False   # Simulation finished (not truncated)
    sim_error = False       # Failed to parse results
    sim_failed = False      # Simulation reports error
    sim_passed = False      # Simulation reports success
    try:
        print('Parsing: %s'%log)
        with open(log, 'rt') as fh:
            for line in fh.readlines():
                # Skip to start of actual simulation
                if not sim_started:
                    sim_started = line.find('## run')==0
                elif not sim_completed:
                    if 'Error:' in line:
                        sim_failed = True
                    if 'PASSED' in line:
                        sim_passed = True
                    # Check for exit, possibly might have tons of errors and clipped file
                    if 'Exiting xsim' in line:
                        sim_completed = True
    except Exception as ex:
        print('Failed parsing %s: %s'%(log,ex))
        sim_error = True
    # Translate results for JUnit.
    test_name = os.path.basename(log).replace('simulate_','').replace('.log','')
    case = junit_xml.TestCase(test_name, classname='pico_ethernet', timestamp=time.time())
    if sim_error:
        print('error')
        case.add_error_info('Error: Failed parsing simulation results')
    elif not sim_completed:
        print('error')
        case.add_error_info('Error: Simulation results appear to be truncated (could not find Exit message)')
    elif sim_failed:
        print('failed')
        case.add_failure_info('Failure: Error detected in simulation')
    elif sim_passed or IGNORE_MISSING_PASS_MSG:
        print('passed')
        pass # Success!
    else:
        case.add_error_info('Error: Invalid simulation log - unsure of result')
        print('invalid')
    test_cases.append(case)

test_suite = junit_xml.TestSuite('pico_ethernet', test_cases)
with open(f'{work_folder}/sim_results.xml', 'wt') as fh:
    junit_xml.TestSuite.to_file(fh, [test_suite])
