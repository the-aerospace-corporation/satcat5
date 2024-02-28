--------------------------------------------------------------------------
-- Copyright 2022-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Port-interface adapter for generic AXI-streams
--
-- This block connects a pair of AXI-streams to the Tx and Rx interfaces
-- of a general-purpose SatCat5 Ethernet port.  If requested, it may also
-- instantiate a buffer to aide in timing/routing.
--
-- If PTP is enabled, this block requires a Vernier time reference and
-- the nominal frequency of each clock.
--
-- If the Rx stream may contain errors but doesn't include the FCS, connect
-- the optional "rx_error" strobe.  Asserting this strobe at any point during
-- the frame will ensure that the appended FCS is invalid, preventing error
-- propagation through downstream systems.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity port_stream is
    generic (
    DELAY_REG   : boolean := true;      -- Include a buffer register?
    RATE_MBPS   : integer := 1000;      -- Estimated/typical data rate
    RX_MIN_FRM  : natural := 64;        -- Pad Rx frames to min size?
    RX_HAS_FCS  : boolean := false;     -- Does Rx data include FCS?
    TX_HAS_FCS  : boolean := false;     -- Retain FCS for each Tx frame?
    RX_CLK_HZ   : natural := 0;         -- Rx clock rate for PTP timestamps
    TX_CLK_HZ   : natural := 0;         -- Tx clock rate for PTP timestamps
    VCONFIG     : vernier_config := VERNIER_DISABLED);
    port (
    -- AXI-stream interface (Rx).
    rx_clk      : in  std_logic;
    rx_data     : in  byte_t;
    rx_error    : in  std_logic := '0';
    rx_last     : in  std_logic;
    rx_valid    : in  std_logic;
    rx_ready    : out std_logic;
    rx_reset    : in  std_logic;

    -- AXI-stream interface (Tx).
    tx_clk      : in  std_logic;
    tx_data     : out byte_t;
    tx_last     : out std_logic;
    tx_valid    : out std_logic;
    tx_ready    : in  std_logic;
    tx_reset    : in  std_logic;

    -- Global reference for PTP timestamps, if enabled.
    -- (Required if PTP is enabled and Rx/Tx use different clocks.)
    ref_time    : in  port_timeref := PORT_TIMEREF_NULL;

    -- Network port
    prx_data    : out port_rx_m2s;
    ptx_data    : in  port_tx_s2m;
    ptx_ctrl    : out port_tx_m2s);
end port_stream;

architecture port_stream of port_stream is

-- Timestamps in each clock domain.
signal rx_tstamp    : tstamp_t := TSTAMP_DISABLED;
signal rx_tvalid    : std_logic := '0';
signal tx_tstamp    : tstamp_t := TSTAMP_DISABLED;
signal tx_tvalid    : std_logic := '0';

-- Rx stream: Adjust data coming from user
signal rxa_data     : byte_t := (others => '0');
signal rxa_last     : std_logic := '0';
signal rxa_write    : std_logic := '0';

-- Rx stream: Output to switch port
signal rxp_data     : byte_t := (others => '0');
signal rxp_last     : std_logic := '0';
signal rxp_write    : std_logic := '0';

-- Tx stream: Input from switch port
signal txp_data     : byte_t;
signal txp_last     : std_logic;
signal txp_valid    : std_logic;
signal txp_ready    : std_logic;

-- Tx stream: Remove FCS if requested
signal txa_data     : byte_t;
signal txa_last     : std_logic;
signal txa_valid    : std_logic;
signal txa_ready    : std_logic;
signal txa_empty    : std_logic;

begin

------------------------- Timestamp logic ---------------------------

gen_ptp_rx : if RX_CLK_HZ > 0 and VCONFIG.input_hz > 0 generate
    u_tstamp : entity work.ptp_counter_sync
        generic map(
        VCONFIG     => VCONFIG,
        USER_CLK_HZ => RX_CLK_HZ)
        port map(
        ref_time    => ref_time,
        user_clk    => rx_clk,
        user_ctr    => rx_tstamp,
        user_lock   => rx_tvalid,
        user_rst_p  => rx_reset);
end generate;

gen_ptp_tx : if TX_CLK_HZ > 0 and VCONFIG.input_hz > 0 generate
    u_tstamp : entity work.ptp_counter_sync
        generic map(
        VCONFIG     => VCONFIG,
        USER_CLK_HZ => TX_CLK_HZ)
        port map(
        ref_time    => ref_time,
        user_clk    => tx_clk,
        user_ctr    => tx_tstamp,
        user_lock   => tx_tvalid,
        user_rst_p  => tx_reset);
end generate;

-------------------- Rx stream (user to switch) ---------------------

