--------------------------------------------------------------------------
-- Copyright 2020-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Inline injection of keep-alive or status packets
--
-- This block can be dropped inline with any other port type to inject
-- simple fixed-format message frames.  The messages can be sent at
-- regular intervals or on-demand, and can be used for simple status
-- updates, keep-alive heartbeats, MAC-address propagation, etc.
--
-- Frames are generated using "config_send_status" and injected during
-- idle time on the egress and/or ingress link(s).
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity port_inline_status is
    generic (
    SEND_EGRESS     : boolean;          -- Send to external network port?
    SEND_INGRESS    : boolean;          -- Send to internal switch port?
    MSG_BYTES       : natural := 0;     -- Bytes per status message (0 = none)
    MSG_ETYPE       : mac_type_t := x"5C00";
    MAC_DEST        : mac_addr_t := x"FFFFFFFFFFFF";
    MAC_SOURCE      : mac_addr_t := x"5A5ADEADBEEF";
    AUTO_DELAY_CLKS : natural := 0;     -- Send every N clocks, or 0 for on-demand
    MIN_FRAME_BYTES : natural := 0);    -- Pad to minimum frame size?
    port (
    -- Internal switch port.
    lcl_rx_data     : out port_rx_m2s;  -- Ingress data out
    lcl_tx_data     : in  port_tx_s2m;  -- Egress data in
    lcl_tx_ctrl     : out port_tx_m2s;

    -- External network port.
    net_rx_data     : in  port_rx_m2s;  -- Ingress data in
    net_tx_data     : out port_tx_s2m;  -- Egress data out
    net_tx_ctrl     : in  port_tx_m2s;

    -- Optional status message and write-toggle.
    status_val      : in  std_logic_vector(8*MSG_BYTES-1 downto 0) := (others => '0');
    status_wr_t     : in  std_logic := '0');
end port_inline_status;

architecture port_inline_status of port_inline_status is

subtype tstamp_v is std_logic_vector(TSTAMP_WIDTH-1 downto 0);

-- Calculate required ingress FIFO size:
-- (+3 is minimum safe margin for packet_inject block.)
constant IG_FRM_SIZE    : integer := int_max(
    MIN_FRAME_BYTES, HEADER_CRC_BYTES + MSG_BYTES);
constant IG_FIFO_DEPTH  : integer := 2**log2_ceil(IG_FRM_SIZE + 3);

-- Egress datapath
signal eg_clk       : std_logic;
signal eg_reset_p   : std_logic;
signal eg_wr_status : std_logic;
signal eg_status    : axi_stream8;
signal eg_in_strm   : axi_stream8;
signal eg_out_strm  : axi_stream8;
signal eg_err_inj   : std_logic := '0';

-- Ingress datapath
signal ig_clk       : std_logic;
signal ig_reset_p   : std_logic;
signal ig_wr_status : std_logic;
signal ig_status    : axi_stream8;
signal ig_in_data   : byte_t;
signal ig_in_last   : std_logic;
signal ig_in_write  : std_logic;
signal ig_in_tsof   : tstamp_v;
signal ig_mid_strm  : axi_stream8;
signal ig_mid_tsof  : tstamp_v;
signal ig_out_strm  : axi_stream8;
signal ig_out_tsof  : tstamp_v;
signal ig_err_fifo  : std_logic := '0';
signal ig_err_inj   : std_logic := '0';

begin

-- Break out the port signals:
lcl_rx_data.clk     <= ig_clk;
lcl_rx_data.data    <= ig_out_strm.data;
lcl_rx_data.last    <= ig_out_strm.last;
lcl_rx_data.write   <= ig_out_strm.valid;
ig_out_strm.ready   <= '1';
lcl_rx_data.tsof    <= unsigned(ig_out_tsof);
lcl_rx_data.rxerr   <= net_rx_data.rxerr or ig_err_fifo or ig_err_inj;
lcl_rx_data.rate    <= net_rx_data.rate;
lcl_rx_data.status  <= net_rx_data.status;
lcl_rx_data.reset_p <= ig_reset_p;

lcl_tx_ctrl.clk     <= eg_clk;
lcl_tx_ctrl.pstart  <= net_tx_ctrl.pstart and eg_in_strm.ready;
lcl_tx_ctrl.tnow    <= net_tx_ctrl.tnow;
lcl_tx_ctrl.txerr   <= net_tx_ctrl.txerr or eg_err_inj;
lcl_tx_ctrl.reset_p <= eg_reset_p;
eg_in_strm.data     <= lcl_tx_data.data;
eg_in_strm.last     <= lcl_tx_data.last;
eg_in_strm.valid    <= lcl_tx_data.valid;
lcl_tx_ctrl.ready   <= eg_in_strm.ready;

ig_clk              <= net_rx_data.clk;
ig_reset_p          <= net_rx_data.reset_p;
ig_in_tsof          <= std_logic_vector(net_rx_data.tsof);
ig_in_data          <= net_rx_data.data;
ig_in_last          <= net_rx_data.last;
ig_in_write         <= net_rx_data.write;

eg_clk              <= net_tx_ctrl.clk;
eg_reset_p          <= net_tx_ctrl.reset_p;
net_tx_data.data    <= eg_out_strm.data;
net_tx_data.last    <= eg_out_strm.last;
net_tx_data.valid   <= eg_out_strm.valid;
eg_out_strm.ready   <= net_tx_ctrl.ready;

-- Clock-domain transition for the status-write toggle.
u_sync_eg : sync_toggle2pulse
    port map(
    in_toggle   => status_wr_t,
    out_strobe  => eg_wr_status,
    out_clk     => eg_clk,
    reset_p     => eg_reset_p);

