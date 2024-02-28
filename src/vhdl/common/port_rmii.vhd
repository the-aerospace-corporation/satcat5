--------------------------------------------------------------------------
-- Copyright 2019-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- RGII transceiver port (MAC-to-PHY or MAC-to-MAC)
--
-- This module implements the interface logic for an RMII port, adapting
-- an external RMII interface to the generic internal format used
-- throughout this design.  It supports both 10 Mbps and 100 Mbps modes,
-- and will automatically choose the correct mode based on the preamble
-- of the first received frame.
--
-- The RMII interface uses a 50 MHz reference clock that may be sourced
-- by the MAC or by an external oscillator, depending on the design.
-- If this block is the clock source, connect rmii_clkin internally
-- and connect rmii_clkout to the output pin.  If this block is the
-- clock sink, connect rmii_clkin to the pin and leave rmii_clkout open.
--
-- In clock-out mode, it is sometimes necessary to ensure the clock changes
-- a few nanoseconds before the TXEN and TXD outputs.  To use this mode,
-- set MODE_CLKDDR = false.  To bypass this mode and use strict clock-to-data
-- alignment with changes on the falling-edge, set MODE_CLKDDR = true.
--
-- TODO: Determine why this is necessary.  Most datasheets imply rising edge
-- is the only one that matters, but then the PHY doesn't function correctly
-- when data changes exactly on the falling edge of REFCLK.  Intent of RMII
-- spec is frustratingly ambiguous, especially unclear TXD/TXEN transitions
-- in Figure 4.  Is it possible PHYs are using both edges?
--
-- See also: RMII Specification v1.2 (March 1998)
-- http://ebook.pldworld.com/_eBook/-Telecommunications,Networks-/TCPIP/RMII/rmii_rev12.pdf
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity port_rmii is
    generic (
    MODE_CLKOUT : boolean := true;      -- Enable clock output?
    MODE_CLKDDR : boolean := true;      -- TX* change on falling edge?
    VCONFIG     : vernier_config := VERNIER_DISABLED);
    port (
    -- External RMII interface.
    rmii_txd    : out std_logic_vector(1 downto 0);
    rmii_txen   : out std_logic;        -- Data-valid strobe
    rmii_txer   : out std_logic;        -- Error strobe (optional)
    rmii_rxd    : in  std_logic_vector(1 downto 0);
    rmii_rxen   : in  std_logic;        -- Carrier-sense / data-valid (DV_CRS)
    rmii_rxer   : in  std_logic;        -- Error strobe

    -- Internal or external clock.
    rmii_clkin  : in  std_logic;        -- 50 MHz reference
    rmii_clkout : out std_logic;        -- Optional clock output

    -- Global reference for PTP timestamps, if enabled.
    ref_time    : in  port_timeref := PORT_TIMEREF_NULL;

    -- Generic internal port interface.
    rx_data     : out port_rx_m2s;
    tx_data     : in  port_tx_s2m;
    tx_ctrl     : out port_tx_m2s;

    -- Other control
    force_10m   : in  std_logic := '0'; -- Force 10Mbps mode (for testing)
    lock_refclk : in  std_logic;        -- Separate clock for lock-detect
    reset_p     : in  std_logic);       -- Reset / shutdown
end port_rmii;

architecture port_rmii of port_rmii is

-- Raw I/O registers
subtype io_word is std_logic_vector(1 downto 0);
signal dly_txd      : io_word := (others => '0');
signal dly_txen     : std_logic := '0';
signal io_txd       : io_word := (others => '0');
signal io_txen      : std_logic := '0';
signal io_rxd       : io_word := (others => '0');
signal io_rxen      : std_logic := '0';
signal io_rxer      : std_logic := '0';
signal io_clk       : std_logic;
signal io_reset     : std_logic;
signal io_lock      : std_logic;

-- Precision timestamps.
signal lcl_tstamp       : tstamp_t := TSTAMP_DISABLED;
signal lcl_tvalid       : std_logic := '0';