-- Adjust raw data coming from user.
gen_rx_adj1 : if RX_MIN_FRM > 0 or not RX_HAS_FCS generate
    -- Insert zero-padding, then add or recalculate FCS.
    -- (Output to switch must always have a valid FCS.)
    u_rx_adj : entity work.eth_frame_adjust
        generic map(
        MIN_FRAME   => RX_MIN_FRM,
        APPEND_FCS  => true,
        STRIP_FCS   => RX_HAS_FCS)
        port map(
        in_data     => rx_data,
        in_error    => rx_error,
        in_last     => rx_last,
        in_valid    => rx_valid,
        in_ready    => rx_ready,
        out_data    => rxa_data,
        out_last    => rxa_last,
        out_valid   => rxa_write,
        out_ready   => '1',
        clk         => rx_clk,
        reset_p     => rx_reset);
end generate;

gen_rx_adj0 : if RX_MIN_FRM = 0 and RX_HAS_FCS generate
    -- Direct passthrough.
    rxa_data    <= rx_data;
    rxa_last    <= rx_last;
    rxa_write   <= rx_valid;
    rx_ready    <= '1';
end generate;

-- Optional delay register.
gen_rx_dly1 : if DELAY_REG generate
    -- Simple delay register.
    p_rxdly : process(rx_clk)
    begin
        if rising_edge(rx_clk) then
            rxp_data    <= rxa_data;
            rxp_last    <= rxa_last;
            rxp_write   <= rxa_write and not rx_reset;
        end if;
    end process;
end generate;

gen_rx_dly0 : if not DELAY_REG generate
    -- Direct passthrough.
    rxp_data    <= rxa_data;
    rxp_last    <= rxa_last;
    rxp_write   <= rxa_write;
end generate;

-- Connect all signals to switch port.
prx_data.clk        <= rx_clk;
prx_data.data       <= rxp_data;
prx_data.last       <= rxp_last;
prx_data.write      <= rxp_write;
prx_data.rxerr      <= '0';
prx_data.rate       <= get_rate_word(RATE_MBPS);
prx_data.status     <= (0 => rx_reset, 1 => tx_reset, 2 => rx_tvalid, 3 => tx_tvalid, others => '0');
prx_data.tsof       <= rx_tstamp;
prx_data.reset_p    <= rx_reset;

-------------------- Tx stream (switch to user) ---------------------

-- Connect all signals from switch port.
ptx_ctrl.clk        <= tx_clk;
ptx_ctrl.pstart     <= txa_empty;
ptx_ctrl.tnow       <= tx_tstamp;
ptx_ctrl.txerr      <= '0';
ptx_ctrl.reset_p    <= tx_reset;
txp_data            <= ptx_data.data;
txp_last            <= ptx_data.last;
txp_valid           <= ptx_data.valid;
ptx_ctrl.ready      <= txp_ready;

-- Adjust framed data from the switch.
gen_tx_fcs1 : if not TX_HAS_FCS generate
    -- Input from switch will always have a valid FCS.
    -- If user requests, remove it from the output stream.
    u_tx_adj : entity work.eth_frame_adjust
        generic map(
        MIN_FRAME   => 0,
        APPEND_FCS  => false,
        STRIP_FCS   => true)
        port map(
        in_data     => txp_data,
        in_last     => txp_last,
        in_valid    => txp_valid,
        in_ready    => txp_ready,
        out_data    => txa_data,
        out_last    => txa_last,
        out_valid   => txa_valid,
        out_ready   => txa_ready,
        clk         => tx_clk,
        reset_p     => tx_reset);
end generate;

gen_tx_fcs0 : if TX_HAS_FCS generate
    -- Direct passthrough.
    txa_data        <= txp_data;
    txa_last        <= txp_last;
    txa_valid       <= txp_valid;
    txp_ready       <= txa_ready;
end generate;

-- Optional delay register
gen_tx_dly1 : if DELAY_REG generate
    blk_dly : block is
        signal tmp_data     : byte_t := (others => '0');
        signal tmp_last     : std_logic := '0';
        signal tmp_write    : std_logic := '0';
    begin
        -- Simple delay register.
        p_txdly : process(tx_clk)
        begin
            if rising_edge(tx_clk) then
                tmp_data    <= txa_data;
                tmp_last    <= txa_last;
                tmp_write   <= txa_valid and txa_ready and not tx_reset;
            end if;
        end process;

        -- A small FIFO simplifies Tx flow-control.
        u_fifo : entity work.fifo_smol_sync
            generic map(IO_WIDTH => 8)
            port map(
            in_data     => tmp_data,
            in_last     => tmp_last,
            in_write    => tmp_write,
            out_data    => tx_data,
            out_last    => tx_last,
            out_valid   => tx_valid,
            out_read    => tx_ready,
            fifo_empty  => txa_empty,
            fifo_hempty => txa_ready,
            clk         => tx_clk,
            reset_p     => tx_reset);
    end block;
end generate;

gen_tx_dly0 : if not DELAY_REG generate
    -- Direct passthrough.
    tx_data     <= txa_data;
    tx_last     <= txa_last;
    tx_valid    <= txa_valid;
    txa_ready   <= tx_ready;
    txa_empty   <= not txa_valid;
end generate;

end port_stream;
