--------------------------------------------------------------------------
-- Copyright 2019-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- RGMII transceiver port (MAC-to-PHY or MAC-to-MAC)
--
-- This module implements the interface logic for an RGMII port,
-- adapting an external RGMII interface to the generic internal
-- format used throughout this design.
--
-- The reset signal for this block is also used to shut down the
-- clock output, to save power if the port is disabled.
--
-- The transmit path has an option to delay the output clock. Such
-- a delay is required by the RGMII standard and should be applied
-- exactly once (either using a delayed output, a long PCB trace, or
-- a phase-shift at the receiver). If no delay is desired, tie
-- clk_125 and clk_txc to the same source.  Otherwise, tie clk_txc
-- to 90-degree shifted clock (2.0 nsec delay).
--
-- The receive path has a similar option, to delay the incoming clock by
-- approximately 2 nsec.  As above, this delay is part of the RGMII standard
-- and must be applied exactly once.  To use, set RXCLK_DELAY = 2.0.
--
-- See also: Reduced Gigabit Media Independent Interface v 2.0 (April 2002)
-- https://web.archive.org/web/20160303171328/http://www.hp.com/rnd/pdfs/RGMIIv2_0_final_hp.pdf
--
-- The RGMII_RXC pin should be attached to a clock-capable input pin.
-- Several generics configure the associated input buffer:
--  * RXCLK_ALIGN: Enable deskew by resynthesizing clock (default false).
--  * RXCLK_GLOBL: If true, use a global clock buffer (default true).
--  * RXCLK_LOCAL: If true, use a local clock buffer (default false).
-- If any of the above is "true", this block instantiates the vendor-agnostic
-- "clk_input" wrapper from "common_primitives.vhd".  Use of local clock
-- buffers may save resources, but typically requires additional location
-- constraints that may complicate the overall design.  If all of the above
-- are "false", then users should provide their own clock buffer(s).
--
-- Note: For cross-platform support, the block uses vendor-agnostic
--       I/O wrappers from "common_primitives.vhd".
-- Note: If the "shutdown" signal is used, hold reset_p for at least
--       1 msec after shutdown is released. (RXCLK_ALIGN mode only.)
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity port_rgmii is
    generic (
    RXCLK_ALIGN : boolean := false;     -- Enable precision clock-buffer deskew
    RXCLK_LOCAL : boolean := false;     -- Enable input clock buffer (local)
    RXCLK_GLOBL : boolean := true;      -- Enable input clock buffer (global)
    RXCLK_DELAY : real := 0.0;          -- Input clock delay, in nanoseconds (typ. 0.0 or 2.0)
    RXDAT_DELAY : real := 0.0;          -- Input data/control delay, in nanoseconds
    VCONFIG     : vernier_config := VERNIER_DISABLED);
    port (
    -- External RGMII interface.
    rgmii_txc   : out std_logic;
    rgmii_txd   : out std_logic_vector(3 downto 0);
    rgmii_txctl : out std_logic;
    rgmii_rxc   : in  std_logic;
    rgmii_rxd   : in  std_logic_vector(3 downto 0);
    rgmii_rxctl : in  std_logic;

    -- Generic internal port interface.
    rx_data     : out port_rx_m2s;
    tx_data     : in  port_tx_s2m;
    tx_ctrl     : out port_tx_m2s;

    -- Test controls (not required for general use)
    force_10m   : in  std_logic := '0';
    force_100m  : in  std_logic := '0';

    -- Global reference for PTP timestamps, if enabled.
    ref_time    : in  port_timeref := PORT_TIMEREF_NULL;

    -- Reference clock and reset.
    clk_125     : in  std_logic;        -- Main reference clock
    clk_txc     : in  std_logic;        -- Same clock or delayed clock
    reset_p     : in  std_logic;        -- Reset / port shutdown
    shdn_p      : in  std_logic := '0'); -- Long-term shutdown (optional)
end port_rgmii;

architecture port_rgmii of port_rgmii is

subtype nybble_t is std_logic_vector(3 downto 0);

-- On startup, default is 1000 Mbps full-duplex (Table 4)
constant META_1000M : nybble_t := "1100";
constant META_100M  : nybble_t := "1010";
constant META_10M   : nybble_t := "1000";

