--------------------------------------------------------------------------
-- Copyright 2021-2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
use     work.ptp_types.all;
use     work.switch_types.all;

entity switch_port_rx is
    generic (
    DEV_ADDR        : integer;      -- ConfigBus device address
    CORE_CLK_HZ     : positive;     -- Rate of core_clk (Hz)
    PORT_COUNT      : positive;     -- Total ports in this switch
    PORT_INDEX      : natural;      -- Index for current port
    PTP_DOPPLER     : boolean;      -- Enable Doppler-TLV tags?
    STRIP_FCS       : boolean;      -- Strip FCS from incoming frames?
    SUPPORT_LOG     : boolean;      -- Support packet logging diagnostics?
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
    rx_tsof         : in  tstamp_t;
    rx_tfreq        : in  tfreq_t;
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
    err_log_data    : out log_meta_t;
    err_log_write   : out std_logic;

    -- Configuration interface (required for PTP/VLAN)
    cfg_cmd         : in  cfgbus_cmd;
    cfg_ack         : out cfgbus_ack;

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

-- Calculate worst-case timeout for round-robin packet readout.
-- (i.e., Every other port is waiting to read out a max-length frame.)
constant READ_MAX_WAIT : positive := div_ceil(PORT_COUNT * get_max_frame, OUTPUT_BYTES);
constant FLUSH_TIMEOUT : positive := 2 ** log2_ceil(2 * READ_MAX_WAIT) - 1;

-- Convenience types
subtype data_t is std_logic_vector(8*INPUT_BYTES-1 downto 0);
subtype last_t is integer range 0 to INPUT_BYTES;

-- Input format conversion
signal rx_reset_i   : std_logic;
signal rx_nlast_adj : integer range 0 to INPUT_BYTES;

-- Frame integrity check
signal chk_data     : data_t;
signal chk_nlast    : last_t;
signal chk_write    : std_logic;
signal chk_result   : frm_result_t;

-- VLAN tag parsing
signal vlan_data    : data_t;
signal vlan_nlast   : last_t;
signal vlan_write   : std_logic;
signal vlan_result  : frm_result_t;

-- PTP metadata
signal ptp_data     : data_t;
signal ptp_nlast    : last_t;
signal ptp_write    : std_logic;
signal ptp_result   : frm_result_t;
signal ptp_error    : std_logic;

-- Output FIFO and metadata format conversion.
signal rx_meta      : switch_meta_t := SWITCH_META_NULL;
signal rx_overflow  : std_logic;
signal log_toggle   : std_logic;
signal mvec_in      : switch_meta_v := (others => '0');
signal mvec_out     : switch_meta_v;
signal pkt_error    : std_logic;
signal pkt_final    : std_logic;

-- ConfigBus combining.
signal cfg_acks     : cfgbus_ack_array(0 to 0) := (others => cfgbus_idle);

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

-- Check each frame and drive the commit / revert strobes.
-- Do this first, because VLAN header removal invalidates the FCS.
u_frmchk : entity work.eth_frame_check
    generic map(
    ALLOW_JUMBO => ALLOW_JUMBO,
    ALLOW_RUNT  => ALLOW_RUNT,
    IO_BYTES    => INPUT_BYTES,
    STRIP_FCS   => STRIP_FCS)
    port map(
    in_data     => rx_data,
    in_nlast    => rx_nlast_adj,
    in_write    => rx_write,
    out_data    => chk_data,
    out_nlast   => chk_nlast,
    out_write   => chk_write,
    out_result  => chk_result,
    clk         => rx_clk,
    reset_p     => rx_reset_i);

-- If VLAN is enabled, parse and remove VLAN tags.
-- This step must be performed before PTP message parsing.
gen_vlan1 : if SUPPORT_VLAN generate
    u_vlan : entity work.eth_frame_vstrip
        generic map(
        DEVADDR     => DEV_ADDR,
        REGADDR     => SW_ADDR_VLAN_PORT,
        IO_BYTES    => INPUT_BYTES,
        PORT_INDEX  => PORT_INDEX)
        port map(
        in_data     => chk_data,
        in_nlast    => chk_nlast,
        in_write    => chk_write,
        in_result   => chk_result,
        out_data    => vlan_data,
        out_vtag    => rx_meta.vtag,
        out_nlast   => vlan_nlast,
        out_write   => vlan_write,
        out_result  => vlan_result,
        cfg_cmd     => cfg_cmd,
        clk         => rx_clk,
        reset_p     => rx_reset_i);
end generate;

gen_vlan0 : if not SUPPORT_VLAN generate
    vlan_data   <= chk_data;
    vlan_nlast  <= chk_nlast;
    vlan_write  <= chk_write;
    vlan_result <= chk_result;
end generate;

-- If PTP is enabled, generate additional metadata.
gen_ptp1 : if SUPPORT_PTP generate
    blk_ptp1 : block is
        signal pkt_valid1 : std_logic;
        signal pkt_valid2 : std_logic;
    begin
        -- Mark start-of-frame timestamps using metadata from MAC/PHY.
        -- Use the raw "rx_data" stream to ensure consistent pipeline delays.
        u_tsof : entity work.ptp_timestamp
            generic map(
            IO_BYTES    => INPUT_BYTES,
            PTP_DOPPLER => PTP_DOPPLER,
            PTP_STRICT  => false,
            DEVADDR     => DEV_ADDR,
            REGADDR     => SW_ADDR_PORT_BASE(PORT_INDEX) + REGOFFSET_PORT_PTP_RX)
            port map(
            in_adj_time => '1',
            in_adj_freq => '1',
            in_tnow     => rx_tsof,
            in_tfreq    => rx_tfreq,
            in_nlast    => rx_nlast_adj,
            in_write    => rx_write,
            out_tstamp  => rx_meta.tstamp,
            out_tfreq   => rx_meta.tfreq,
            out_valid   => pkt_valid1,
            out_ready   => pkt_final,
            cfg_cmd     => cfg_cmd,
            cfg_ack     => cfg_acks(0),
            clk         => rx_clk,
            reset_p     => rx_reset_i);

        -- Input parsing to identify PTP message fields.
        -- Use the post-VLAN data stream to handle nested VLAN+PTP messages
        -- and match byte offsets needed in "ptp_adjust" and "ptp_egress".
        u_ingress : entity work.ptp_ingress
            generic map(
            IO_BYTES    => INPUT_BYTES,
            TLV_ID0     => tlvtype_if(TLVTYPE_DOPPLER, PTP_DOPPLER))
            port map(
            in_data     => vlan_data,
            in_nlast    => vlan_nlast,
            in_write    => vlan_write,
            out_pmsg    => rx_meta.pmsg,
            out_tlv0    => rx_meta.pfreq,
            out_valid   => pkt_valid2,
            out_ready   => pkt_final,
            clk         => rx_clk,
            reset_p     => rx_reset_i);

        -- Fixed pipeline delay for the output data stream.
        -- (Must meet or exceed worst-case "ptp_ingress" delay.)
        u_delay : entity work.packet_delay
            generic map(
            IO_BYTES    => INPUT_BYTES,
            DELAY_COUNT => 4)
            port map(
            in_data     => vlan_data,
            in_nlast    => vlan_nlast,
            in_write    => vlan_write,
            in_result   => vlan_result,
            out_data    => ptp_data,
            out_nlast   => ptp_nlast,
            out_write   => ptp_write,
            out_result  => ptp_result,
            io_clk      => rx_clk,
            reset_p     => rx_reset_i);

        -- Generate an error strobe if metadata arrives too late.
        ptp_error <= pkt_final and not (pkt_valid1 and pkt_valid2);
    end block;
end generate;

gen_ptp0 : if not SUPPORT_PTP generate
    ptp_data    <= vlan_data;
    ptp_nlast   <= vlan_nlast;
    ptp_write   <= vlan_write;
    ptp_result  <= vlan_result;
    ptp_error   <= '0';
end generate;

-- End-of-frame strobe.
pkt_final <= ptp_write and (ptp_result.commit or ptp_result.revert);
pkt_error <= (vlan_write and vlan_result.error) or (ptp_error);

-- Metadata format conversion.
-- Note: Relying on synthesis tools to trim unused metadata fields.
out_meta <= switch_v2m(mvec_out);
mvec_in  <= switch_m2v(rx_meta);

-- Instantiate this port's input FIFO.
u_fifo : entity work.fifo_packet
    generic map(
    INPUT_BYTES     => INPUT_BYTES,
    OUTPUT_BYTES    => OUTPUT_BYTES,
    BUFFER_KBYTES   => IBUF_KBYTES,
    META_WIDTH      => SWITCH_META_WIDTH,
    FLUSH_TIMEOUT   => FLUSH_TIMEOUT,
    MAX_PACKETS     => IBUF_PACKETS,
    MAX_PKT_BYTES   => get_max_frame)
    port map(
    in_clk          => rx_clk,
    in_pkt_meta     => mvec_in,
    in_data         => ptp_data,
    in_nlast        => ptp_nlast,
    in_last_commit  => ptp_result.commit,
    in_last_revert  => ptp_result.revert,
    in_write        => ptp_write,
    in_overflow     => rx_overflow,
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

-- Optional diagnostic logging, just before the FIFO input.
gen_log1 : if SUPPORT_LOG generate
    u_log : entity work.eth_frame_log
        generic map(
        INPUT_BYTES => INPUT_BYTES,
        FILTER_MODE => true,    -- Dropped packets only
        OUT_BUFFER  => true)    -- Double-buffer required
        port map(
        in_data     => ptp_data,
        in_meta     => rx_meta,
        in_nlast    => ptp_nlast,
        in_result   => ptp_result,
        in_write    => ptp_write,
        ovr_strobe  => rx_overflow,
        out_data    => err_log_data,
        out_toggle  => log_toggle,
        clk         => rx_clk,
        reset_p     => rx_reset_i);

    u_log_hs : sync_toggle2pulse
        port map(
        in_toggle   => log_toggle,
        out_strobe  => err_log_write,
        out_clk     => core_clk);
end generate;

gen_log0 : if not SUPPORT_LOG generate
    err_log_data    <= LOG_META_NULL;
    err_log_write   <= '0';
end generate;

-- Detect error strobes from MII Rx.
u_err : sync_toggle2pulse
    generic map(RISING_ONLY => true)
    port map(
    in_toggle   => rx_macerr,
    out_strobe  => err_rxmac,
    out_clk     => core_clk);
u_pkt : sync_pulse2pulse
    port map(
    in_strobe   => pkt_error,
    in_clk      => rx_clk,
    out_strobe  => err_badfrm,
    out_clk     => core_clk);

-- Combine ConfigBus replies.
cfg_ack <= cfgbus_merge(cfg_acks);

end switch_port_rx;
