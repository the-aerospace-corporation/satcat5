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
-- Ethernet PAUSE frame detection and state-machine
--
-- Given an Ethernet byte stream, analyze incoming frames to detect
-- PAUSE commands as defined in IEEE 802.3 Annex 31B.
--
-- If such frames are detected, assert the PAUSE flag for the designated
-- period of time.  Per specification, the "quanta" is linked to the link
-- rate, so we require clock-rate and baud-rate metadata from the Rx-port.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.sync_toggle2pulse;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity eth_pause_ctrl is
    generic (
    REFCLK_HZ   : positive);    -- Rate of ref_clk (Hz)
    port (
    -- Input data stream
    port_rx     : in  port_rx_m2s;

    -- On command, assert PAUSE flag
    pause_tx    : out std_logic;

    -- Reference clock and reset
    ref_clk     : in  std_logic;
    reset_p     : in  std_logic);
end eth_pause_ctrl;

architecture eth_pause_ctrl of eth_pause_ctrl is

-- Port clock.
signal rx_clk   : std_logic;

-- Packet-parsing state machine
signal cmd_val  : unsigned(15 downto 0) := (others => '0');
signal cmd_wr_t : std_logic := '0'; -- Toggle in rx_clk domain
signal cmd_wr_i : std_logic;        -- Strobe in ref_clk domain

-- Reference timer
signal timer_en : std_logic := '0';

-- Pause state machine
signal pause_ct : unsigned(15 downto 0) := (others => '0');
signal pause_i  : std_logic := '0';

begin

-- Drive the final pause signal signal.
pause_tx <= pause_i;

-- Force clock assignment, as a workaround for bugs in Vivado XSIM.
-- (Further discussion in "switch_core.vhd".)
rx_clk <= to_01_std(port_rx.clk);

-- Packet-parsing state machine.
p_parse : process(rx_clk)
    variable is_cmd : std_logic := '0';
    variable bcount : integer range 0 to 18 := 0;
begin
    if rising_edge(rx_clk) then
        -- Read headers to see if this is a PAUSE command:
        --   DST    = Bytes 00-05 = 01:80:C2:00:00:01
        --   SRC    = Bytes 06-11 = Don't care
        --   EType  = Bytes 12-13 = 0x8808
        --   Opcode = Bytes 14-15 = 0x0001
        --   Pause  = Bytes 16-17 = Read from packet
        --   Rest of packet       = Don't care (Note: Not checking FCS!)
        if (port_rx.write = '1') then
            if (bcount = 0) then
                is_cmd := bool2bit(port_rx.data = x"01");
            elsif (bcount = 1) then
                is_cmd := is_cmd and bool2bit(port_rx.data = x"80");
            elsif (bcount = 2) then
                is_cmd := is_cmd and bool2bit(port_rx.data = x"C2");
            elsif (bcount = 3) then
                is_cmd := is_cmd and bool2bit(port_rx.data = x"00");
            elsif (bcount = 4) then
                is_cmd := is_cmd and bool2bit(port_rx.data = x"00");
            elsif (bcount = 5) then
                is_cmd := is_cmd and bool2bit(port_rx.data = x"01");
            elsif (bcount = 12) then
                is_cmd := is_cmd and bool2bit(port_rx.data = x"88");
            elsif (bcount = 13) then
                is_cmd := is_cmd and bool2bit(port_rx.data = x"08");
            elsif (bcount = 14) then
                is_cmd := is_cmd and bool2bit(port_rx.data = x"00");
            elsif (bcount = 15) then
                is_cmd := is_cmd and bool2bit(port_rx.data = x"01");
            elsif (bcount = 16) then
                cmd_val(15 downto 8) <= unsigned(port_rx.data);
            elsif (bcount = 17) then
                cmd_val( 7 downto 0) <= unsigned(port_rx.data);
                -- If command received, generate toggle event.
                cmd_wr_t <= cmd_wr_t xor is_cmd;
            end if;
        end if;

        -- Count bytes in each packet.
        if (port_rx.reset_p = '1') then
            bcount := 0;
        elsif (port_rx.write = '1') then
            if (port_rx.last = '1') then
                bcount := 0;
            elsif (bcount < 18) then
                bcount := bcount + 1;
            end if;
        end if;
    end if;
end process;

u_sync : sync_toggle2pulse
    port map(
    in_toggle   => cmd_wr_t,
    out_strobe  => cmd_wr_i,
    out_clk     => ref_clk);

-- Reference timer generates an event for each "quanta" = 512 bit intervals.
-- (i.e., Once every 512 usec at 1 Mbps, or once every 512 nsec at 1 Gbps.)
-- Do this in the REF_CLK domain, since we know how it translates to real-time.
p_timer : process(ref_clk)
    constant CT_DIV : positive := 1_000_000 / 512;
    constant CT_MAX : positive := (REFCLK_HZ + CT_DIV - 1) / CT_DIV;
    variable accum  : integer range 0 to CT_MAX-1 := 0;
    variable incr   : integer range 0 to CT_MAX := 0;
begin
    if rising_edge(ref_clk) then
        -- Generate an event each time the accumulator overflows.
        timer_en <= bool2bit(accum + incr >= CT_MAX);

        -- Sync timer updates to incoming commands.
        -- Otherwise, increment with wraparound.
        if (reset_p = '1' or cmd_wr_i = '1') then
            accum := 0;
        elsif (accum + incr >= CT_MAX) then
            accum := accum + incr - CT_MAX;
        else
            accum := accum + incr;
        end if;

        -- Increment amount is equal to the port's rate parameter.
        -- (Quasi-static, no need to worry about clock-domain crossing.)
        if (unsigned(port_rx.rate) < CT_MAX) then
            incr := to_integer(unsigned(port_rx.rate));
        else
            incr := CT_MAX;
        end if;
    end if;
end process;

-- Pause state machine
p_pause : process(ref_clk)
begin
    if rising_edge(ref_clk) then
        -- Pause whenever the countdown is nonzero.
        pause_i <= bool2bit(pause_ct > 0);

        -- Update the countdown.
        if (reset_p = '1') then
            pause_ct <= (others => '0');
        elsif (cmd_wr_i = '1') then
            pause_ct <= cmd_val;
        elsif (timer_en = '1' and pause_ct > 0) then
            pause_ct <= pause_ct - 1;
        end if;
    end if;
end process;

end eth_pause_ctrl;