-- All RX signals are in the "rx_clk" domain.
signal rx_clk       : std_logic;                    -- Buffered Rx-clock
signal rx_lock      : std_logic := '0';             -- Rx clock detected?
signal rx_reset     : std_logic;                    -- Inverse of rx_lock
signal rx_raw_data  : byte_t := (others => '0');    -- DDR input register
signal rx_raw_dv    : std_logic := '0';             -- DDR input register
signal rx_raw_err   : std_logic := '0';             -- DDR input register
signal rx_out_data  : byte_t := (others => '0');    -- De-duplicated data
signal rx_out_dv    : std_logic := '0';             -- De-duplicated data
signal rx_out_err   : std_logic := '0';             -- De-duplicated data
signal rx_out_cken  : std_logic := '1';             -- Preamble clock-enable
signal rx_meta      : nybble_t := META_1000M;       -- Received link config
signal rx_tstamp    : tstamp_t := TSTAMP_DISABLED;  -- Receive clock timestamps
signal rx_tvalid    : std_logic := '0';             -- Timestamp valid?

-- All TX signals are in the "tx_clk" domain.
signal tx_clk       : std_logic;                    -- Main Tx-clock
signal tx_reset     : std_logic;                    -- Reset sync'd to tx_clk
signal tx_pwren     : std_logic := '0';             -- Port enabled?
signal tx_lock      : std_logic := '0';             -- Rx clock detected?
signal tx_meta      : nybble_t;                     -- Outgoing link config
signal tx_pre_data  : byte_t := (others => '0');    -- Byte-stream w/ amble
signal tx_pre_dv    : std_logic := '0';             -- Byte-stream w/ amble
signal tx_pre_err   : std_logic := '0';             -- Byte-stream w/ amble
signal tx_pre_cken  : std_logic := '1';             -- Byte-stream clock-enable
signal tx_out_data  : byte_t := (others => '0');    -- DDR output data
signal tx_out_dv    : std_logic := '0';             -- DDR output data
signal tx_out_err   : std_logic := '0';             -- DDR output data
signal tx_out_clkr  : std_logic := '0';             -- DDR output clock
signal tx_out_clkf  : std_logic := '0';             -- DDR output clock
signal tx_rate10    : std_logic := '0';             -- Output rate flag
signal tx_rate100   : std_logic := '0';             -- Output rate flag
signal tx_tstamp    : tstamp_t := TSTAMP_DISABLED;  -- Receive clock timestamps
signal tx_tvalid    : std_logic := '0';             -- Timestamp valid?

-- Upstream status reporting is asynchronous.
signal rate_word    : port_rate_t;                  -- Link rate (10/100/1000)
signal status_word  : port_status_t;                -- Link status (see below)

begin

-- Most Tx logic uses the TXC clock, which is optionally delayed.
-- This ensures that DDR outputs using the early clock are aligned
-- correctly, in both the same-clock and delayed-clock configuration.
tx_clk <= clk_txc;

-- Synchronize the external reset signal.
u_rsync : sync_reset
    port map(
    in_reset_p  => reset_p,
    out_reset_p => tx_reset,
    out_clk     => tx_clk);

tx_pwren <= not tx_reset;

-- Instantiate platform-specific I/O structures:
-- Note: For symmetry with clock input path, set DELAY_NSEC = 0.0 on all
--       inputs, rather than bypassing the delay-control structure.
u_txc : ddr_output
    port map(
    d_re    => tx_out_clkr,     -- Rising-edge output ('1' in Gbps mode)
    d_fe    => tx_out_clkf,     -- Falling-edge output ('0' in Gbps mode)
    clk     => tx_clk,          -- Use the delayed Tx clock
    q_pin   => rgmii_txc);      -- Output pin
u_txctl : ddr_output
    port map(
    d_re    => tx_out_dv,       -- DDR-shared DV/ERR flags
    d_fe    => tx_out_err,      -- (ERR is XOR-encoded)
    clk     => clk_125,         -- Data and DV/ERR use early clock
    q_pin   => rgmii_txctl);    -- Output pin

u_rxctl : ddr_input
    generic map(DELAY_NSEC => RXDAT_DELAY)
    port map(
    d_pin   => rgmii_rxctl,
    clk     => rx_clk,
    q_re    => rx_raw_dv,
    q_fe    => rx_raw_err);

gen_clk_pass : if not (RXCLK_ALIGN or RXCLK_LOCAL or RXCLK_GLOBL) generate
    -- Clock passthrough: User-provided external buffer or simulation.
    rx_clk <= rgmii_rxc;
end generate;

gen_clk_buff : if (RXCLK_ALIGN or RXCLK_LOCAL or RXCLK_GLOBL) generate
    -- Clock buffer: Instantiate explicit clock buffer inside this block.
    u_rxc : clk_input
        generic map(
        CLKIN_MHZ   => 125.0,
        GLOBAL_BUFF => RXCLK_GLOBL,
        DESKEW_EN   => RXCLK_ALIGN,
        DELAY_NSEC  => RXCLK_DELAY)
        port map(
        reset_p     => reset_p,
        shdn_p      => shdn_p,
        clk_pin     => rgmii_rxc,
        clk_out     => rx_clk);