-- Receive datapath
signal rx_byte      : byte_t := (others => '0');
signal rx_dv        : std_logic := '0';
signal rx_cken      : std_logic := '0';
signal rx_fast      : std_logic := '1';

-- Transmit datapath
signal tx_byte      : byte_t;
signal tx_dv        : std_logic;
signal tx_cken      : std_logic := '0';
signal tx_fast      : std_logic;

-- Other control signals
signal port_status  : port_status_t;
signal port_rate    : port_rate_t;

begin

-- Instantiate the appropriate clock configuration:
gen_clkddr : if MODE_CLKOUT and MODE_CLKDDR generate
    -- Internal reference clock, no buffer needed.
    io_clk <= rmii_clkin;

    -- Mirror TXEN/TXD output structure for tightest possible alignment.
    u_txclk : ddr_output
        port map(
        d_re    => '1',
        d_fe    => '0',
        clk     => rmii_clkin,
        q_pin   => rmii_clkout);
end generate;

gen_clkint : if MODE_CLKOUT and not MODE_CLKDDR generate
    -- Internal reference clock, no buffer needed.
    io_clk <= rmii_clkin;

    -- Unregistered buffer, so CLKOUT leads TXEN/TXD by a few nanoseconds.
    -- TODO: This trick works on Xilinx platforms, need to check others.
    rmii_clkout <= rmii_clkin;
end generate;

gen_clkext : if not MODE_CLKOUT generate
    -- External reference clock, instantiate buffer.
    u_rxclk : clk_input
        generic map(CLKIN_MHZ => 50.0)
        port map(
        reset_p => reset_p,
        clk_pin => rmii_clkin,
        clk_out => io_clk);

    -- Output clock (optional) is the buffered signal.
    rmii_clkout <= io_clk;
end generate;

-- Detect whether the input clock is running.
u_detect : entity work.io_clock_detect
    port map(
    ref_reset_p => reset_p,
    ref_clk     => lock_refclk,
    tst_clk     => io_clk,
    tst_halted  => io_reset,
    tst_running => io_lock);

-- If enabled, generate timestamps with a Vernier synchronizer.
gen_ptp : if VCONFIG.input_hz > 0 generate
    u_tstamp : entity work.ptp_counter_sync
        generic map(
        VCONFIG     => VCONFIG,
        USER_CLK_HZ => 50_000_000)
        port map(
        ref_time    => ref_time,
        user_clk    => IO_CLK,
        user_ctr    => lcl_tstamp,
        user_lock   => lcl_tvalid,
        user_rst_p  => io_reset);
end generate;

-- TXER signal is not part of the RMII spec; we include it here to make
-- the interface completely symmetric for MAC-to-MAC mode.
rmii_txer <= '0';

-- Choose output mode for TXEN and TXD signals:
gen_txfe : if MODE_CLKDDR generate
    -- Update on falling edge of REFCLK (1/2 cycle delay).
    u_txd0 : ddr_output
        port map(
        d_re    => dly_txd(0),
        d_fe    => io_txd(0),
        clk     => io_clk,
        q_pin   => rmii_txd(0));
    u_txd1 : ddr_output
        port map(
        d_re    => dly_txd(1),
        d_fe    => io_txd(1),
        clk     => io_clk,
        q_pin   => rmii_txd(1));
    u_txen : ddr_output
        port map(
        d_re    => dly_txen,
        d_fe    => io_txen,
        clk     => io_clk,
        q_pin   => rmii_txen);
end generate;

gen_txre : if not MODE_CLKDDR generate
    -- Update on or just after rising edge of REFCLK.
    u_txd0 : ddr_output
        port map(
        d_re    => io_txd(0),
        d_fe    => io_txd(0),
        clk     => io_clk,
        q_pin   => rmii_txd(0));
    u_txd1 : ddr_output
        port map(
        d_re    => io_txd(1),
        d_fe    => io_txd(1),
        clk     => io_clk,
        q_pin   => rmii_txd(1));
    u_txen : ddr_output
        port map(
        d_re    => io_txen,
        d_fe    => io_txen,
        clk     => io_clk,
        q_pin   => rmii_txen);
end generate;

