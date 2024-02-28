--------------------------------------------------------------------------
-- Copyright 2019-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- A pipe from input port to output packet FIFO through frame check.
-- This module is intended to be used in a 2-port design in which data
-- from one port is always forwarded to the other with no MAC checks
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.switch_types.all;

entity port_passthrough is
    generic (
    ALLOW_JUMBO     : boolean := false; -- Allow jumbo frames? (Size up to 9038 bytes)
    ALLOW_RUNT      : boolean;          -- Allow runt frames? (Size < 64 bytes)
    OBUF_KBYTES     : positive);        -- Output buffer size (kilobytes)
    port (
    -- Input from first port.
    port_rx_data    : in  port_rx_m2s;

    -- Output to second port.
    port_tx_data    : out port_tx_s2m;
    port_tx_ctrl    : in  port_tx_m2s;

    -- Error events are marked by toggling these bits.
    errvec_t        : out std_logic_vector(SWITCH_ERR_WIDTH-1 downto 0));
end port_passthrough;

architecture port_passthrough of port_passthrough is

-- Frame check.
signal eth_chk_data     : std_logic_vector(7 downto 0);
signal eth_chk_write    : std_logic;
signal eth_chk_commit   : std_logic;
signal eth_chk_revert   : std_logic;
signal eth_chk_error    : std_logic;

-- Input packet error signals
signal pktin_rxerror    : std_logic;
signal pktin_crcerror   : std_logic;

-- Output packet error signals
signal pktout_overflow  : std_logic;
signal pktout_txerror   : std_logic;

-- Error toggles for switch_aux.
signal errtog_mac_late  : std_logic := '0';
signal errtog_mac_ovr   : std_logic := '0';
signal errtog_mac_tbl   : std_logic := '0';
signal errtog_pkt_crc   : std_logic := '0';
signal errtog_ovr_rx    : std_logic := '0';
signal errtog_ovr_tx    : std_logic := '0';
signal errtog_mii_tx    : std_logic := '0';
signal errtog_mii_rx    : std_logic := '0';
signal errtog_sched     : std_logic := '0';

begin

----------------------------- INPUT LOGIC ---------------------------

-- Check each frame and drive the commit / revert strobes.
-- Note: Normally, 802.3D-compliant switches should block frames sent to the
--       reserved control address.  However, a simple passthrough *should*
--       allow them through since we're not handling them ourselves.
u_frmchk : entity work.eth_frame_check
    generic map(
    ALLOW_JUMBO => ALLOW_JUMBO,
    ALLOW_MCTRL => true,
    ALLOW_RUNT  => ALLOW_RUNT)
    port map(
    in_data     => port_rx_data.data,
    in_last     => port_rx_data.last,
    in_write    => port_rx_data.write,
    out_data    => eth_chk_data,
    out_write   => eth_chk_write,
    out_commit  => eth_chk_commit,
    out_revert  => eth_chk_revert,
    out_error   => eth_chk_error,
    clk         => port_rx_data.clk,
    reset_p     => port_rx_data.reset_p);

-- Detect error strobes from MII Rx.
u_err : sync_toggle2pulse
    generic map(RISING_ONLY => true)
    port map(
    in_toggle   => port_rx_data.rxerr,
    out_strobe  => pktin_rxerror,
    out_clk     => port_rx_data.clk);
u_pkt : sync_pulse2pulse
    port map(
    in_strobe   => eth_chk_error,
    in_clk      => port_rx_data.clk,
    out_strobe  => pktin_crcerror,
    out_clk     => port_rx_data.clk);

----------------------------- OUTPUT LOGIC --------------------------
-- Instantiate this port's output FIFO.
u_fifo : entity work.fifo_packet
    generic map(
    INPUT_BYTES     => 1,
    OUTPUT_BYTES    => 1,
    BUFFER_KBYTES   => OBUF_KBYTES)
    port map(
    in_clk          => port_rx_data.clk,
    in_data         => eth_chk_data,
    in_last_commit  => eth_chk_commit,
    in_last_revert  => eth_chk_revert,
    in_write        => eth_chk_write,
    in_overflow     => open,
    out_clk         => port_tx_ctrl.clk,
    out_data        => port_tx_data.data,
    out_last        => port_tx_data.last,
    out_valid       => port_tx_data.valid,
    out_ready       => port_tx_ctrl.ready,
    out_overflow    => pktout_overflow,
    reset_p         => port_tx_ctrl.reset_p);

-- Detect error strobes from MII Tx.
u_err_tx : sync_toggle2pulse
    generic map(RISING_ONLY => true)
    port map(
    in_toggle   => port_tx_ctrl.txerr,
    out_strobe  => pktout_txerror,
    out_clk     => port_tx_ctrl.clk);


-- Create error toggles
p_errs_rx : process(port_rx_data.clk)
begin
    if rising_edge(port_rx_data.clk) then
        -- Confirm end-of-packet timing constraint holds.
        -- Consolidate per-port error strobes and convert to toggle.
        if (pktin_crcerror = '1') then
            report "Packet CRC mismatch" severity warning;
            errtog_pkt_crc <= not errtog_pkt_crc;
        end if;
        if (pktin_rxerror = '1') then
            report "Input interface error" severity error;
            errtog_mii_rx <= not errtog_mii_rx;
        end if;
    end if;
end process;

p_errs_tx : process(port_tx_ctrl.clk)
begin
    if rising_edge(port_tx_ctrl.clk) then
        -- Confirm end-of-packet timing constraint holds.
        -- Consolidate per-port error strobes and convert to toggle.
        if (pktout_overflow = '1') then
            report "Output buffer overflow" severity warning;
            errtog_ovr_tx <= not errtog_ovr_tx;
        end if;
        if (pktout_txerror = '1') then
            report "Output interface error" severity error;
            errtog_mii_tx <= not errtog_mii_tx;
        end if;
    end if;
end process;

-- Drive the final error vector:
errvec_t <= errtog_pkt_crc      -- Bit 7
          & errtog_mii_tx       -- Bit 6
          & errtog_mii_rx       -- Bit 5
          & errtog_mac_tbl      -- Bit 4
          & errtog_mac_ovr      -- Bit 3
          & errtog_mac_late     -- Bit 2
          & errtog_ovr_tx       -- Bit 1
          & errtog_ovr_rx;      -- Bit 0

end port_passthrough;
