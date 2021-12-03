--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation
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
-- Port-interface wrapper for a generic AXI-stream
--
-- Xilinx IP-cores can only use simple std_logic and std_logic_vector types.
-- This shim provides that conversion.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.switch_types.all;

entity wrap_port_stream is
    generic (
    RATE_MBPS   : in  integer);
    port (
    -- AXI-stream interface (Rx).
    rx_clk      : in  std_logic;
    rx_data     : in  std_logic_vector(7 downto 0);
    rx_last     : in  std_logic;
    rx_valid    : in  std_logic;
    rx_ready    : out std_logic;
    rx_reset    : in  std_logic;

    -- AXI-stream interface (Tx).
    tx_clk      : in  std_logic;
    tx_data     : out std_logic_vector(7 downto 0);
    tx_last     : out std_logic;
    tx_valid    : out std_logic;
    tx_ready    : in  std_logic;
    tx_reset    : in  std_logic;

    -- Network port
    sw_rx_clk   : out std_logic;
    sw_rx_data  : out std_logic_vector(7 downto 0);
    sw_rx_last  : out std_logic;
    sw_rx_write : out std_logic;
    sw_rx_error : out std_logic;
    sw_rx_rate  : out std_logic_vector(15 downto 0);
    sw_rx_status: out std_logic_vector(7 downto 0);
    sw_rx_reset : out std_logic;
    sw_tx_clk   : out std_logic;
    sw_tx_data  : in  std_logic_vector(7 downto 0);
    sw_tx_last  : in  std_logic;
    sw_tx_valid : in  std_logic;
    sw_tx_ready : out std_logic;
    sw_tx_error : out std_logic;
    sw_tx_reset : out std_logic);
end wrap_port_stream;

architecture wrap_port_stream of wrap_port_stream is

begin

-- From user to switch.
sw_rx_clk       <= rx_clk;
sw_rx_data      <= rx_data;
sw_rx_last      <= rx_last;
sw_rx_write     <= rx_valid;
rx_ready        <= '1';
sw_rx_error     <= '0';
sw_rx_rate      <= get_rate_word(RATE_MBPS);
sw_rx_status    <= (others => '0');
sw_rx_reset     <= rx_reset;

-- From switch to user.
sw_tx_clk       <= tx_clk;
tx_data         <= sw_tx_data;
tx_last         <= sw_tx_last;
tx_valid        <= sw_tx_valid;
sw_tx_ready     <= tx_ready;
sw_tx_error     <= '0';
sw_tx_reset     <= tx_reset;

end wrap_port_stream;
