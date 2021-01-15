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
-- A simple byte-by-byte MDIO writer.
--
-- The "Management Data Input/Output" (MDIO) is an interface defined in
-- IEEE 802.3, Part 3.  It is commonly used to configure Ethernet PHY
-- transceivers.  This block implements a write-only bus controller that
-- is controlled by a byte stream.  This stream MUST contain the preamble,
-- start, write, and other tokens; they are not generated by this state
-- machine.
--
-- Note: This block uses packet-at-a-time flow control.  The "valid"
-- strobe for the first byte should not be raised until the entire frame
-- has been received.  This is the default for fifo_packet, but UART-based
-- interfaces will need to buffer the frame contents.
--
-- Currently this block is write-only, it doesn't support MDIO reads.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity io_mdio_writer is
    generic (
    CLKREF_HZ   : positive;         -- Main clock rate (Hz)
    MDIO_BAUD   : positive);        -- MDIO baud rate (bps)
    port (
    -- Command stream
    cmd_data    : in  byte_t;
    cmd_last    : in  std_logic;
    cmd_valid   : in  std_logic;
    cmd_ready   : out std_logic;

    -- MDIO interface
    mdio_clk    : out std_logic;
    mdio_data   : out std_logic;
    mdio_oe     : out std_logic;

    -- System interface
    ref_clk     : in  std_logic;    -- Reference clock
    reset_p     : in  std_logic);
end io_mdio_writer;

architecture rtl of io_mdio_writer is

signal cmd_write    : std_logic;
signal mdio_ready   : std_logic := '1';
signal mdio_clk_i   : std_logic := '0';
signal mdio_data_i  : std_logic := '1';
signal mdio_oe_i    : std_logic := '0';

begin

-- Drive all output signals.
mdio_clk  <= mdio_clk_i and mdio_oe_i;
mdio_data <= mdio_data_i or not mdio_oe_i;
mdio_oe   <= mdio_oe_i;

-- Upstream flow control.
cmd_ready <= mdio_ready;
cmd_write <= mdio_ready and cmd_valid;

-- MDIO state machine.
p_mdio : process(ref_clk)
    -- Calculate delay per quarter-bit.
    -- (Specified rate is maximum, so round up.)
    constant DELAY_QTR  : natural := clocks_per_baud(CLKREF_HZ, 4*MDIO_BAUD);
    -- Local state.
    variable byte_final : std_logic := '0';
    variable out_sreg   : byte_t := (others => '1');
    variable bit_count  : integer range 0 to 7 := 0;
    variable qtr_count  : integer range 0 to 3 := 0;
    variable clk_count  : natural range 0 to DELAY_QTR-1 := 0;
begin
    if rising_edge(ref_clk) then
        -- Output-enable state machine.
        if (reset_p = '1') then
            mdio_oe_i <= '0';   -- Global reset
        elsif (cmd_write = '1') then
            mdio_oe_i <= '1';   -- Any write starts command
        elsif (qtr_count = 0 and bit_count = 0 and clk_count = 0 and byte_final = '1') then
            mdio_oe_i <= '0';   -- Release at end of the very last bit
        end if;

        -- Drive clock and data signals.
        mdio_clk_i  <= bool2bit(qtr_count = 1 or qtr_count = 2);
        mdio_data_i <= out_sreg(7); -- MSB first

        -- Upstream flow control.
        if (cmd_write = '1') then
            mdio_ready <= '0'; -- Force low while counters are updated.
        else
            mdio_ready  <= bool2bit(qtr_count = 0 and bit_count = 0 and clk_count < 2);
        end if;

        -- Update shift register.
        if (cmd_write = '1') then
            -- Load the next byte.
            out_sreg := cmd_data;
            byte_final := cmd_last;
        elsif (clk_count = 0 and qtr_count = 0) then
            -- Move to the next bit.
            out_sreg := out_sreg(6 downto 0) & '1';
        end if;

        -- Update counters.
        if (reset_p = '1') then
            -- Reset.
            bit_count := 0;
            qtr_count := 0;
            clk_count := 0;
        elsif (cmd_write = '1') then
            -- Start of new byte.
            bit_count := 7;
            qtr_count := 3;
            clk_count := DELAY_QTR - 1;
        elsif (clk_count > 0) then
            -- Countdown to next quarter-bit.
            clk_count := clk_count - 1;
        elsif (qtr_count > 0) then
            -- Countdown to next full-bit.
            qtr_count := qtr_count - 1;
            clk_count := DELAY_QTR - 1;
        elsif (bit_count > 0) then
            -- Start of next bit.
            bit_count := bit_count - 1;
            qtr_count := 3;
            clk_count := DELAY_QTR - 1;
        end if;
    end if;
end process;

end rtl;