end generate;

gen_data_pins : for n in 0 to 3 generate
    u_txd : ddr_output
        port map(
        d_re    => tx_out_data(n),      -- LSBs on rising edge
        d_fe    => tx_out_data(n+4),    -- MSBs on falling edge
        clk     => clk_125,             -- Data and DV/ERR use early clock
        q_pin   => rgmii_txd(n));       -- Output pin
    u_rxd : ddr_input
        generic map(DELAY_NSEC => RXDAT_DELAY)
        port map(
        d_pin   => rgmii_rxd(n),        -- Input pin
        clk     => rx_clk,              -- Buffered receive clock
        q_re    => rx_raw_data(n),      -- LSBs on rising edge
        q_fe    => rx_raw_data(n+4));   -- MSBs on falling edge
end generate;

-- Clock-detection state machine:
-- Reference clock is 125 MHz; rx_clk may be 125, 25, or 2.5 MHz.
u_detect : entity work.io_clock_detect
    generic map (CLK_RATIO => 50)
    port map(
    ref_reset_p => tx_reset,
    ref_clk     => tx_clk,
    ref_running => tx_lock,
    tst_clk     => rx_clk,
    tst_halted  => rx_reset,
    tst_running => rx_lock);

-- If enabled, generate timestamps with a Vernier synchronizer.
gen_tstamp : if VCONFIG.input_hz > 0 generate
    u_tstamp_rx : entity work.ptp_counter_sync
        generic map(
        VCONFIG     => VCONFIG,
        USER_CLK_HZ => 125_000_000)
        port map(
        ref_time    => ref_time,
        user_clk    => rx_clk,
        user_ctr    => rx_tstamp,
        user_lock   => rx_tvalid,
        user_rst_p  => rx_reset);

    u_tstamp_tx : entity work.ptp_counter_sync
        generic map(
        VCONFIG     => VCONFIG,
        USER_CLK_HZ => 125_000_000)
        port map(
        ref_time    => ref_time,
        user_clk    => tx_clk,
        user_ctr    => tx_tstamp,
        user_lock   => tx_tvalid,
        user_rst_p  => tx_reset);
end generate;

-- Rate detection and incoming data conversion:
p_rx : process(rx_clk)
begin
    if rising_edge(rx_clk) then
        -- Latch metadata sent during idle periods (See RGMII spec, Table 4).
        if (rx_lock = '0') then
            rx_meta <= META_1000M;  -- Default to 1000 Mbps
        elsif (force_100m = '1') then
            rx_meta <= META_100M;   -- Override for testing
        elsif (force_10m = '1') then
            rx_meta <= META_10M;    -- Override for testing
        elsif (rx_raw_dv = '0' and rx_raw_err = '0') then
            rx_meta <= rx_raw_data(3 downto 0);
        end if;

        -- De-duplicate incoming data (Section 5.0).
        --  * 1000 Mbps mode is DDR (unique data on rising + falling edge)
        --  * 10/100 Mbps modes are SDR (data duplicated on falling edge)
        --    Use a shift-register to reconstruct the complete byte.
        if (rx_raw_dv = '0') then           -- Between packets
            rx_out_data <= (others => '0');
            rx_out_cken <= '1';             -- Flush preamble pipeline
        elsif (rx_meta(2) = '1') then       -- 1000 Mbps mode (DDR)
            rx_out_data <= rx_raw_data;     -- No conversion needed
            rx_out_cken <= '1';             -- New byte every clock
        else                                -- 10/100 Mbps mode (SDR)
            rx_out_data <= rx_raw_data(3 downto 0) & rx_out_data(7 downto 4);
            rx_out_cken <= not rx_out_cken; -- New byte every 2nd cycle
        end if;
        rx_out_dv   <= rx_raw_dv;           -- Matched delay for DV/ERR
        rx_out_err  <= rx_raw_err;
    end if;
end process;

-- Upstream status reporting.
rate_word <= get_rate_word(10)   when (tx_rate10 = '1')
        else get_rate_word(100)  when (tx_rate100 = '1')
        else get_rate_word(1000);

status_word <= (
    0 => tx_reset,
    1 => rx_lock,
    2 => rx_tvalid and tx_tvalid,
    4 => rx_meta(0),
    5 => rx_meta(1),
    6 => rx_meta(2),
    7 => rx_meta(3),
    others => '0');

-- Receive state machine, including preamble removal.
u_amble_rx : entity work.eth_preamble_rx
    generic map(
    DV_XOR_ERR  => true)
    port map(
    raw_clk     => rx_clk,
    raw_lock    => rx_lock,
    raw_data    => rx_out_data, -- Recovered byte stream
    raw_dv      => rx_out_dv,
    raw_err     => rx_out_err,
    raw_cken    => rx_out_cken,
    rate_word   => rate_word,
    rx_tstamp   => rx_tstamp,
    status      => status_word,
    rx_data     => rx_data);    -- Rx data to switch

