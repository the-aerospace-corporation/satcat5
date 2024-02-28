--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
use     work.ptp_types.all;
use     work.switch_types.all;

entity switch_port_tx is
    generic (
    DEV_ADDR        : integer;      -- ConfigBus device address
    PORT_INDEX      : natural;      -- Index for current port
    SUPPORT_PTP     : boolean;      -- Support precise frame timestamps?
    SUPPORT_VLAN    : boolean;      -- Support or ignore 802.1q VLAN tags?
    ALLOW_JUMBO     : boolean;      -- Allow jumbo frames? (Size up to 9038 bytes)
    ALLOW_RUNT      : boolean;      -- Allow runt frames? (Size < 64 bytes)
    PTP_STRICT      : boolean;      -- Drop frames with missing timestamps?
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
    in_precommit    : in  std_logic;
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
    tx_pstart       : in  std_logic;
    tx_tnow         : in  tstamp_t;
    tx_macerr       : in  std_logic;
    tx_reset_p      : in  std_logic;

    -- Port-specific control flags.
    pause_tx        : in  std_logic;    -- Flow-control for PAUSE frames
    port_2step      : in  std_logic;    -- PTP format conversion

    -- Error strobes, referenced to core_clk.
    err_overflow    : out std_logic;
    err_txmac       : out std_logic;
    err_ptp         : out std_logic;

    -- Configuration interface
    cfg_cmd         : in  cfgbus_cmd;
    cfg_ack         : out cfgbus_ack;

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

-- Convenience types
subtype data_t is std_logic_vector(8*OUTPUT_BYTES-1 downto 0);
subtype last_t is integer range 0 to OUTPUT_BYTES;

-- Clock and reset from port.
signal port_reset_p : std_logic;

-- Output priority FIFO and metadata format conversion.
signal meta_vec_in  : switch_meta_v := (others => '0');
signal meta_vec_out : switch_meta_v;
signal fifo_data    : byte_t;
signal fifo_meta    : switch_meta_t;
signal fifo_nlast   : last_t;
signal fifo_valid   : std_logic;
signal fifo_ready   : std_logic;

-- In-place PTP header modification.
signal ptp_data     : byte_t;
signal ptp_vtag     : vlan_hdr_t;
signal ptp_nlast    : last_t;
signal ptp_error    : std_logic;
signal ptp_valid    : std_logic;
signal ptp_ready    : std_logic;

-- VLAN tag insertion.
signal vlan_data    : byte_t;
signal vlan_nlast   : last_t;
signal vlan_error   : std_logic;
signal vlan_valid   : std_logic;
signal vlan_ready   : std_logic;

-- FCS recalculation.
signal fcs_data     : byte_t;
signal fcs_nlast    : last_t;
signal fcs_valid    : std_logic;
signal fcs_ready    : std_logic;

-- ConfigBus combining.
signal err_ptp_stb  : std_logic;
signal cfg_acks     : cfgbus_ack_array(0 to 0) := (others => cfgbus_idle);

begin

-- Convert metadata for FIFO input/output.
-- Note: Relying on synthesis tools to trim unused metadata fields.
fifo_meta   <= switch_v2m(meta_vec_out);
meta_vec_in <= switch_m2v(in_meta);

-- Instantiate this port's output FIFO.
u_fifo : entity work.fifo_priority
    generic map(
    INPUT_BYTES     => INPUT_BYTES,
    OUTPUT_BYTES    => OUTPUT_BYTES,
    META_WIDTH      => SWITCH_META_WIDTH,
    BUFF_HI_KBYTES  => HBUF_KBYTES,
    BUFF_LO_KBYTES  => OBUF_KBYTES,
    MAX_PACKETS     => OBUF_PACKETS,
    MAX_PKT_BYTES   => get_max_frame)
    port map(
    in_clk          => core_clk,
    in_data         => in_data,
    in_meta         => meta_vec_in,
    in_nlast        => in_nlast,
    in_precommit    => in_precommit,
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
    u_ptp : entity work.ptp_egress
        generic map(
        IO_BYTES    => OUTPUT_BYTES,
        PTP_STRICT  => PTP_STRICT,
        DEVADDR     => DEV_ADDR,
        REGADDR     => REGADDR_PORT_BASE(PORT_INDEX) + REGOFFSET_PORT_PTP_TX)
        port map(
        port_tnow   => tx_tnow,
        port_pstart => tx_pstart,
        port_dvalid => fcs_valid,
        in_tref     => fifo_meta.tstamp,
        in_pmode    => fifo_meta.pmode,
        in_vtag     => fifo_meta.vtag,
        in_data     => fifo_data,
        in_nlast    => fifo_nlast,
        in_valid    => fifo_valid,
        in_ready    => fifo_ready,
        out_vtag    => ptp_vtag,
        out_data    => ptp_data,
        out_error   => ptp_error,
        out_nlast   => ptp_nlast,
        out_valid   => ptp_valid,
        out_ready   => ptp_ready,
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(0),
        cfg_2step   => port_2step,
        clk         => tx_clk,
        reset_p     => port_reset_p);
end generate;

gen_ptp0 : if not SUPPORT_PTP generate
    ptp_data    <= fifo_data;
    ptp_vtag    <= fifo_meta.vtag;
    ptp_error   <= '0';
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
        in_error    => ptp_error,
        in_nlast    => ptp_nlast,
        in_valid    => ptp_valid,
        in_ready    => ptp_ready,
        out_data    => vlan_data,
        out_error   => vlan_error,
        out_nlast   => vlan_nlast,
        out_valid   => vlan_valid,
        out_ready   => vlan_ready,
        cfg_cmd     => cfg_cmd,
        clk         => tx_clk,
        reset_p     => port_reset_p);
end generate;

gen_vlan0 : if not SUPPORT_VLAN generate
    vlan_data   <= ptp_data;
    vlan_error  <= ptp_error;
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
        in_error    => vlan_error,
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

u_ptperr:  process (tx_clk)
begin
    if rising_edge(tx_clk) then
        err_ptp_stb <= '0';
        if (ptp_valid='1' and ptp_ready='1' and ptp_nlast > 0) then
            err_ptp_stb <= ptp_error;
        end if;
    end if;
end process;

u_ptp_err_sync: sync_pulse2pulse
    port map(
    in_strobe   => err_ptp_stb,
    in_clk      => tx_clk,
    out_strobe  => err_ptp,
    out_clk     => core_clk);

-- Combine ConfigBus replies.
cfg_ack <= cfgbus_merge(cfg_acks);

end switch_port_tx;
