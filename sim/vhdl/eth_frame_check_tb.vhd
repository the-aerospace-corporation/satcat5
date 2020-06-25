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
-- Testbench for the Ethernet frame verification.
--
-- This testbench generates randomized Ethernet frames in the
-- following categories:
--      * Valid frames with an EtherType field.
--      * Valid frames with a length field.
--      * Invalid frames that are too short or too long.
--      * Invalid frames with a mismatched length field.
--      * Invalid frames with a mismatched check sequence.
--
-- The output is inspected to verify that the data is correct and
-- the commit/revert strobes are asserted correctly.
--
-- The test runs indefinitely, with reasonably complete coverage
-- (200 packets) after about two milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity eth_frame_check_tb is
    -- Unit testbench top level, no I/O ports
end eth_frame_check_tb;

architecture tb of eth_frame_check_tb is

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Input stream generation.
signal pkt_len      : integer := 256;
signal pkt_etype    : boolean := false;

signal in_port      : port_rx_m2s;
signal in_rate      : real := 0.0;
signal in_data      : std_logic_vector(7 downto 0) := (others => '0');
signal in_last      : std_logic := '0';
signal in_write     : std_logic := '0';
signal in_commit    : std_logic := '0';
signal in_revert    : std_logic := '0';

-- Output stream.
signal out_data     : std_logic_vector(7 downto 0);
signal out_write    : std_logic;
signal out_commit   : std_logic;
signal out_revert   : std_logic;

-- Matched-delay FIFO.
signal fifo_in      : std_logic_vector(9 downto 0);
signal fifo_out     : std_logic_vector(9 downto 0);
signal ref_data     : std_logic_vector(7 downto 0);
signal ref_commit   : std_logic;
signal ref_revert   : std_logic;
signal ref_valid    : std_logic;
signal ref_index    : integer := 0;

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Set rate of input stream.
p_rate : process
begin
    wait until (reset_p = '0');
    for n in 1 to 9 loop
        in_rate <= 0.1 * real(n);
        wait for 100 us;
    end loop;
end process;

-- Raw stream generation for valid packets.
u_src : entity work.eth_traffic_gen
    generic map(
    AUTO_START  => true)
    port map(
    clk         => clk_100,
    reset_p     => reset_p,
    pkt_len     => pkt_len,
    pkt_etype   => pkt_etype,
    mac_dst     => x"DD",
    mac_src     => x"CC",
    out_rate    => in_rate,
    out_port    => in_port);

-- Packet state machine and data-replacement.
-- (Allows generation of various types of invalid packets.)
p_src : process(clk_100)
    -- PRNG state
    variable seed1      : positive := 1234;
    variable seed2      : positive := 5678;
    variable rand       : real := 0.0;

    -- Packet generator state.
    variable pkt_valid  : std_logic := '1'; -- Is this a valid packet?
    variable pkt_badfcs : boolean := false; -- Send incorrect FCS?
    variable pkt_badlen : boolean := false; -- Send incorrect length?
    variable pkt_bidx   : integer := 0;     -- Current byte index
    variable pkt_rem    : integer := 0;     -- Remaining byte count
begin
    if rising_edge(clk_100) then
        -- Synchronization sanity check.
        if (in_port.write = '1' and pkt_rem = 0) then
            if (ref_index = 0) then
                pkt_rem := pkt_len;  -- Special case on startup.
            else
                report "Counter underflow" severity error;
            end if;
        end if;
        if (in_port.write = '1' and in_port.last = '1') then
            assert (pkt_rem = 1)
                report "Desync at packet " & integer'image(ref_index)
                severity error;
        end if;

        -- Tamper with length or CRC fields as requested.
        -- Otherwise, forward the streaming data unchanged.
        if (pkt_badlen and pkt_bidx = 13) then
            in_data <= not in_port.data;
        elsif (pkt_badfcs and pkt_rem = 4) then
            in_data <= not in_port.data;
        else
            in_data <= in_port.data;
        end if;
        in_last   <= in_port.last;
        in_write  <= in_port.write;
        in_commit <= in_port.last and pkt_valid;
        in_revert <= in_port.last and not pkt_valid;

        -- Randomize packet length BEFORE start of each packet.
        if (pkt_rem = 2 and in_port.write = '1') then
            pkt_len <= 2 + integer(floor(rand*real(MAX_FRAME_BYTES+10)));
        end if;

        -- Update byte counters, and randomize all other parameters.
        if (in_port.write = '1') then
            if (in_port.last = '0') then
                -- Normal increment
                pkt_bidx := pkt_bidx + 1;
                pkt_rem  := pkt_rem - 1;
            else
                -- End of packet, get ready for next.
                pkt_bidx := 0;
                pkt_rem  := pkt_len;
                -- Randomize various parameters.
                uniform(seed1, seed2, rand);
                pkt_badfcs := (rand < 0.1);
                uniform(seed1, seed2, rand);
                if (rand < 0.3) then
                    pkt_etype  <= true;     -- Ethertype, can't have invalid length.
                    pkt_badlen := false;
                else
                    uniform(seed1, seed2, rand);
                    pkt_etype  <= false;    -- Length field with chance of tamper.
                    pkt_badlen := (rand < 0.1);
                end if;
                -- Is this a valid packet?
                pkt_valid := bool2bit((pkt_len >= MIN_FRAME_BYTES)
                                  and (pkt_len <= MAX_FRAME_BYTES)
                                  and not (pkt_badfcs or pkt_badlen));
            end if;
        end if;
    end if;
end process;

-- Unit under test
uut : entity work.eth_frame_check
    port map(
    in_data     => in_data,
    in_last     => in_last,
    in_write    => in_write,
    out_data    => out_data,
    out_write   => out_write,
    out_commit  => out_commit,
    out_revert  => out_revert,
    clk         => clk_100,
    reset_p     => reset_p);

-- Matched-delay FIFO.
fifo_in     <= in_commit & in_revert & in_data;
ref_commit  <= fifo_out(9);
ref_revert  <= fifo_out(8);
ref_data    <= fifo_out(7 downto 0);

u_fifo : entity work.smol_fifo
    generic map(
    IO_WIDTH     => 10,
    DEPTH_LOG2   => 6)   -- FIFO depth = 2^N
    port map(
    in_data      => fifo_in,
    in_write     => in_write,
    out_data     => fifo_out,
    out_valid    => ref_valid,
    out_read     => out_write,
    reset_p      => reset_p,
    clk          => clk_100);

-- Output checking.
p_check : process(clk_100)
begin
    if rising_edge(clk_100) then
        if (out_write = '1') then
            assert (ref_valid = '1')
                report "Unexpected output data" severity error;
            assert (out_data = ref_data)
                report "Data mismatch in packet " & integer'image(ref_index)
                severity error;
            assert (out_commit = ref_commit)
                report "Commit mismatch for packet " & integer'image(ref_index)
                severity error;
            assert (out_revert = ref_revert)
                report "Revert mismatch for packet " & integer'image(ref_index)
                severity error;
        elsif (reset_p = '0') then
            assert (out_commit = '0' and out_revert = '0')
                report "Unexpected commit/revert strobe" severity error;
        end if;

        if (reset_p = '1') then
            ref_index <= 0;
        elsif (out_write = '1' and (ref_commit = '1' or ref_revert = '1')) then
            if (ref_index = 200) then
                report "Tested 200th packet." severity note;
            end if;
            ref_index <= ref_index + 1;
        end if;
    end if;
end process;

end tb;
