--------------------------------------------------------------------------
-- Copyright 2020 The Aerospace Corporation
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
-- Null-sink port
--
-- This block is used to cap off unused ports in a design.
-- All received frames are discarded.  No frames are sent.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.switch_types.all;

entity port_nullsink is
    port (
    -- Generic internal port interface.
    rx_data     : out port_rx_m2s;
    tx_data     : in  port_tx_s2m;
    tx_ctrl     : out port_tx_m2s;

    -- Clock and reset.
    refclk      : in  std_logic;    -- Reference clock
    reset_p     : in  std_logic);   -- Reset / shutdown
end port_nullsink;

architecture port_nullsink of port_nullsink is

begin

-- Drive all output signals.
rx_data.clk     <= refclk;
rx_data.data    <= (others => '0');
rx_data.last    <= '0';
rx_data.write   <= '0';
rx_data.rxerr   <= '0';
rx_data.rate    <= get_rate_word(1000);
rx_data.status  <= (0 => reset_p, others => '0');
rx_data.reset_p <= reset_p;

tx_ctrl.clk     <= refclk;
tx_ctrl.ready   <= '1';
tx_ctrl.txerr   <= '0';
tx_ctrl.reset_p <= reset_p;

-- Unused inputs:
--  tx_data.data
--  tx_data.last
--  tx_data.valid

end port_nullsink;