-- Buffers and clock-transition for outgoing metadata.
tx_meta(0) <= tx_lock;          -- Link OK?

u_hs_meta : sync_buffer_slv
    generic map(IO_WIDTH => 3)
    port map(
    in_flag     => rx_meta(3 downto 1),
    out_flag    => tx_meta(3 downto 1),
    out_clk     => tx_clk);

-- Transmit state machine, including insertion of preamble,
-- start-of-frame delimiter, and inter-packet gap.
u_amble_tx : entity work.eth_preamble_tx
    generic map(DV_XOR_ERR => true)
    port map(
    out_data    => tx_pre_data, -- Psuedo-GMII signals
    out_dv      => tx_pre_dv,   -- Note: ERR is xor-encoded
    out_err     => tx_pre_err,
    tx_clk      => tx_clk,
    tx_pwren    => tx_pwren,    -- Port enabled?
    tx_cken     => tx_pre_cken, -- Clock enable
    tx_pkten    => tx_lock,     -- Link up, ready to send?
    tx_tstamp   => tx_tstamp,
    tx_idle     => tx_meta,     -- Echo Rx metadata
    tx_data     => tx_data,     -- Tx data from switch
    tx_ctrl     => tx_ctrl);    -- (Associated control)

-- Rate adaptation for outgoing clock and data.
p_tx : process(tx_clk)
    variable clkdiv : integer range 0 to 99 := 0;
begin
    if rising_edge(tx_clk) then
        -- Update rate-control settings when it is safe to do so.
        -- (Prevent clock and data glitches during rate transitions.)
        if (tx_reset = '1') then
            tx_rate10   <= '0';
            tx_rate100  <= '0';
        elsif (tx_pre_cken = '1' and tx_pre_dv = '0') then
            tx_rate10   <= force_10m  or bool2bit(tx_meta(2) = '0' and tx_meta(1) = '0');
            tx_rate100  <= force_100m or bool2bit(tx_meta(2) = '0' and tx_meta(1) = '1');
        end if;

        -- Clock and data stretching:
        if (tx_reset = '1') then
            -- Port shutdown, no clock.
            tx_pre_cken <= '0';
            tx_out_data <= (others => '0'); -- No data
            tx_out_clkr <= '0';             -- No clock
            tx_out_clkf <= '0';
            clkdiv      := 0;
        elsif (tx_rate10 = '1') then
            -- 10 Mbps mode: Hold each nybble for 50 internal clock cycles.
            if (clkdiv < 50) then
                tx_out_data <= tx_pre_data(3 downto 0) & tx_pre_data(3 downto 0);
            else
                tx_out_data <= tx_pre_data(7 downto 4) & tx_pre_data(7 downto 4);
            end if;
            -- Divide clock by 50x (SDR = 2 cycles per byte)
            tx_out_clkr <= bool2bit(clkdiv mod 50 < 25);
            tx_out_clkf <= bool2bit(clkdiv mod 50 < 25);
            -- Assert clock-enable one cycle before wraparound.
            tx_pre_cken <= bool2bit(clkdiv = 98);
            clkdiv      := (clkdiv + 1) mod 100;
        elsif (tx_rate100 = '1') then
            -- 100 Mbps mode: Hold each nybble for 5 internal clock cycles.
            if (clkdiv < 5) then
                tx_out_data <= tx_pre_data(3 downto 0) & tx_pre_data(3 downto 0);
            else
                tx_out_data <= tx_pre_data(7 downto 4) & tx_pre_data(7 downto 4);
            end if;
            -- Divide clock by 5x (SDR = 2 cycles per byte)
            tx_out_clkr <= bool2bit(clkdiv mod 5 < 3);
            tx_out_clkf <= bool2bit(clkdiv mod 5 < 2);
            -- Assert clock-enable one cycle before wraparound.
            tx_pre_cken <= bool2bit(clkdiv = 8);
            clkdiv      := (clkdiv + 1) mod 10;
        else
            -- 1000 Mbps mode: DDR @ 125 MHz clock (full rate)
            tx_pre_cken <= '1';
            tx_out_data <= tx_pre_data; -- Direct forwarding
            tx_out_clkr <= '1';         -- 125 MHz clock
            tx_out_clkf <= '0';
            clkdiv      := 0;
        end if;

        -- Matched delay for DV/ERR flags.
        tx_out_dv   <= tx_pre_dv;
        tx_out_err  <= tx_pre_err;
    end if;
end process;

end port_rgmii;
