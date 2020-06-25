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
-- Testbench for the Ethernet frame adjustment block.
--
-- This testbench generates a mixture of regular Ethernet traffic and
-- "runt" packets that are too short for IEEE 802.3 compliance.  Each
-- packet is passed through the unit under test, which pads as needed.
-- The padded checksum is verified by the eth_frame_check block, and
-- underlying data is checked against a FIFO-delayed copy of the input.
--
-- The test runs indefinitely, with reasonably complete coverage
-- (600 packets) after about 7.6 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity eth_frame_adjust_tb is
    -- Unit testbench: Two modes, no I/O ports.
    generic (FCS_MODE : boolean := false);
end eth_frame_adjust_tb;

architecture tb of eth_frame_adjust_tb is

-- Strip FCS prior to eth_frame_adjust block?
constant STRIP_FCS_1ST : boolean := FCS_MODE;
constant STRIP_FCS_UUT : boolean := not FCS_MODE;

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Input stream generation.
constant FIRST_PKTLEN : integer := 256;
signal pkt_len      : integer := FIRST_PKTLEN;
signal pkt_etype    : boolean := false;

signal in_port      : port_rx_m2s;
signal in_data      : std_logic_vector(7 downto 0) := (others => '0');
signal in_last      : std_logic := '0';
signal in_valid_raw : std_logic := '0';
signal in_valid_ovr : std_logic := '0';
signal in_last_ovr  : std_logic := '0';
signal in_valid     : std_logic := '0';
signal in_ready     : std_logic := '0';
signal in_rate      : real := 0.0;

-- Reference data FIFO
signal fifo_in      : std_logic_vector(8 downto 0);
signal fifo_out     : std_logic_vector(8 downto 0);
signal fifo_wr      : std_logic;
signal fifo_rd      : std_logic;
signal ref_data     : std_logic_vector(7 downto 0);
signal ref_last     : std_logic;

-- Output stream.
signal out_data     : std_logic_vector(7 downto 0);
signal out_last     : std_logic;
signal out_valid    : std_logic;
signal out_ready    : std_logic := '0';
signal out_write    : std_logic := '0';
signal out_rate     : real := 0.0;

-- Output checking
signal frm_ok       : std_logic;
signal frm_err      : std_logic;
signal frm_idx      : integer := 0;

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Set rate of input and output streams.
p_rate : process
    procedure run(ri, ro : real) is
    begin
        in_rate  <= ri;
        out_rate <= ro;
        wait for 100 us;
    end procedure;
begin
    if (reset_p = '1') then
        wait until falling_edge(reset_p);
    end if;
    run(1.0, 1.0);  -- Continuity check
    run(1.0, 0.5);  -- Continuity check
    run(0.1, 0.9);
    run(0.3, 0.9);
    run(0.5, 0.9);
    run(0.7, 0.9);
    run(0.9, 0.1);
    run(0.9, 0.3);
    run(0.9, 0.5);
    run(0.9, 0.7);
    run(0.9, 0.9);
    wait for 500 us;
end process;

-- Raw stream generation for valid packets.
-- Note: Always use EtherType field, not length.
u_src : entity work.eth_traffic_gen
    generic map(
    AUTO_START  => true)
    port map(
    clk         => clk_100,
    reset_p     => reset_p,
    pkt_len     => pkt_len,
    pkt_etype   => true,
    mac_dst     => x"DD",
    mac_src     => x"CC",
    out_rate    => in_rate,
    out_port    => in_port,
    out_valid   => in_valid_raw,
    out_ready   => in_ready);

-- If specified, strip the FCS from each packet (last four bytes).
-- Randomize source parameters, such as the length of each frame.
in_data  <= in_port.data;
in_valid <= in_valid_raw when (not STRIP_FCS_1ST) else
            in_valid_raw and in_valid_ovr;
in_last  <= in_port.last when (not STRIP_FCS_1ST) else
            in_valid_raw and in_last_ovr;

p_src : process(clk_100)
    -- PRNG state
    variable seed1      : positive := 1234;
    variable seed2      : positive := 5678;
    variable rand       : real := 0.0;
    -- Countdown to end of each packet.
    variable pkt_rem    : integer := FIRST_PKTLEN;
