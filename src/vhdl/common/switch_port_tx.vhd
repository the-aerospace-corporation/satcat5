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
-- Per-port transmit/egress logic for the switch pipeline
--
-- This module instantiates all the logic required to emit frames from
-- an Ethernet switch to an individual port.  This includes:
--  * Priority FIFO (i.e., one or more queues for outgoing frames)
--  * Cross-clock synchronization for various error signals
--  * (Optional) PTP timestamp modification
--  * (Optional) VLAN tag insertion
--  * (Optional) Recalculate FCS if frame contents have changed
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity switch_port_tx is
    generic (
    DEV_ADDR        : integer;      -- ConfigBus device address
    PORT_INDEX      : natural;      -- Index for current port
    SUPPORT_PTP     : boolean;      -- Support precise frame timestamps?
    SUPPORT_VLAN    : boolean;      -- Support or ignore 802.1q VLAN tags?
    ALLOW_JUMBO     : boolean;      -- Allow jumbo frames? (Size up to 9038 bytes)
    ALLOW_RUNT      : boolean;      -- Allow runt frames? (Size < 64 bytes)
    INPUT_BYTES     : positive;     -- Width of shared pipeline
    OUTPUT_BYTES    : positive;     -- Width of output pipeline
    HBUF_KBYTES     : natural;      -- High-priority output buffer (kilobytes)
    OBUF_KBYTES     : positive;     -- Normal-priority output buffer (kilobytes)
    OBUF_PACKETS    : positive);    -- Output buffer max packets
    port (
    -- Input from shared pipeline, referenced to core_clk.
    in_data         : in  std_logic_vector(8*INPUT_BYTES-1 downto 0);
    in_meta         : in  switch_meta_t;
    in_nlast        : in  integer range 0 to INPUT_BYTES;
    in_keep         : in  std_logic;
    in_hipri        : in  std_logic;
    in_write        : in  std_logic;

    -- Output to the assigned port (compatible with 1 GbE and 10 GbE)
    tx_clk          : in  std_logic;
    tx_data         : out std_logic_vector(8*OUTPUT_BYTES-1 downto 0);
    tx_nlast        : out integer range 0 to OUTPUT_BYTES;
    tx_last         : out std_logic;
    tx_valid        : out std_logic;
    tx_ready        : in  std_logic;
    tx_macerr       : in  std_logic;
    tx_reset_p      : in  std_logic;

    -- Flow-control for PAUSE frames.
    pause_tx        : in  std_logic;

    -- Error strobes, referenced to core_clk.
    err_overflow    : out std_logic;
    err_txmac       : out std_logic;

    -- Configuration interface
    cfg_cmd         : in  cfgbus_cmd;

    -- System interface.
    core_clk        : in  std_logic;    -- Core datapath clock
    core_reset_p    : in  std_logic);   -- Core sync reset
end switch_port_tx;

architecture switch_port_tx of switch_port_tx is

-- Minimum padding requirement?
-- The switch itself already prevents short frames from reaching this point,
-- but VLAN tag-removal may result in frames that need to be re-padded.
function get_min_pad return natural is
begin
    if SUPPORT_VLAN and not ALLOW_RUNT then
        return 64;  -- Padding required in some edge-cases
    else
        return 0;   -- Padding is never required
    end if;
end function;

-- Maximum frame size (for output FIFO)
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
function get_meta_width return natural is
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
subtype data_t is std_logic_vector(8*OUTPUT_BYTES-1 downto 0);
subtype meta_t is std_logic_vector(get_meta_width-1 downto 0);
subtype last_t is integer range 0 to OUTPUT_BYTES;

-- Convert metadata to vector and vice-versa.
function meta2vec(x : switch_meta_t) return meta_t is
    variable meta : meta_t := (others => '0');
    variable temp : meta_t := (others => '0');
