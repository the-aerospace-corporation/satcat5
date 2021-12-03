--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation
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
-- Per-port receive/ingress logic for the switch pipeline
--
-- This module instantiates all of the logic required to accept data
-- from one port into the rest of an Ethernet switch.  This includes:
--  * Frame integrity check (i.e., confirm incoming frames are valid)
--  * Packet FIFO (i.e., buffer incoming frames for verification)
--  * Cross-clock synchronization for various error signals
--  * (Optional) Pause-frame detection per-port flow control)
--  * (Optional) VLAN tag parsing and removal
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity switch_port_rx is
    generic (
    DEV_ADDR        : integer;      -- ConfigBus device address
    CORE_CLK_HZ     : positive;     -- Rate of core_clk (Hz)
    PORT_INDEX      : natural;      -- Index for current port
    SUPPORT_PAUSE   : boolean;      -- Support or ignore 802.3x PAUSE frames?
    SUPPORT_PTP     : boolean;      -- Support precise frame timestamps?
    SUPPORT_VLAN    : boolean;      -- Support or ignore 802.1q VLAN tags?
    ALLOW_JUMBO     : boolean;      -- Allow jumbo frames? (Size up to 9038 bytes)
    ALLOW_RUNT      : boolean;      -- Allow runt frames? (Size < 64 bytes)
    INPUT_BYTES     : positive;     -- Width of input pipeline
    OUTPUT_BYTES    : positive;     -- Width of shared pipeline
    IBUF_KBYTES     : positive;     -- Input buffer size (kilobytes)
    IBUF_PACKETS    : positive);    -- Input buffer max packets
    port (
    -- Input from the assigned port (compatible with 1 GbE and 10 GbE)
    rx_clk          : in  std_logic;
    rx_data         : in  std_logic_vector(8*INPUT_BYTES-1 downto 0);
    rx_nlast        : in  integer range 0 to INPUT_BYTES := 0;
    rx_last         : in  std_logic := '0'; -- Ignored if INPUT_BYTES > 1
    rx_write        : in  std_logic;
    rx_macerr       : in  std_logic;
    rx_rate         : in  port_rate_t;
    rx_reset_p      : in  std_logic;

    -- Output to shared pipeline, referenced to core_clk.
    out_data        : out std_logic_vector(8*OUTPUT_BYTES-1 downto 0);
    out_meta        : out switch_meta_t;
    out_nlast       : out integer range 0 to OUTPUT_BYTES;
    out_last        : out std_logic;
    out_valid       : out std_logic;
    out_ready       : in  std_logic;

    -- Flow-control for PAUSE frames, if supported.
    pause_tx        : out std_logic;

    -- Error strobes, referenced to core_clk.
    err_badfrm      : out std_logic;
    err_rxmac       : out std_logic;
    err_overflow    : out std_logic;

    -- Configuration interface (required for PTP/VLAN)
    cfg_cmd         : in  cfgbus_cmd := CFGBUS_CMD_NULL;

    -- System interface.
    core_clk        : in  std_logic;    -- Core datapath clock
    core_reset_p    : in  std_logic);   -- Core sync reset
end switch_port_rx;

architecture switch_port_rx of switch_port_rx is

-- Maximum frame size? (For checking incoming frames.)
function get_max_frame return positive is
begin
    if ALLOW_JUMBO then
        return MAX_JUMBO_BYTES;
    else
        return MAX_FRAME_BYTES;
    end if;
end function;

-- Required metadata size?
-- (Retain a single bit if empty, to avoid problems with some tools.)
function get_meta_width return positive is
    variable tmp : natural := 0;
begin
    if SUPPORT_PTP then
        tmp := tmp + TSTAMP_WIDTH;
    end if;
    if SUPPORT_VLAN then
        tmp := tmp + VLAN_HDR_WIDTH;
    end if;
    return int_max(1, tmp);
end function;

-- Convenience types
subtype data_t is std_logic_vector(8*INPUT_BYTES-1 downto 0);
subtype meta_t is std_logic_vector(get_meta_width-1 downto 0);
subtype last_t is integer range 0 to INPUT_BYTES;

-- Convert metadata to vector and vice-versa.
function meta2vec(x : switch_meta_t) return meta_t is
    variable meta : meta_t := (others => '0');
    variable temp : meta_t := (others => '0');
begin
    if SUPPORT_PTP then
        temp := std_logic_vector(resize(x.tstamp, get_meta_width));
        meta := shift_left(meta, TSTAMP_WIDTH) or temp;
    end if;
    if SUPPORT_VLAN then
        temp := resize(x.vtag, get_meta_width);
        meta := shift_left(meta, VLAN_HDR_WIDTH) or temp;
    end if;
    return meta;
end function;

function vec2meta(x : meta_t) return switch_meta_t is
    variable meta : switch_meta_t := SWITCH_META_NULL;
    variable temp : meta_t := x;
begin
    if SUPPORT_VLAN then
        meta.vtag := temp(VLAN_HDR_WIDTH-1 downto 0);
        temp := shift_right(temp, VLAN_HDR_WIDTH);
    end if;
    if SUPPORT_PTP then
        meta.tstamp := unsigned(temp(TSTAMP_WIDTH-1 downto 0));
        temp := shift_right(temp, TSTAMP_WIDTH);
    end if;
    return meta;
end function;

-- Input format conversion
signal rx_reset_i   : std_logic;
signal rx_nlast_adj : integer range 0 to INPUT_BYTES;

-- Frame integrity check
signal chk_data     : data_t;
signal chk_nlast    : last_t;
signal chk_write    : std_logic;
signal chk_commit   : std_logic;
signal chk_revert   : std_logic;
signal chk_error    : std_logic;

