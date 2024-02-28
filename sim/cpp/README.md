# C++ Unit-Test README

This folder contains unit tests for the SatCat5 embedded software framework.

It uses the "Catch" test framework. [Catch](https://github.com/catchorg/Catch2) is defined in a single .h file.

* [Download](https://raw.githubusercontent.com/catchorg/Catch2/master/single_include/catch2/catch.hpp)
* [Documentation](https://github.com/catchorg/Catch2/tree/master/docs).

## Building

To run the tests in a Linux environment, first install "gcov" and "gcovr". (Details vary by distribution.)

To run the tests in a Windows environment, first install [MinGW](https://nuwen.net/mingw.html#install).

Once all prerequisites are installed, run "make test" to run the unit tests or "make coverage" to generate a coverage report.

## Valgrind Usage

To make the tests and run with Valgrind (a [memory leak detection tool](https://valgrind.org/)), run `make valgrind_test`.

Note: Valgrind requires a Linux environment. Additionally, there may be tests with hard-coded
timeouts that fail due to the additional time it takes to run valgrind.

To download Valgrind, run `git clone https://sourceware.org/git/valgrind.git` and follow the instructions to build it from [here](https://valgrind.org/docs/manual/dist.readme.html)

Valgrind links to dependencies:

* [GNU M4](https://www.gnu.org/software/m4/m4.html), which is required for Autoconf
* [Autoconf](https://www.gnu.org/software/autoconf/), which is requied to setup Valgrind

## VSCode debugger using GDB

The VSCode debugger uses json files to determine how to debug the project. These json files include which debugger to use, where it's located, etc. These json files reside in the `.vscode` folder at the top of the repository and is usually one of the folders in the gitignore. 

If working in windows, and using MinGW, then gdb is already downloaded. Next, if there isn't already a `.vscode folder` at the top of the repository, create one now. In that folder, should be `launch.json` and `tasks.json`. If these don't already exist, create them now. Below is an example `launch.json` file. Note: change `miDebuggerPath` to be the path of your gdb.exe file.

``` {
    // Use IntelliSense to learn about possible attributes.
    // Hover to view descriptions of existing attributes.
    // For more information, visit: https://go.microsoft.com/fwlink/?linkid=830387
    
    
    "version": "0.2.0",
    "configurations": [
        {
            "name": "(gdb) build test and Launch",
            "type": "cppdbg",
            "request": "launch",
            "program": "${workspaceFolder}/sim/cpp/build_tmp/test_main.bin",
            "args": [],
            "stopAtEntry": false,
            "cwd": "${workspaceFolder}",
            "environment": [],
            "externalConsole": false,
            "MIMode": "gdb",
            "miDebuggerPath": "C:/Users/User/MinGW/bin/gdb.exe",
            "setupCommands": [
                {
                    "description": "Enable pretty-printing for gdb",
                    "text": "-enable-pretty-printing",
                    "ignoreFailures": true
                },
                {
                    "description": "Set Disassembly Flavor to Intel",
                    "text": "-gdb-set disassembly-flavor intel",
                    "ignoreFailures": true
                }
            ],
            "preLaunchTask": "build-and-test"
        },

        {
            "name": "(gdb) post-build Launch",
            "type": "cppdbg",
            "request": "launch",
            "program": "${workspaceFolder}/sim/cpp/build_tmp/test_main.bin",
            "args": [],
            "stopAtEntry": false,
            "cwd": "${workspaceFolder}",
            "environment": [],
            "externalConsole": false,
            "MIMode": "gdb",
            "miDebuggerPath": "C:/Users/User/MinGW/bin/gdb.exe",
            "setupCommands": [
                {
                    "description": "Enable pretty-printing for gdb",
                    "text": "-enable-pretty-printing",
                    "ignoreFailures": true
                },
                {
                    "description": "Set Disassembly Flavor to Intel",
                    "text": "-gdb-set disassembly-flavor intel",
                    "ignoreFailures": true
                }
            ],
            // "preLaunchTask": "build-and-test"
        }

    ],

    } 
```

Here is an example `tasks.json` file:

``` {
    "version": "2.0.0",
    "tasks": [
        {
            "label": "build-and-test",
            "type": "shell",
            "command": "make",
            "args": ["test"],
            "options": {
                "cwd": "sim/cpp"
            },
            "group": {
                "kind": "build",
                "isDefault": true
            }
        }
    ]
}
```

After these two files are created, in the debugger sidebar, a dropdown menu will appear where either version can be run. If the `make test` has already been run, then `(gdb) post-build Launch` will work. Otherwise, `(gdb) build test and Launch` will also `make test`.

To set breakpoints in vscode, click to the left of the line number. Left click to add a breakpoint, right click to have the option of a conditional breakpoint or a logpoint.

## Copyright Notice

Copyright 2021-2024 The Aerospace Corporation.

This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

You may redistribute and modify SatCat5 and make products using it under
the weakly reciprocal variant of the CERN Open Hardware License, version 2
or (at your option) any later weakly reciprocal version.

SatCat5 is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING
OF MERCHANTABILITY, SATISFACTORY QUALITY, AND FITNESS FOR A PARTICULAR
PURPOSE. Please see (https:/cern.ch/cern-ohl) for applicable conditions.