begin
    if SUPPORT_PTP then
        temp := std_logic_vector(resize(x.tstamp, meta'length));
        meta := shift_left(meta, TSTAMP_WIDTH) or temp;
    end if;
    if SUPPORT_VLAN then
        temp := resize(x.vtag, meta'length);
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

-- Clock and reset from port.
signal port_reset_p : std_logic;

-- Output priority FIFO and metadata format conversion.
signal meta_vec_in  : meta_t := (others => '0');
signal meta_vec_out : meta_t;
signal fifo_data    : byte_t;
signal fifo_meta    : switch_meta_t;
signal fifo_last    : std_logic;
signal fifo_nlast   : last_t;
signal fifo_valid   : std_logic;
signal fifo_ready   : std_logic;

-- In-place PTP header modification.
signal ptp_data     : byte_t;
signal ptp_vtag     : vlan_hdr_t;
signal ptp_nlast    : last_t;
signal ptp_valid    : std_logic;
signal ptp_ready    : std_logic;

-- VLAN tag insertion.
signal vlan_data    : byte_t;
signal vlan_vtag    : vlan_hdr_t;
signal vlan_nlast   : last_t;
signal vlan_valid   : std_logic;
signal vlan_ready   : std_logic;

-- FCS recalculation.
signal fcs_data     : byte_t;
signal fcs_nlast    : last_t;
signal fcs_valid    : std_logic;
signal fcs_ready    : std_logic;

begin

-- Convert metadata for FIFO input/output.
fifo_meta <= vec2meta(meta_vec_out);
gen_meta : if get_meta_width > 1 generate
    meta_vec_in <= meta2vec(in_meta);
end generate;

-- Instantiate this port's output FIFO.
u_fifo : entity work.fifo_priority
    generic map(
    INPUT_BYTES     => INPUT_BYTES,
    OUTPUT_BYTES    => OUTPUT_BYTES,
    META_WIDTH      => get_meta_width,
    BUFF_HI_KBYTES  => HBUF_KBYTES,
    BUFF_LO_KBYTES  => OBUF_KBYTES,
    MAX_PACKETS     => OBUF_PACKETS,
    MAX_PKT_BYTES   => get_max_frame)
    port map(
    in_clk          => core_clk,
    in_data         => in_data,
    in_meta         => meta_vec_in,
    in_nlast        => in_nlast,
    in_last_keep    => in_keep,
    in_last_hipri   => in_hipri,
    in_write        => in_write,
    in_overflow     => err_overflow,
    out_clk         => tx_clk,
    out_data        => fifo_data,
    out_meta        => meta_vec_out,
    out_nlast       => fifo_nlast,
    out_valid       => fifo_valid,
    out_ready       => fifo_ready,
    out_reset       => port_reset_p,    -- Sync'd output
    async_pause     => pause_tx,
    reset_p         => tx_reset_p);     -- Input from port

-- If PTP is enabled, modify outgoing timestamps.
gen_ptp1 : if SUPPORT_PTP generate
    -- TODO: Placeholder ONLY!
    -- TODO: Replace this once the design is complete.
    ptp_data    <= fifo_data;
    ptp_vtag    <= fifo_meta.vtag;
    ptp_nlast   <= fifo_nlast;
    ptp_valid   <= fifo_valid;
    fifo_ready  <= ptp_ready;
end generate;

gen_ptp0 : if not SUPPORT_PTP generate
    ptp_data    <= fifo_data;
    ptp_vtag    <= fifo_meta.vtag;
    ptp_nlast   <= fifo_nlast;
    ptp_valid   <= fifo_valid;
    fifo_ready  <= ptp_ready;
end generate;

-- If VLAN is enabled, insert VLAN tags as needed.
gen_vlan1 : if SUPPORT_VLAN generate
    u_vtag : entity work.eth_frame_vtag
        generic map(
        DEV_ADDR    => DEV_ADDR,
        REG_ADDR    => REGADDR_VLAN_PORT,
        PORT_INDEX  => PORT_INDEX,
        IO_BYTES    => OUTPUT_BYTES)
        port map(
        in_data     => ptp_data,
        in_vtag     => ptp_vtag,
        in_nlast    => ptp_nlast,
        in_valid    => ptp_valid,
        in_ready    => ptp_ready,
        out_data    => vlan_data,
        out_nlast   => vlan_nlast,
        out_valid   => vlan_valid,
        out_ready   => vlan_ready,
        cfg_cmd     => cfg_cmd,
        clk         => tx_clk,
        reset_p     => port_reset_p);
end generate;

gen_vlan0 : if not SUPPORT_VLAN generate
    vlan_data   <= ptp_data;
    vlan_nlast  <= ptp_nlast;
    vlan_valid  <= ptp_valid;
    ptp_ready   <= vlan_ready;
end generate;

-- If we may have modified the frame contents, modify FCS.
gen_adj1 : if SUPPORT_PTP or SUPPORT_VLAN generate
    u_adj : entity work.eth_frame_adjust
        generic map(
        MIN_FRAME   => get_min_pad,
        STRIP_FCS   => true,    -- Remove old FCS...
        APPEND_FCS  => true,    -- ...then add a new one
        IO_BYTES    => OUTPUT_BYTES)
        port map(
        in_data     => vlan_data,
        in_nlast    => vlan_nlast,
        in_valid    => vlan_valid,
        in_ready    => vlan_ready,
        out_data    => fcs_data,
        out_nlast   => fcs_nlast,
        out_valid   => fcs_valid,
        out_ready   => fcs_ready,
        clk         => tx_clk,
        reset_p     => port_reset_p);
end generate;

gen_adj0 : if not(SUPPORT_PTP or SUPPORT_VLAN) generate
    fcs_data    <= vlan_data;
    fcs_nlast   <= vlan_nlast;
    fcs_valid   <= vlan_valid;
    vlan_ready  <= fcs_ready;
end generate;

-- Connect final output signals.
tx_data     <= fcs_data;
tx_nlast    <= fcs_nlast;
tx_last     <= bool2bit(fcs_nlast > 0);
tx_valid    <= fcs_valid;
fcs_ready   <= tx_ready;

-- Detect error strobes from MII Tx.
u_err : sync_toggle2pulse
    generic map(RISING_ONLY => true)
    port map(
    in_toggle   => tx_macerr,
    out_strobe  => err_txmac,
    out_clk     => core_clk);

end switch_port_tx;
