::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Copyright 2019 The Aerospace Corporation
::
:: This file is part of SatCat5.
::
:: SatCat5 is free software: you can redistribute it and/or modify it under
:: the terms of the GNU Lesser General Public License as published by the
:: Free Software Foundation, either version 3 of the License, or (at your
:: option) any later version.
::
:: SatCat5 is distributed in the hope that it will be useful, but WITHOUT
:: ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
:: FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
:: License for more details.
::
:: You should have received a copy of the GNU Lesser General Public License
:: along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

REM -- Script must be run from within the project source folder.
REM -- LIBERO_PATH variable may need to be modified if not correct.
REM set "LIBERO_PATH=C:\Microsemi\Libero_SoC_v12.3\Designer\bin\libero.exe"

IF "%LIBERO_PATH%"=="" (
	set /P LIBERO_PATH="Please enter path to Libero executable: "
)

set "BUILD_IP_SCRIPT_PATH=%cd%\gen_ip.tcl"
set "BUILD_PROJ_SCRIPT_PATH=%cd%\create_project_mpf_splash_rgmii.tcl"

if exist %cd%\switch_mpf_splash_rgmii (
	ECHO "Deleting existing project"
	RD /Q /S "%cd%\switch_mpf_splash_rgmii"
)

%LIBERO_PATH% SCRIPT:%BUILD_PROJ_SCRIPT_PATH%