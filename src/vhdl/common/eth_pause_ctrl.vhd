--------------------------------------------------------------------------
-- Copyright 2021-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
    REFCLK_HZ   : positive;         -- Rate of ref_clk (Hz)
    IO_BYTES    : positive := 1);   -- Width of input stream
    port (
    -- Input data stream
    rx_clk      : in  std_logic;
    rx_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    rx_nlast    : in  integer range 0 to IO_BYTES := 0;
    rx_last     : in  std_logic := '0'; -- Choose LAST or NLAST
    rx_write    : in  std_logic;
    rx_rate     : in  port_rate_t;
    rx_reset_p  : in  std_logic;

    -- On command, assert PAUSE flag
    pause_tx    : out std_logic;

    -- Reference clock and reset
    ref_clk     : in  std_logic;
    reset_p     : in  std_logic);
end eth_pause_ctrl;

architecture eth_pause_ctrl of eth_pause_ctrl is

-- Packet-parsing state machine
signal cmd_val  : unsigned(15 downto 0) := (others => '0');
signal cmd_wr_t : std_logic := '0'; -- Toggle in rx_clk domain
signal cmd_wr_i : std_logic;        -- Strobe in ref_clk domain

-- Reference timer
signal timer_en : std_logic := '0';

-- Pause state machine
signal pause_ct : unsigned(15 downto 0) := (others => '0');
signal pause_i  : std_logic := '0';

-- Custom attribute makes it easy to "set_false_path" on cross-clock signals.
-- (Vivado explicitly DOES NOT allow such constraints to be set in the HDL.)
attribute satcat5_cross_clock_src : boolean;
attribute satcat5_cross_clock_src of cmd_val : signal is true;

begin

-- Drive the final pause signal signal.
pause_tx <= pause_i;

-- Packet-parsing state machine.
p_parse : process(rx_clk)
    constant PAUSE_DST : mac_addr_t := x"0180C2000001";
    constant PAUSE_TYP : mac_type_t := x"8808";
    constant PAUSE_OPC : mac_type_t := x"0001";
    constant WCOUNT_MAX : mac_bcount_t := mac_wcount_max(IO_BYTES);
    variable wcount : integer range 0 to WCOUNT_MAX := 0;
    variable is_cmd : std_logic_vector(9 downto 0) := (others => '0');
    variable btmp, bref : byte_t;
begin
    if rising_edge(rx_clk) then
        -- Read headers to see if this is a PAUSE command:
        --   DST    = Bytes 00-05 = 01:80:C2:00:00:01
        --   SRC    = Bytes 06-11 = Don't care
        --   EType  = Bytes 12-13 = 0x8808
        --   Opcode = Bytes 14-15 = 0x0001
        --   Pause  = Bytes 16-17 = Read from packet
        --   Rest of packet       = Don't care (Note: Not checking FCS!)
        if (rx_write = '1') then
            -- DST (Bytes 0-5 = Flags 0-5)
            for n in 0 to 5 loop
                if (strm_byte_present(IO_BYTES, ETH_HDR_DSTMAC+n, wcount)) then
                    bref := strm_byte_value(n, PAUSE_DST);
                    btmp := strm_byte_value(ETH_HDR_DSTMAC+n, rx_data);
                    is_cmd(n+0) := bool2bit(bref = btmp);
                end if;
            end loop;
            -- EType (Bytes 12-13 = Flags 6-7)
            for n in 0 to 1 loop
                if (strm_byte_present(IO_BYTES, ETH_HDR_ETYPE+n, wcount)) then
                    bref := strm_byte_value(n, PAUSE_TYP);
                    btmp := strm_byte_value(ETH_HDR_ETYPE+n, rx_data);
                    is_cmd(n+6) := bool2bit(bref = btmp);
                end if;
            end loop;
            -- Opcode (Bytes 14-15 = Flags 8-9)
            for n in 0 to 1 loop
                if (strm_byte_present(IO_BYTES, ETH_HDR_DATA+n, wcount)) then
                    bref := strm_byte_value(n, PAUSE_OPC);
                    btmp := strm_byte_value(ETH_HDR_DATA+n, rx_data);
                    is_cmd(n+8) := bool2bit(bref = btmp);
                end if;
            end loop;
            -- If this is a PAUSE command...
            if (and_reduce(is_cmd) = '1') then
                -- Latch the duration argument (Bytes 16-17)
                if (strm_byte_present(IO_BYTES, ETH_HDR_DATA+2, wcount)) then
                    btmp := strm_byte_value(ETH_HDR_DATA+2, rx_data);
                    cmd_val(15 downto 8) <= unsigned(btmp);
                end if;
                if (strm_byte_present(IO_BYTES, ETH_HDR_DATA+3, wcount)) then
                    btmp := strm_byte_value(ETH_HDR_DATA+3, rx_data);
                    cmd_val(7 downto 0) <= unsigned(btmp);
                    cmd_wr_t <= not cmd_wr_t;   -- Signal new command
                end if;
            end if;
        end if;

        -- Count words in each packet.
        if (rx_reset_p = '1') then
            wcount := 0;
        elsif (rx_write = '1' and (rx_last = '1' or rx_nlast > 0)) then
            wcount := 0;
        elsif (rx_write = '1' and wcount < WCOUNT_MAX) then
            wcount := wcount + 1;
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
    constant CT_MAX : positive := div_ceil(REFCLK_HZ, CT_DIV);
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
        if (unsigned(rx_rate) < CT_MAX) then
            incr := to_integer(unsigned(rx_rate));
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
