--------------------------------------------------------------------------
-- Copyright 2019-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- General-purpose logic for SGMII transceiver port
--
-- This module implements basic, platform-independent functions for
-- interfacing an SGMII port to the switch fabric.  This includes
-- an 8b/10b encoder, an 8b/10b decoder, the state machine for
-- handling link-startup handshaking, preamble insertion, etc.
--
-- Generally, this block is instantiated inside a platform-specific
-- module that instantiates and controls the external interfaces.
--
-- Note: 10/100/1000 Mbps modes are all supported.  SGMII handles
--       these modes through byte-repetition, which is detected
--       and removed by the "eth_preamble_rx" block.  The same
--       setting is then mirrored to any outgoing packets.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.sync_buffer;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity port_sgmii_common is
    generic (
    MSB_FIRST   : boolean := true;   -- Bit order for tx_data, rx_data
    SHAKE_WAIT  : boolean := false); -- Wait for MAC/PHY handshake?
    port (
    -- Transmitter/Serializer interface.
    tx_clk      : in  std_logic;    -- 125 MHz typical
    tx_cken     : in  std_logic := '1';
    tx_data     : out std_logic_vector(9 downto 0);
    tx_tstamp   : in  tstamp_t := (others => '0');
    tx_tvalid   : in  std_logic := '0';

    -- Receiver/Deserializer interface.
    rx_clk      : in  std_logic;    -- 125 MHz minimum
    rx_cken     : in  std_logic := '1';
    rx_lock     : in  std_logic := '1';
    rx_data     : in  std_logic_vector(9 downto 0);
    rx_tstamp   : in  tstamp_t := (others => '0');
    rx_tvalid   : in  std_logic := '0';

    -- Generic internal port interface.
    prx_data    : out port_rx_m2s;  -- Ingress data
    ptx_data    : in  port_tx_s2m;  -- Egress data
    ptx_ctrl    : out port_tx_m2s;  -- Egress control
    reset_p     : in  std_logic);   -- Reset / shutdown
end port_sgmii_common;

architecture port_sgmii_common of port_sgmii_common is

-- Transmit chain
signal tx_data_msb  : std_logic_vector(9 downto 0);
signal tx_amb_data  : std_logic_vector(7 downto 0);
signal tx_amb_dv    : std_logic;
signal tx_amb_err   : std_logic;
signal tx_cfg_xmit  : std_logic;
signal tx_cfg_rcvd  : std_logic;
signal tx_cfg_ack   : std_logic;
signal tx_cfg_reg   : std_logic_vector(15 downto 0);
signal tx_pwren     : std_logic;
signal tx_pkten     : std_logic;
signal tx_frmst     : std_logic;

-- Receive chain
signal rx_data_msb  : std_logic_vector(9 downto 0);
signal rx_dly_cken  : std_logic := '0';
signal rx_dly_lock  : std_logic := '0';
signal rx_dly_data  : std_logic_vector(9 downto 0) := (others => '0');
signal rx_dly_tsof  : tstamp_t := (others => '0');
signal rx_dec_data  : std_logic_vector(7 downto 0);
signal rx_dec_tsof  : tstamp_t := (others => '0');
signal rx_dec_lock  : std_logic;
signal rx_dec_cken  : std_logic;
signal rx_dec_dv    : std_logic;
signal rx_dec_err   : std_logic;
signal rx_cfg_ack   : std_logic;
signal rx_cfg_rcvd  : std_logic;
signal rx_cfg_reg   : std_logic_vector(15 downto 0);
signal rx_rep_rate  : byte_u;
signal rx_rep_valid : std_logic;

-- Rate detection
signal rate_10      : std_logic := '0';
signal rate_100     : std_logic := '0';
signal rate_1000    : std_logic := '0';
signal rate_error   : std_logic := '0';
signal rate_word    : port_rate_t := get_rate_word(1000);

-- Status reporting
signal status_word  : port_status_t;

-- For debugging, apply KEEP constraint to certain signals.
attribute KEEP : string;
attribute KEEP of rx_dly_cken, rx_dly_lock, rx_dly_data : signal is "true";

begin

-- Clock domain transitions for specific config-register bits.
rx_cfg_ack <= rx_cfg_reg(14);

hs_cfg_ack : sync_buffer
    port map(
    in_flag     => rx_cfg_rcvd,
    out_flag    => tx_cfg_rcvd,
    out_clk     => tx_clk);
hs_cfg_rcvd : sync_buffer
    port map(
    in_flag     => rx_cfg_ack,
    out_flag    => tx_cfg_ack,
    out_clk     => tx_clk);

-- Set configuration register for auto-negotiate handshake.
-- Handshake defined by IEEE 802.3-2015, Section 37.2.1 (Config_Reg)
-- Bit assignments set by Cisco ENG-46158, SGMII Specification 1.8, Table 1.
tx_pwren    <= not reset_p;                 -- Idle except during reset
tx_cfg_xmit <= not tx_cfg_ack;              -- Transmit until acknowledged
tx_cfg_reg  <= (14 => '1', 0 => '1', others => '0');    -- MAC to PHY

