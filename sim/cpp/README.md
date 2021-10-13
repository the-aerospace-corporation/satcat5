# C++ Unit-Test README

This folder contains unit tests for the SatCat5 embedded software framework.

It uses the "Catch" test framework. [Catch](https://github.com/catchorg/Catch2) is defined in a single .h file.
* [Download](https://raw.githubusercontent.com/catchorg/Catch2/master/single_include/catch2/catch.hpp)
* [Documentation](https://github.com/catchorg/Catch2/tree/master/docs).

# Building

To run the tests in a Linux environment, first install "gcov" and "gcovr". (Details vary by distribution.)

To run the tests in a Windows environment, first install [MinGW](https://nuwen.net/mingw.html#install).

Once all prerequisites are installed, run "make test" to run the unit tests or "make coverage" to generate a coverage report.

# Copyright Notice

Copyright 2021 The Aerospace Corporation

This file is part of SatCat5.

SatCat5 is free software: you can redistribute it and/or modify it under
the terms of the GNU Lesser General Public License as published by the
Free Software Foundation, either version 3 of the License, or (at your
option) any later version.

SatCat5 is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
License for more details.

You should have received a copy of the GNU Lesser General Public License
along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