-- VLAN tag parsing
signal vlan_data    : data_t;
signal vlan_nlast   : last_t;
signal vlan_write   : std_logic;
signal vlan_commit  : std_logic;
signal vlan_revert  : std_logic;
signal vlan_error   : std_logic;

-- Output FIFO and metadata format conversion.
signal rx_meta      : switch_meta_t := SWITCH_META_NULL;
signal mvec_in      : meta_t := (others => '0');
signal mvec_out     : meta_t;
signal pkt_final    : std_logic;

begin

-- Backwards compatibility for legacy interfaces.
rx_nlast_adj <= 1 when (INPUT_BYTES = 1 and rx_last = '1') else rx_nlast;

-- Optionally monitor incoming traffic for PAUSE requests.
gen_pause1 : if SUPPORT_PAUSE generate
    u_pause : entity work.eth_pause_ctrl
        generic map(
        REFCLK_HZ   => CORE_CLK_HZ,
        IO_BYTES    => INPUT_BYTES)
        port map(
        rx_clk      => rx_clk,
        rx_data     => rx_data,
        rx_nlast    => rx_nlast_adj,
        rx_write    => rx_write,
        rx_rate     => rx_rate,
        rx_reset_p  => rx_reset_i,
        pause_tx    => pause_tx,
        ref_clk     => core_clk,
        reset_p     => core_reset_p);
end generate;

gen_pause0 : if not SUPPORT_PAUSE generate
    pause_tx <= '0';
end generate;

-- If PTP is enabled, small FIFO for timestamps from MAC/PHY.
gen_ptp1 : if SUPPORT_PTP generate
    -- TODO: Connect this once the PTP design is complete.
    -- TODO: PTP block should have a small FIFO connected to pkt_final.
end generate;

-- Check each frame and drive the commit / revert strobes.
u_frmchk : entity work.eth_frame_check
    generic map(
    ALLOW_JUMBO => ALLOW_JUMBO,
    ALLOW_RUNT  => ALLOW_RUNT,
    IO_BYTES    => INPUT_BYTES)
    port map(
    in_data     => rx_data,
    in_nlast    => rx_nlast_adj,
    in_write    => rx_write,
    out_data    => chk_data,
    out_nlast   => chk_nlast,
    out_write   => chk_write,
    out_commit  => chk_commit,
    out_revert  => chk_revert,
    out_error   => chk_error,
    clk         => rx_clk,
    reset_p     => rx_reset_i);

-- If VLAN is enabled, parse and remove VLAN tags.
gen_vlan1 : if SUPPORT_VLAN generate
    u_vlan : entity work.eth_frame_vstrip
        generic map(
        DEVADDR     => DEV_ADDR,
        REGADDR     => REGADDR_VLAN_PORT,
        IO_BYTES    => INPUT_BYTES,
        PORT_INDEX  => PORT_INDEX)
        port map(
        in_data     => chk_data,
        in_nlast    => chk_nlast,
        in_write    => chk_write,
        in_commit   => chk_commit,
        in_revert   => chk_revert,
        in_error    => chk_error,
        out_data    => vlan_data,
        out_vtag    => rx_meta.vtag,
        out_nlast   => vlan_nlast,
        out_write   => vlan_write,
        out_commit  => vlan_commit,
        out_revert  => vlan_revert,
        out_error   => vlan_error,
        cfg_cmd     => cfg_cmd,
        clk         => rx_clk,
        reset_p     => rx_reset_i);
end generate;

gen_vlan0 : if not SUPPORT_VLAN generate
    vlan_data   <= chk_data;
    vlan_nlast  <= chk_nlast;
    vlan_write  <= chk_write;
    vlan_commit <= chk_commit;
    vlan_revert <= chk_revert;
    vlan_error  <= chk_error;
end generate;

-- End-of-frame strobe.
pkt_final <= vlan_write and (vlan_commit or vlan_revert or vlan_error);

-- Metadata format conversion.
out_meta <= vec2meta(mvec_out);
gen_meta : if get_meta_width > 1 generate
    mvec_in <= meta2vec(rx_meta);
end generate;

-- Instantiate this port's input FIFO.
u_fifo : entity work.fifo_packet
    generic map(
    INPUT_BYTES     => INPUT_BYTES,
    OUTPUT_BYTES    => OUTPUT_BYTES,
    BUFFER_KBYTES   => IBUF_KBYTES,
    META_WIDTH      => get_meta_width,
    MAX_PACKETS     => IBUF_PACKETS,
    MAX_PKT_BYTES   => get_max_frame)
    port map(
    in_clk          => rx_clk,
    in_pkt_meta     => mvec_in,
    in_data         => vlan_data,
    in_nlast        => vlan_nlast,
    in_last_commit  => vlan_commit,
    in_last_revert  => vlan_revert,
    in_write        => vlan_write,
    in_overflow     => open,
    in_reset        => rx_reset_i,
    out_clk         => core_clk,
    out_pkt_meta    => mvec_out,
    out_data        => out_data,
    out_nlast       => out_nlast,
    out_last        => out_last,
    out_valid       => out_valid,
    out_ready       => out_ready,
    out_overflow    => err_overflow,
    reset_p         => rx_reset_p);

-- Detect error strobes from MII Rx.
u_err : sync_toggle2pulse
    generic map(RISING_ONLY => true)
    port map(
    in_toggle   => rx_macerr,
    out_strobe  => err_rxmac,
    out_clk     => core_clk);
u_pkt : sync_pulse2pulse
    port map(
    in_strobe   => vlan_error,
    in_clk      => rx_clk,
    out_strobe  => err_badfrm,
    out_clk     => core_clk);

end switch_port_rx;
