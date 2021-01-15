--------------------------------------------------------------------------
-- Copyright 2019, 2020 The Aerospace Corporation
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
-- Note: 10/100 Mbps modes are not supported.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.switch_types.all;
use     work.synchronization.all;

entity port_sgmii_common is
    generic (
    SHAKE_WAIT  : boolean := true); -- Wait for MAC/PHY handshake?
    port (
    -- Transmitter/Serializer interface.
    tx_clk      : in  std_logic;    -- 125 MHz typical
    tx_cken     : in  std_logic := '1';
    tx_data     : out std_logic_vector(9 downto 0);

    -- Receiver/Deserializer interface.
    rx_clk      : in  std_logic;    -- 125 MHz minimum
    rx_cken     : in  std_logic := '1';
    rx_lock     : in  std_logic := '1';
    rx_data     : in  std_logic_vector(9 downto 0);

    -- Generic internal port interface.
    prx_data    : out port_rx_m2s;  -- Ingress data
    ptx_data    : in  port_tx_m2s;  -- Egress data
    ptx_ctrl    : out port_tx_s2m;  -- Egress control
    reset_p     : in  std_logic);   -- Reset / shutdown
end port_sgmii_common;

architecture port_sgmii_common of port_sgmii_common is

-- Transmit chain
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
signal rx_dly_cken  : std_logic := '0';
signal rx_dly_lock  : std_logic := '0';
signal rx_dly_data  : std_logic_vector(9 downto 0) := (others => '0');
signal rx_dec_data  : std_logic_vector(7 downto 0);
signal rx_dec_lock  : std_logic;
signal rx_dec_cken  : std_logic;
signal rx_dec_dv    : std_logic;
signal rx_dec_err   : std_logic;
signal rx_cfg_rcvd  : std_logic;
signal rx_cfg_reg   : std_logic_vector(15 downto 0);

-- For debugging, apply KEEP constraint to certain signals.
attribute KEEP : string;
attribute KEEP of rx_dly_cken, rx_dly_lock, rx_dly_data : signal is "true";

begin

-- Clock domain transitions for specific config-register bits.
hs_cfg_ack : sync_buffer
    port map(
    in_flag     => rx_cfg_rcvd,
    out_flag    => tx_cfg_rcvd,
    out_clk     => tx_clk);
hs_cfg_rcvd : sync_buffer
    port map(
    in_flag     => rx_cfg_reg(14),
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
    tx_data     => ptx_data,
    tx_ctrl     => ptx_ctrl);

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
    out_data    => tx_data,
    out_cken    => open,
    io_clk      => tx_clk,
    reset_p     => reset_p);

-- Receive: Buffer inputs for better timing
p_rxbuf : process(rx_clk)
begin
    if rising_edge(rx_clk) then
        rx_dly_cken <= rx_cken;
        rx_dly_lock <= rx_lock;
        rx_dly_data <= rx_data;
    end if;
end process;

-- Receive: 8b/10b decoder
u_rxdec : entity work.eth_dec8b10b
    port map(
    io_clk      => rx_clk,
    in_lock     => rx_dly_lock,
    in_cken     => rx_dly_cken,
    in_data     => rx_dly_data,
    out_lock    => rx_dec_lock,
    out_cken    => rx_dec_cken,
    out_dv      => rx_dec_dv,
    out_err     => rx_dec_err,
    out_data    => rx_dec_data,
    cfg_rcvd    => rx_cfg_rcvd,
    cfg_word    => rx_cfg_reg);

-- Receive: Preamble detection and removal
u_rxamb : entity work.eth_preamble_rx
    generic map(
    RATE_MBPS   => 1000)
    port map(
    raw_clk     => rx_clk,
    raw_lock    => rx_dec_lock,
    raw_cken    => rx_dec_cken,
    raw_data    => rx_dec_data,
    raw_dv      => rx_dec_dv,
    raw_err     => rx_dec_err,
    rx_data     => prx_data);

end port_sgmii_common;