-- Input buffers don't use reset, to allow absorption into IOB.
-- Note: In CLKOUT mode, internal clock slightly precedes refclk signal.
--       In CLKIN mode, internal clock slightly lags refclk signal.
u_rxbuf : process(io_clk)
begin
    if rising_edge(io_clk) then
        io_rxd  <= rmii_rxd;
        io_rxen <= rmii_rxen;
        io_rxer <= rmii_rxer;
    end if;
end process;

-- Receive state machine:
-- Convert incoming 2-bit signal to bytes, and auto-detect input rate.
p_rx : process(io_clk)
    variable fast_byte, slow_byte : byte_t := (others => '0');
    variable fast_rdy,  slow_rdy  : std_logic := '0';
    variable frm_dv : std_logic := '0';
    variable div4a  : integer range 0 to 3 := 2;
    variable div4b  : integer range 0 to 3 := 3;
    variable div10  : integer range 0 to 9 := 8;
begin
    if rising_edge(io_clk) then
        -- Choose the active output mode.
        if (frm_dv = '0' or rx_dv = '0') then
            rx_byte <= ETH_AMBLE_SOF;
        elsif (rx_fast = '1') then
            rx_byte <= fast_byte;
        else
            rx_byte <= slow_byte;
        end if;

        -- For each frame, lock onto the input mode that is first to yield
        -- a valid start-of-frame token (0xD5).  Hold until end-of-frame.
        if (io_lock = '0') then
            rx_dv   <= '0'; -- Port reset
            rx_cken <= '0';
            rx_fast <= '1'; -- (Default to 100 Mbps mode)
        elsif (frm_dv = '0') then
            rx_dv   <= '0'; -- Unlock between frames
            rx_cken <= '1'; -- (Flush output pipeline)
        elsif (rx_dv = '1' and rx_fast = '1') then
            rx_dv   <= '1'; -- Fast mode (100 Mbps)
            rx_cken <= fast_rdy;
        elsif (rx_dv = '1' and rx_fast = '0') then
            rx_dv   <= '1'; -- Slow mode (10 Mbps)
            rx_cken <= slow_rdy;
        elsif (fast_rdy = '1' and fast_byte = ETH_AMBLE_SOF) then
            rx_dv   <= '1'; -- Start of fast frame
            rx_cken <= '1';
            rx_fast <= '1';
        elsif (slow_rdy = '1' and slow_byte = ETH_AMBLE_SOF) then
            rx_dv   <= '1'; -- Start of slow frame
            rx_cken <= '1';
            rx_fast <= '0';
        else
            rx_dv   <= '0'; -- Waiting for frame-start
            rx_cken <= '1'; -- (Flush output pipeline)
        end if;

        -- Shift register for 10 Mbps mode samples every 10th clock.
        -- (Each two-bit input slice is repeated ten times in this mode,
        --  so a new data byte is ready on every 40th clock.)
        if (div10 = 0) then
            slow_byte := io_rxd & slow_byte(7 downto 2);    -- LSB-first
        end if;
        slow_rdy  := frm_dv and bool2bit(div10 = 0 and div4b = 0);

        -- Shift register for 100 Mbps mode samples every clock.
        -- (New data byte is ready on every 4th clock.)
        fast_byte := io_rxd & fast_byte(7 downto 2);        -- LSB-first
        fast_rdy  := frm_dv and bool2bit(div4a = 0);

        -- Clock-divider counters are locked to start-of-preamble.
        -- There is some complexity here because DV/CRS may be asserted
        -- before the preamble, and it may toggle near the end of the frame
        -- due to FIFO buffering (refer to Figure 2 and Section 5.2).
        if (io_lock = '0') then
            -- Port reset.
            frm_dv  := '0';
            div10   := 8;
            div4a   := 2;
            div4b   := 3;
        elsif (frm_dv = '0') then
            -- Waiting for start of preamble.
            -- Note: Initial state of each counter is effectively "N-1",
            --       since we we've already gotten the first input slice.
            frm_dv  := io_rxen and bool2bit(io_rxd /= "00");
            div10   := 8;   -- Divide-by-10
            div4a   := 2;   -- Divide-by-4
            div4b   := 3;   -- Second-digit for divide-by-40
        else
            -- Ignore DV changes except on byte boundaries.
            if (div4a = 0 and rx_fast = '1') then
                frm_dv := io_rxen;  -- Fast byte boundary
            elsif (div4b = 0 and div10 = 0) then
                frm_dv := io_rxen;  -- Slow byte boundary
            end if;
            -- Modulo-4 countdown for fast mode.
            if (div4a /= 0) then
                div4a := div4a - 1;
            else
                div4a := 3;
            end if;
            -- Modulo-40 countdown for slow mode.
            if (div10 /= 0) then
                div10 := div10 - 1;
            elsif (div4b /= 0) then
                div10 := 9;
                div4b := div4b - 1;
            else
                div10 := 9;
                div4b := 3;
            end if;
        end if;
    end if;
