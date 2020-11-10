--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation
--
-- This file is part of SatCat5.
--
-- SatCat5 is free software: you can redistribute it and/or modify it under
-- the terms of the GNU Lesser General Public License as published by the
-- Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- SatCat5 is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
-- License for more details.
--
-- You should have received a copy of the GNU Lesser General Public License
-- along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
--------------------------------------------------------------------------
--
-- Data-type definitions used for the switch core.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

package SWITCH_TYPES is
    -- Each input port is unidirectional:
    type port_rx_m2s is record
        clk     : std_logic;
        data    : std_logic_vector(7 downto 0);
        last    : std_logic;
        write   : std_logic;
        rxerr   : std_logic;
        reset_p : std_logic;
    end record;

    -- Each output port requires inputs and outputs:
    type port_tx_m2s is record
        data    : std_logic_vector(7 downto 0);
        last    : std_logic;
        valid   : std_logic;
    end record;

    type port_tx_s2m is record
        clk     : std_logic;
        ready   : std_logic;
        txerr   : std_logic;
        reset_p : std_logic;
    end record;

    -- Define arrays for each port type:
    type array_rx_m2s is array(natural range<>) of port_rx_m2s;
    type array_tx_m2s is array(natural range<>) of port_tx_m2s;
    type array_tx_s2m is array(natural range<>) of port_tx_s2m;

    -- Generic 8-bit data stream with AXI flow-control:
    type axi_stream8 is record
        data    : std_logic_vector(7 downto 0);
        last    : std_logic;
        valid   : std_logic;
        ready   : std_logic;
    end record;
    
    constant AXI_STREAM8_IDLE : axi_stream8 := (
        data => (others => '0'), last => '0', valid => '0', ready => '0');

    -- Error reporting: Width of the errvec_t signal from switch_core.
    constant SWITCH_ERR_WIDTH : integer := 8;
end package;