-- Allow data transmission before MAC/PHY handshake is established?
tx_pkten    <= (tx_cfg_rcvd and tx_cfg_ack) when SHAKE_WAIT else '1';

-- Convert input and output signals to preferred MSB-first order.
tx_data     <= tx_data_msb when MSB_FIRST else flip_vector(tx_data_msb);
rx_data_msb <= rx_data     when MSB_FIRST else flip_vector(rx_data);

-- Transmit: preamble insertion
u_txamb : entity work.eth_preamble_tx
    port map(
    out_data    => tx_amb_data,
    out_dv      => tx_amb_dv,
    out_err     => tx_amb_err,
    tx_clk      => tx_clk,
    tx_pwren    => tx_pwren,
    tx_pkten    => tx_pkten,
    tx_frmst    => tx_frmst,
    tx_cken     => tx_cken,
    tx_tstamp   => tx_tstamp,
    tx_data     => ptx_data,
    tx_ctrl     => ptx_ctrl,
    rep_rate    => rx_rep_rate);

-- Transmit: 8b/10b encoder
u_txenc : entity work.eth_enc8b10b
    port map(
    in_data     => tx_amb_data,
    in_dv       => tx_amb_dv,
    in_err      => tx_amb_err,
    in_cken     => tx_cken,
    in_frmst    => tx_frmst,
    cfg_xmit    => tx_cfg_xmit,
    cfg_word    => tx_cfg_reg,
    out_data    => tx_data_msb,
    out_cken    => open,
    io_clk      => tx_clk,
    reset_p     => reset_p);

-- Receive: Buffer inputs for better timing
p_rxbuf : process(rx_clk)
begin
    if rising_edge(rx_clk) then
        rx_dly_cken <= rx_cken;
        rx_dly_lock <= rx_lock;
        rx_dly_data <= rx_data_msb;
        rx_dly_tsof <= rx_tstamp;
    end if;
end process;

-- Receive: 8b/10b decoder
u_rxdec : entity work.eth_dec8b10b
    generic map(
    IN_RATE_HZ  => 1_250_000_000)
    port map(
    io_clk      => rx_clk,
    in_lock     => rx_dly_lock,
    in_cken     => rx_dly_cken,
    in_data     => rx_dly_data,
    in_tsof     => rx_dly_tsof,
    out_lock    => rx_dec_lock,
    out_cken    => rx_dec_cken,
    out_dv      => rx_dec_dv,
    out_err     => rx_dec_err,
    out_data    => rx_dec_data,
    out_tsof    => rx_dec_tsof,
    cfg_rcvd    => rx_cfg_rcvd,
    cfg_word    => rx_cfg_reg);

-- Receive: Preamble detection and removal
u_rxamb : entity work.eth_preamble_rx
    generic map(
    REP_ENABLE  => true)
    port map(
    raw_clk     => rx_clk,
    raw_lock    => rx_dec_lock,
    raw_cken    => rx_dec_cken,
    raw_data    => rx_dec_data,
    raw_dv      => rx_dec_dv,
    raw_err     => rx_dec_err,
    rep_rate    => rx_rep_rate,
    rep_valid   => rx_rep_valid,
    rate_word   => rate_word,
    aux_err     => rate_error,
    rx_tstamp   => rx_dec_tsof,
    status      => status_word,
    rx_data     => prx_data);

-- Rate detection
p_rate : process(rx_clk)
begin
    if rising_edge(rx_clk) then
        -- Set defaults, override as needed.
        rate_10     <= '0';
        rate_100    <= '0';
        rate_1000   <= '0';
        rate_error  <= '0';

        -- Note: Each Tx/Rx byte repeated N+1 times.
        if (rx_rep_valid = '0') then
            rate_word   <= RATE_WORD_NULL;
        elsif (rx_rep_rate = 0) then
            rate_word   <= get_rate_word(1000);
            rate_1000   <= '1'; -- 1x repeat = 1000 Mbps
        elsif (rx_rep_rate = 9) then
            rate_word   <= get_rate_word(100);
            rate_100    <= '1'; -- 10x repeat = 100 Mbps
        elsif (rx_rep_rate = 99) then
            rate_word   <= get_rate_word(10);
            rate_10     <= '1'; -- 100x repeat = 10 Mbps
        else
            rate_word   <= get_rate_word(10);
            rate_error  <= '1'; -- Unexpected rate
        end if;
    end if;
end process;

-- Upstream status reporting.
status_word <= (
    0 => reset_p,
    1 => rx_tvalid and tx_tvalid,
    2 => rx_dly_lock and rx_dec_lock,
    3 => rx_cfg_rcvd,
    4 => rx_cfg_ack,
    5 => rate_1000,
    6 => rate_100,
    7 => rate_10);

end port_sgmii_common;