end process;

-- Upstream status reporting.
port_rate <= get_rate_word(100) when (rx_fast = '1')
        else get_rate_word(10);

port_status <= (
    0 => reset_p,
    1 => io_lock,
    2 => rx_fast,
    3 => lcl_tvalid,
    others => '0');

-- Preamble removal and port interface logic.
u_amble_rx : entity work.eth_preamble_rx
    port map(
    raw_clk     => io_clk,
    raw_lock    => io_lock,
    raw_cken    => rx_cken,
    raw_data    => rx_byte,     -- Recovered byte stream
    raw_dv      => rx_dv,
    raw_err     => io_rxer,
    rate_word   => port_rate,
    rx_tstamp   => lcl_tstamp,
    status      => port_status,
    rx_data     => rx_data);    -- Rx data to switch

-- Insert preambles and inter-packet gap.
u_amble_tx : entity work.eth_preamble_tx
    port map(
    out_data    => tx_byte,     -- Psuedo-GMII signals
    out_dv      => tx_dv,
    out_err     => open,
    tx_clk      => io_clk,
    tx_pwren    => io_lock,
    tx_cken     => tx_cken,
    tx_tstamp   => lcl_tstamp,
    tx_data     => tx_data,     -- Tx data from switch
    tx_ctrl     => tx_ctrl);    -- (Associated control)

-- Override for unit tests: Force transmission in 10 Mbps mode.
tx_fast <= rx_fast and not force_10m;

-- Convert transmit byte-stream to two-bit signal.
-- (With repeats as needed for 10 Mbps mode.)
p_tx : process(io_clk)
    variable bcount : integer range 0 to 3 := 0;
    variable div10  : integer range 0 to 9 := 0;
begin
    if rising_edge(io_clk) then
        -- Single-cycle delayed copy of each signal.
        dly_txd  <= io_txd;
        dly_txen <= io_txen;

        -- Latch each two-bit output, LSB-first (Figure 5).
        io_txd  <= tx_byte(2*bcount+1 downto 2*bcount);
        io_txen <= tx_dv;

        -- Upstream clock-enable leads by one clock.
        -- (i.e., To be concurrent with the final usage of each byte.)
        if (io_lock = '0') then
            tx_cken <= '0';
        elsif (tx_fast = '1') then
            tx_cken <= bool2bit(bcount = 2);
        else
            tx_cken <= bool2bit(bcount = 3 and div10 = 1);
        end if;

        -- Update sub-byte counter.
        if (io_lock = '0') then
            bcount := 0;            -- Port reset
        elsif (div10 = 0 and bcount = 3) then
            bcount := 0;            -- Byte rollover
        elsif (div10 = 0) then
            bcount := bcount + 1;   -- Continue current byte
        end if;

        -- Optional divide-by-10 counter for 10 Mbps mode.
        if (io_lock = '0') then
            div10 := 0;             -- Port reset
        elsif (tx_fast = '1') then
            div10 := 0;             -- 100 Mbps mode
        elsif (div10 = 0) then
            div10 := 9;             -- 10 Mbps rollover
        else
            div10 := div10 - 1;     -- 10 Mbps countdown
        end if;
    end if;
end process;

end port_rmii;