begin
    if rising_edge(clk_100) then
        -- Sanity-check byte-counter synchronization.
        if (in_valid_raw = '1' and in_ready = '1') then
            if (in_port.last = '1') then
                assert (pkt_rem = 1)
                    report "Unexpected LAST" severity error;
            else
                assert (pkt_rem /= 1)
                    report "Countdown desync" severity error;
            end if;
        end if;

        -- Update byte counter.
        if (in_valid_raw = '1' and in_ready = '1') then
            if (in_port.last = '0') then
                -- Normal countdown.
                pkt_rem  := pkt_rem - 1;
            else
                -- End of packet, get ready for next.
                pkt_rem  := pkt_len;
            end if;
        end if;

        -- Randomize packet length BEFORE start of each packet.
        if (pkt_rem = 1 and in_valid_raw = '1' and in_ready = '1') then
            uniform(seed1, seed2, rand);
            pkt_len <= MIN_RUNT_BYTES + integer(floor(rand*real(MAX_FRAME_BYTES - MIN_RUNT_BYTES)));
        end if;

        -- Update the valid-override and last-override strobes.
        in_valid_ovr <= bool2bit(pkt_rem > 4);
        in_last_ovr  <= bool2bit(pkt_rem = 5);

        -- Output flow-control randomization.
        uniform(seed1, seed2, rand);
        out_ready <= bool2bit(rand < out_rate);
    end if;
end process;

-- Small FIFO buffers original packet contents except for FCS.
fifo_in <= in_last_ovr & in_data;
fifo_wr <= in_valid_raw and in_valid_ovr and in_ready;
fifo_rd <= out_write and (out_last or not ref_last);

u_fifo : entity work.smol_fifo
    generic map(
    IO_WIDTH    => 9,
    DEPTH_LOG2  => 6)   -- FIFO depth = 2^N
    port map(
    in_data     => fifo_in,
    in_write    => fifo_wr,
    out_data    => fifo_out,
    out_read    => fifo_rd,
    reset_p     => reset_p,
    clk         => clk_100);

ref_data <= fifo_out(7 downto 0);
ref_last <= fifo_out(8);

-- Unit under test
uut : entity work.eth_frame_adjust
    generic map(
    STRIP_FCS   => STRIP_FCS_UUT)
    port map(
    in_data     => in_data,
    in_last     => in_last,
    in_valid    => in_valid,
    in_ready    => in_ready,
    out_data    => out_data,
    out_last    => out_last,
    out_valid   => out_valid,
    out_ready   => out_ready,
    clk         => clk_100,
    reset_p     => reset_p);

-- Check the FCS of each modified packet.
out_write <= out_valid and out_ready;

u_check_fcs : entity work.eth_frame_check
    generic map(
    ALLOW_RUNT  => false)
    port map(
    in_data     => out_data,
    in_last     => out_last,
    in_write    => out_write,
    out_data    => open,
    out_write   => open,
    out_commit  => frm_ok,
    out_revert  => frm_err,
    clk         => clk_100,
    reset_p     => reset_p);

-- Check the contents of each modified packet.
p_check_dat : process(clk_100)
    variable contig_cnt : integer := 0;
    variable contig_req : std_logic := '0';
    variable ref_end    : std_logic := '0';
begin
    if rising_edge(clk_100) then
        -- Flow control continuity check: Once first byte is valid,
        -- further data must be contiguous until end of packet.
        -- (This is not an AXI requirement, but is needed for port_adjust)
        if (in_rate < 1.0) then
            -- Input not contiguous, disable checking.
            contig_cnt := 0;
        elsif (contig_cnt < 100) then
            -- Hold for a few clock cycles after mode change.
            contig_cnt := contig_cnt + 1;
        elsif (contig_req = '1') then
            -- Output should now be contiguous.
            assert (out_valid = '1')
                report "Contiguous output violation" severity warning;
        end if;
        contig_req := out_valid and not out_last;

        -- Check first part of each frame (up to original FCS).
        if (out_write = '1' and ref_end = '0') then
            assert (out_data = ref_data)
                report "Output data mismatch" severity error;
        end if;

        -- Update packet state.
        if (reset_p = '1') then
            ref_end := '0'; -- Global reset
        elsif (out_write = '1' and out_last = '1') then
            ref_end := '0'; -- End of output, resume checking.
        elsif (out_write = '1' and ref_last = '1') then
            ref_end := '1'; -- End of user data, pause checking.
        end if;

        -- Count the number of valid received packets.
        if (reset_p = '1') then
            frm_idx <= 0;
        elsif (frm_err = '1') then
            report "Unexpected frame error" severity error;
        elsif (frm_ok = '1') then
            frm_idx <= frm_idx + 1;
            if ((frm_idx mod 200) = 199) then
                report "Received packet #" & integer'image(frm_idx+1);
            end if;
        end if;
    end if;
end process;

end tb;