u_sync_ig : sync_toggle2pulse
    port map(
    in_toggle   => status_wr_t,
    out_strobe  => ig_wr_status,
    out_clk     => ig_clk,
    reset_p     => ig_reset_p);

-- Egress datapath (or bypass):
eg_bypass : if not SEND_EGRESS generate
    eg_status           <= AXI_STREAM8_IDLE;
    eg_out_strm.data    <= eg_in_strm.data;
    eg_out_strm.last    <= eg_in_strm.last;
    eg_out_strm.valid   <= eg_in_strm.valid;
    eg_in_strm.ready    <= eg_out_strm.ready;
end generate;

eg_inject : if SEND_EGRESS generate
    -- Packet generator block:
    u_status : entity work.config_send_status
        generic map(
        MSG_BYTES       => MSG_BYTES,
        MSG_ETYPE       => MSG_ETYPE,
        MAC_DEST        => MAC_DEST,
        MAC_SOURCE      => MAC_SOURCE,
        AUTO_DELAY_CLKS => AUTO_DELAY_CLKS,
        MIN_FRAME_BYTES => MIN_FRAME_BYTES)
        port map(
        status_val      => status_val,
        status_wr       => eg_wr_status,
        out_data        => eg_status.data,
        out_last        => eg_status.last,
        out_valid       => eg_status.valid,
        out_ready       => eg_status.ready,
        clk             => eg_clk,
        reset_p         => eg_reset_p);

    -- Packet injection (lower-numbered input gets priority):
    u_inject : entity work.packet_inject
        generic map(
        INPUT_COUNT     => 2,
        APPEND_FCS      => false,
        RULE_PRI_CONTIG => false)
        port map(
        in0_data        => eg_in_strm.data,
        in1_data        => eg_status.data,
        in_last(0)      => eg_in_strm.last,
        in_last(1)      => eg_status.last,
        in_valid(0)     => eg_in_strm.valid,
        in_valid(1)     => eg_status.valid,
        in_ready(0)     => eg_in_strm.ready,
        in_ready(1)     => eg_status.ready,
        in_error        => eg_err_inj,
        out_data        => eg_out_strm.data,
        out_last        => eg_out_strm.last,
        out_valid       => eg_out_strm.valid,
        out_ready       => eg_out_strm.ready,
        out_aux         => open,
        clk             => eg_clk,
        reset_p         => eg_reset_p);
end generate;

-- Ingress datapath (or bypass):
ig_bypass : if not SEND_INGRESS generate
    ig_status           <= AXI_STREAM8_IDLE;
    ig_out_tsof         <= ig_in_tsof;
    ig_out_strm.data    <= ig_in_data;
    ig_out_strm.last    <= ig_in_last;
    ig_out_strm.valid   <= ig_in_write;
end generate;

ig_inject : if SEND_INGRESS generate
    -- Small FIFO for buffering received data.
    -- (No flow control back-pressure on the ingress input.)
    u_fifo : entity work.fifo_large_sync
        generic map(
        META_WIDTH      => TSTAMP_WIDTH,
        FIFO_WIDTH      => 8,
        FIFO_DEPTH      => IG_FIFO_DEPTH)
        port map(
        in_meta         => ig_in_tsof,
        in_data         => ig_in_data,
        in_last         => ig_in_last,
        in_write        => ig_in_write,
        in_error        => ig_err_fifo,
        out_meta        => ig_mid_tsof,
        out_data        => ig_mid_strm.data,
        out_last        => ig_mid_strm.last,
        out_valid       => ig_mid_strm.valid,
        out_ready       => ig_mid_strm.ready,
        clk             => ig_clk,
        reset_p         => ig_reset_p);

    -- Packet generator block:
    u_status : entity work.config_send_status
        generic map(
        MSG_BYTES       => MSG_BYTES,
        MSG_ETYPE       => MSG_ETYPE,
        MAC_DEST        => MAC_DEST,
        MAC_SOURCE      => MAC_SOURCE,
        AUTO_DELAY_CLKS => AUTO_DELAY_CLKS,
        MIN_FRAME_BYTES => MIN_FRAME_BYTES)
        port map(
        status_val      => status_val,
        status_wr       => ig_wr_status,
        out_data        => ig_status.data,
        out_last        => ig_status.last,
        out_valid       => ig_status.valid,
        out_ready       => ig_status.ready,
        clk             => ig_clk,
        reset_p         => ig_reset_p);

    -- Packet injection (lower-numbered input gets priority):
    u_inject : entity work.packet_inject
        generic map(
        INPUT_COUNT     => 2,
        META_WIDTH      => TSTAMP_WIDTH,
        APPEND_FCS      => false,
        RULE_PRI_CONTIG => false)
        port map(
        in0_meta        => ig_mid_tsof,
        in1_meta        => (others => '0'),
        in0_data        => ig_mid_strm.data,
        in1_data        => ig_status.data,
        in_last(0)      => ig_mid_strm.last,
        in_last(1)      => ig_status.last,
        in_valid(0)     => ig_mid_strm.valid,
        in_valid(1)     => ig_status.valid,
        in_ready(0)     => ig_mid_strm.ready,
        in_ready(1)     => ig_status.ready,
        in_error        => ig_err_inj,
        out_meta        => ig_out_tsof,
        out_data        => ig_out_strm.data,
        out_last        => ig_out_strm.last,
        out_valid       => ig_out_strm.valid,
        out_ready       => ig_out_strm.ready,
        out_aux         => open,
        clk             => ig_clk,
        reset_p         => ig_reset_p);
end generate;

end port_inline_status;
