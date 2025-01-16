--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Hardware/software interface for hybrid hardware/software routers
--
-- The "router2" system uses a combination of gateware and software.
-- Routine forwarding is defined in VHDL to provide the throughput, but
-- more complex or time-delayed operations are offloaded to software.
-- This block provides that offload function, applying the forward/offload
-- decisions made by the upstream "router2_gateway" block.
--
-- The memory-mapped I/O function is performed by "router2_mailmap", which
-- is instantiated inside this block.  ConfigBus register documentation is
-- provided in that file.
--
-- The offload interface requires three main steps:
--  * If the offload flag is enabled, copy incoming data to the mailmap port.
--    Note: Data may be forwarded to offload and regular ports concurrently.
--  * Apply packet-forwarding updates to IPv4 header fields (router2_forward).
--    To avoid accidental duplication, offloaded packets skip this step.
--  * If the output is idle, read outgoing data from the offload port.
--
-- All input and output streams contain Ethernet frames with no FCS and
-- no VLAN tags.  Output metadata is available from start-of-frame.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.router_common.all;
use     work.switch_types.all;

entity router2_offload is
    generic (
    DEVADDR     : integer;              -- ConfigBus address
    IO_BYTES    : positive;             -- Width of datapath
    PORT_COUNT  : positive;             -- Number of ports
    VLAN_ENABLE : boolean := false;     -- Enable VLAN support?
    IBUF_KBYTES : positive := 2;        -- Input buffer size in kilobytes
    OBUF_KBYTES : positive := 2;        -- Output buffer size in kilobytes
    BIG_ENDIAN  : boolean := false);    -- Byte order of ConfigBus host
    port (
    -- Input stream with AXI-stream flow control.
    -- (Offload port is indicated by MSB of in_pmask.)
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_nlast    : in  integer range 0 to IO_BYTES;
    in_valid    : in  std_logic;
    in_ready    : out std_logic;
    in_dstmac   : in  mac_addr_t;
    in_srcmac   : in  mac_addr_t;
    in_pdst     : in  std_logic_vector(PORT_COUNT downto 0);
    in_psrc     : in  integer range 0 to PORT_COUNT-1;
    in_meta     : in  switch_meta_t;

    -- Output stream with AXI-stream flow control.
    out_data    : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_nlast   : out integer range 0 to IO_BYTES;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;
    out_pdst    : out std_logic_vector(PORT_COUNT-1 downto 0);
    out_psrc    : out integer range 0 to PORT_COUNT;
    out_meta    : out switch_meta_t;

    -- ConfigBus interface
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack;

    -- System clock and reset.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end router2_offload;

architecture router2_offload of router2_offload is

-- Concatenated destination-mask + metadata.
constant PIDX_WIDTH : integer := log2_ceil(PORT_COUNT + 1);
constant META_TOTAL : integer := PIDX_WIDTH + PORT_COUNT + SWITCH_META_WIDTH;

-- Upstream flow-control.
signal in_ready_i   : std_logic;
signal in_write     : std_logic;

-- One-word input buffer.
signal buf_data     : std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
signal buf_nlast    : integer range 0 to IO_BYTES := 0;
signal buf_valid    : std_logic := '0';
signal buf_ready    : std_logic;
signal buf_dstmac   : mac_addr_t := (others => '0');
signal buf_srcmac   : mac_addr_t := (others => '0');
signal buf_offwr    : std_logic := '0';
signal buf_commit   : std_logic := '0';
signal buf_psrc     : integer range 0 to PORT_COUNT-1 := 0;
signal buf_vtag     : vlan_hdr_t := (others => '0');
signal buf_mvec     : std_logic_vector(META_TOTAL-1 downto 0) := (others => '0');

-- Forward datapath.
signal fwd_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal fwd_mvec     : std_logic_vector(META_TOTAL-1 downto 0);
signal fwd_nlast    : integer range 0 to IO_BYTES;
signal fwd_valid    : std_logic;
signal fwd_ready    : std_logic;

-- Offload interface.
signal aux_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal aux_pdst     : std_logic_vector(PORT_COUNT-1 downto 0);
signal aux_vtag     : vlan_hdr_t;
signal aux_meta     : switch_meta_t;
signal aux_mvec     : std_logic_vector(META_TOTAL-1 downto 0);
signal aux_nlast    : integer range 0 to IO_BYTES;
signal aux_valid    : std_logic;
signal aux_ready    : std_logic;

-- Output conversion.
signal out_mvec     : std_logic_vector(META_TOTAL-1 downto 0);

begin

-- Upstream flow-control.
in_ready    <= in_ready_i;
in_ready_i  <= buf_ready or not buf_valid;
in_write    <= in_valid and in_ready_i;

-- One-word input buffer diverts input to forward/offload/both paths.
p_buf : process(clk)
begin
    if rising_edge(clk) then
        -- Valid strobe for the forward datapath.
        if (reset_p = '1') then
            buf_valid <= '0';
        elsif (in_write = '1') then
            buf_valid <= or_reduce(in_pdst(PORT_COUNT-1 downto 0));
        elsif (buf_ready = '1') then
            buf_valid <= '0';
        end if;

        -- Write and commit strobes for the offload datapath.
        buf_offwr   <= in_write and in_pdst(PORT_COUNT);
        buf_commit  <= in_write and in_pdst(PORT_COUNT) and bool2bit(in_nlast > 0);

        -- Buffer all data and concatenated metadata.
        if (in_write = '1') then
            buf_data    <= in_data;
            buf_nlast   <= in_nlast;
            buf_dstmac  <= in_dstmac;
            buf_srcmac  <= in_srcmac;
            buf_psrc    <= in_psrc;
            buf_vtag    <= in_meta.vtag;
            buf_mvec    <= i2s(in_psrc, PIDX_WIDTH)
                & in_pdst(PORT_COUNT-1 downto 0)
                & switch_m2v(in_meta);
        end if;
    end if;
end process;

-- Forward datapath.
p_fwd : entity work.router2_forward
    generic map(
    IO_BYTES    => IO_BYTES,
    META_WIDTH  => META_TOTAL)
    port map(
    in_data     => buf_data,
    in_meta     => buf_mvec,
    in_nlast    => buf_nlast,
    in_valid    => buf_valid,
    in_ready    => buf_ready,
    in_dstmac   => buf_dstmac,
    in_srcmac   => buf_srcmac,
    out_data    => fwd_data,
    out_meta    => fwd_mvec,
    out_nlast   => fwd_nlast,
    out_valid   => fwd_valid,
    out_ready   => fwd_ready,
    clk         => clk,
    reset_p     => reset_p);

-- Offload interface.
u_aux : entity work.router2_mailmap
    generic map(
    DEVADDR     => DEVADDR,
    IO_BYTES    => IO_BYTES,
    PORT_COUNT  => PORT_COUNT,
    VLAN_ENABLE => VLAN_ENABLE,
    IBUF_KBYTES => IBUF_KBYTES,
    OBUF_KBYTES => OBUF_KBYTES,
    BIG_ENDIAN  => BIG_ENDIAN)
    port map(
    rx_clk      => clk,
    rx_data     => buf_data,
    rx_nlast    => buf_nlast,
    rx_psrc     => buf_psrc,
    rx_vtag     => buf_vtag,
    rx_write    => buf_offwr,
    rx_commit   => buf_commit,
    rx_revert   => '0',
    tx_clk      => clk,
    tx_data     => aux_data,
    tx_nlast    => aux_nlast,
    tx_valid    => aux_valid,
    tx_ready    => aux_ready,
    tx_keep     => aux_pdst,
    tx_vtag     => aux_vtag,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack);

-- For now, the offload port only supports VLAN metadata.
-- TODO: Do we need PTP support on the offload port?
aux_meta <= (TLVPOS_NONE, TLVPOS_NONE, TSTAMP_DISABLED, TFREQ_DISABLED, aux_vtag);
aux_mvec <= i2s(PORT_COUNT, PIDX_WIDTH) & aux_pdst & switch_m2v(aux_meta);

-- Multiplex between the foward and offload outputs.
-- (Packet-inject block only changes inputs at packet boundaries.)
u_mux : entity work.packet_inject
    generic map(
    INPUT_COUNT => 2,
    IO_BYTES    => IO_BYTES,
    META_WIDTH  => META_TOTAL,
    APPEND_FCS  => false)
    port map(
    in0_data    => fwd_data,
    in1_data    => aux_data,
    in0_nlast   => fwd_nlast,
    in1_nlast   => aux_nlast,
    in0_meta    => fwd_mvec,
    in1_meta    => aux_mvec,
    in_valid(0) => fwd_valid,
    in_valid(1) => aux_valid,
    in_ready(0) => fwd_ready,
    in_ready(1) => aux_ready,
    in_error    => open,
    out_data    => out_data,
    out_meta    => out_mvec,
    out_nlast   => out_nlast,
    out_valid   => out_valid,
    out_ready   => out_ready,
    out_aux     => open,
    clk         => clk,
    reset_p     => reset_p);

out_psrc <= u2i(out_mvec(META_TOTAL-1 downto META_TOTAL-PIDX_WIDTH));
out_pdst <= out_mvec(SWITCH_META_WIDTH+PORT_COUNT-1 downto SWITCH_META_WIDTH);
out_meta <= switch_v2m(out_mvec(SWITCH_META_WIDTH-1 downto 0));

end router2_offload;
