--------------------------------------------------------------------------
-- Copyright 2024-2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Shared pipeline for the IPv4 router
--
-- This block is the high-bandwidth pipeline at the heart of "router2_core",
-- providing the IPv4 gateway and forwarding logic that is shared by all
-- router ports.  It is used in conjunction with per-port ingress and egress
-- logic, plus the router's "offload" software, which is required to handle
-- various rare-but-complex packet-forwarding tasks.
--
-- The input is a stream of Ethernet frames without the FCS field, plus
-- various metadata for PTP, etc.  The width of this port can be as narrow
-- as 1 byte per clock, or as wide as needed to support a given throughput.
-- The output is a modified stream, plus per-port "keep" strobes indicating
-- which port(s), if any, should accept each output frame.
--
-- Unit-test coverage for this block is provided by "router2_core_tb".
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.router2_common.all;
use     work.switch_types.all;
use     work.tcam_constants.all;

entity router2_pipeline is
    generic (
    DEV_ADDR        : integer;          -- Device address for all registers
    IO_BYTES        : positive;         -- Width of main data ports
    OVR_DELAY       : positive;         -- Delay from out_write to out_overflow
    PORT_COUNT      : positive;         -- Number of Ethernet ports
    TABLE_SIZE      : positive;         -- Size of the CIDR routing table
    CORE_CLK_HZ     : positive;         -- Core clock frequency (Hz)
    PTP_DOPPLER     : boolean;          -- Enable Doppler-TLV tags?
    PTP_MIXED_STEP  : boolean;          -- Support PTP format conversion?
    PTP_STRICT      : boolean;          -- Drop frames with missing timestamps?
    SUPPORT_LOG     : boolean;          -- Support packet logging diagnostics?
    SUPPORT_PTP     : boolean;          -- Support Precision Time Protocol?
    SUPPORT_VPORT   : boolean;          -- Support virtual-LAN port control?
    SUPPORT_VRATE   : boolean;          -- Support virtual-LAN rate control?
    DEBUG_VERBOSE   : boolean := false);-- Enable simulation logs?
    port (
    -- Main input
    -- PSRC is the input port-index and must be held for the full frame.
    in_psrc         : in  integer range 0 to PORT_COUNT-1;
    in_data         : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_meta         : in  switch_meta_t;
    in_nlast        : in  integer range 0 to IO_BYTES;
    in_valid        : in  std_logic;
    in_ready        : out std_logic;

    -- Optional packet logging metadata.
    log_data        : out log_meta_t;
    log_psrc        : out integer range 0 to PORT_COUNT-1;
    log_dmask       : out std_logic_vector(PORT_COUNT-1 downto 0);
    log_write       : out std_logic;

    -- Main output, with end-of-frame strobes for each port.
    out_data        : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_meta        : out switch_meta_t;
    out_nlast       : out integer range 0 to IO_BYTES;
    out_write       : out std_logic;
    out_priority    : out std_logic;
    out_keep        : out std_logic_vector(PORT_COUNT-1 downto 0);
    out_overflow    : in  std_logic_vector(PORT_COUNT-1 downto 0);

    -- Configuration interface
    cfg_cmd         : in  cfgbus_cmd := CFGBUS_CMD_NULL;
    cfg_ack         : out cfgbus_ack;   -- Optional ConfigBus interface
    port_2step      : out std_logic_vector(PORT_COUNT-1 downto 0);
    queue_state     : in  unsigned(8*PORT_COUNT-1 downto 0);
    error_table     : out std_logic;    -- Table integrity check failed
    error_ptp       : out std_logic_vector(PORT_COUNT-1 downto 0);

    -- System interface
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end router2_pipeline;

architecture router2_pipeline of router2_pipeline is

-- Convenience types:
-- Note: Many blocks use PORT_COUNT+1 to account for the offload port.
constant META_WIDTH : integer := PORT_COUNT + SWITCH_META_WIDTH;
subtype data_word is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype port_mask0 is std_logic_vector(PORT_COUNT-1 downto 0);
subtype port_mask1 is std_logic_vector(PORT_COUNT downto 0);
subtype last_idx_t is integer range 0 to IO_BYTES;
subtype port_idx_t is integer range 0 to PORT_COUNT;
constant MASK0_NONE : port_mask0 := (others => '0');
constant MASK1_NONE : port_mask1 := (others => '0');

-- Main datapath
signal gate_data    : data_word;
signal gate_nlast   : last_idx_t;
signal gate_valid   : std_logic;
signal gate_ready   : std_logic;
signal gate_dstmac  : mac_addr_t;
signal gate_srcmac  : mac_addr_t;
signal gate_pdst    : port_mask1;
signal gate_psrc    : port_idx_t;
signal gate_meta    : switch_meta_t;

signal fwd_data     : data_word;
signal fwd_nlast    : last_idx_t;
signal fwd_valid    : std_logic;
signal fwd_ready    : std_logic;
signal fwd_pdst0    : port_mask0;
signal fwd_pdst1    : port_mask1;
signal fwd_psrc     : port_idx_t;
signal fwd_meta     : switch_meta_t;

signal ptp_data     : data_word;
signal ptp_nlast    : last_idx_t;
signal ptp_last     : std_logic;
signal ptp_write    : std_logic;
signal ptp_pdst     : port_mask1;
signal ptp_psrc     : port_idx_t;
signal ptp_meta     : switch_meta_t;
signal ptp_psrc_v   : byte_t;

signal qstate_pad   : unsigned(8*PORT_COUNT+7 downto 0);
signal qsel_data    : data_word;
signal qsel_pdst    : port_mask0;
signal qsel_nlast   : last_idx_t;
signal qsel_write   : std_logic;
signal qsel_qdepth  : unsigned(7 downto 0);

signal ecn_data     : data_word;
signal ecn_nlast    : last_idx_t;
signal ecn_drop     : std_logic;
signal ecn_pdst     : port_mask0;
signal ecn_pmod     : port_mask0;
signal ecn_write    : std_logic;

signal chk_data     : data_word;
signal chk_nlast    : last_idx_t;
signal chk_write    : std_logic;
signal chk_pdst     : port_mask0;
signal chk_keep     : port_mask0;
signal chk_result   : frm_result_t;
signal chk_meta     : switch_meta_t;

signal ovr_dmask    : port_mask0 := (others => '0');
signal ovr_strobe   : std_logic := '0';
signal packet_done  : std_logic;

-- PTP routing and timestamps (optional)
signal ptpf_mask0   : port_mask0 := (others => '1');
signal ptpf_mask1   : port_mask1 := (others => '1');
signal ptpf_meta    : switch_meta_t := SWITCH_META_NULL;
signal ptpf_psrc    : port_idx_t := 0;
signal ptpf_valid   : std_logic := '1';
signal error_ptp_i  : port_mask1 := (others => '0');

-- VLAN lookup (optional)
signal vport_mask   : port_mask0 := (others => '1');
signal vport_vtag   : vlan_hdr_t := (others => '0');
signal vport_hipri  : std_logic := '0';
signal vport_valid  : std_logic := '1';
signal vrate_mask   : port_mask0 := (others => '1');
signal vrate_allow  : std_logic := '1';
signal vrate_valid  : std_logic := '1';

-- Per-port configuration masks.
-- (Each one is effectively a constant if ConfigBus is disabled.)
signal cfg_shdnword : cfgbus_word := (others => '0');
signal cfg_shdnmask : port_mask0  := (others => '0');
signal cfg_stpword  : cfgbus_word := (others => '0');
signal cfg_stpmask  : port_mask0  := (others => '0');

-- ConfigBus combining.
signal cfg_acks     : cfgbus_ack_array(0 to 11) := (others => cfgbus_idle);

begin

-- Read-only configuration reporting.
-- See "router2_common" for complete register map.
u_portcount : cfgbus_readonly
    generic map(
    DEVADDR     => DEV_ADDR,
    REGADDR     => RT_ADDR_PORT_COUNT)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(0),
    reg_val     => i2s(PORT_COUNT, CFGBUS_WORD_SIZE));
u_datawidth : cfgbus_readonly
    generic map(
    DEVADDR     => DEV_ADDR,
    REGADDR     => RT_ADDR_DATA_WIDTH)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(1),
    reg_val     => i2s(8*IO_BYTES, CFGBUS_WORD_SIZE));
u_coreclock : cfgbus_readonly
    generic map(
    DEVADDR     => DEV_ADDR,
    REGADDR     => RT_ADDR_CORE_CLOCK)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(2),
    reg_val     => i2s(CORE_CLK_HZ, CFGBUS_WORD_SIZE));
u_mactable : cfgbus_readonly
    generic map(
    DEVADDR     => DEV_ADDR,
    REGADDR     => RT_ADDR_TABLE_SIZE)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(3),
    reg_val     => i2s(TABLE_SIZE, CFGBUS_WORD_SIZE));

-- Per-port shutdown register.
u_shdn : cfgbus_register
    generic map(
    DEVADDR     => DEV_ADDR,
    REGADDR     => RT_ADDR_PORT_SHDN,
    WR_ATOMIC   => true,
    WR_MASK     => cfgbus_mask_lsb(PORT_COUNT))
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(4),
    reg_val     => cfg_shdnword);

cfg_shdnmask <= resize(cfg_shdnword, PORT_COUNT);

-- Optional: Two-step register for PTP format conversion.
gen_2step : if (SUPPORT_PTP and PTP_MIXED_STEP) generate
    u_register : cfgbus_register
        generic map(
        DEVADDR     => DEV_ADDR,
        REGADDR     => RT_ADDR_PTP_2STEP,
        WR_ATOMIC   => true,
        WR_MASK     => cfgbus_mask_lsb(PORT_COUNT))
        port map(
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(5),
        reg_val     => cfg_stpword);

    cfg_stpmask <= resize(cfg_stpword, PORT_COUNT);
end generate;

-- IPv4 gateway and packet-routing logic.
-- Note: This block makes decisions but doesn't update packet contents.
u_gateway : entity work.router2_gateway
    generic map(
    DEVADDR     => DEV_ADDR,
    IO_BYTES    => IO_BYTES,
    PORT_COUNT  => PORT_COUNT,
    TABLE_SIZE  => TABLE_SIZE,
    VERBOSE     => DEBUG_VERBOSE)
    port map(
    in_data     => in_data,
    in_nlast    => in_nlast,
    in_valid    => in_valid,
    in_ready    => in_ready,
    in_psrc     => in_psrc,
    in_meta     => in_meta,
    out_data    => gate_data,
    out_nlast   => gate_nlast,
    out_valid   => gate_valid,
    out_ready   => gate_ready,
    out_dstmac  => gate_dstmac,
    out_srcmac  => gate_srcmac,
    out_pdst    => gate_pdst,
    out_psrc    => gate_psrc,
    out_meta    => gate_meta,
    tcam_error  => error_table,
    port_shdn   => cfg_shdnmask,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(6),
    clk         => clk,
    reset_p     => reset_p);

-- Packet forwarding and software-offload interface.
-- Note: CPU offload may insert or delete frames.
u_offload : entity work.router2_offload
    generic map(
    DEVADDR     => DEV_ADDR,
    IO_BYTES    => IO_BYTES,
    PORT_COUNT  => PORT_COUNT,
    VLAN_ENABLE => SUPPORT_VPORT or SUPPORT_VRATE,
    BIG_ENDIAN  => false)
    port map(
    in_data     => gate_data,
    in_nlast    => gate_nlast,
    in_valid    => gate_valid,
    in_ready    => gate_ready,
    in_dstmac   => gate_dstmac,
    in_srcmac   => gate_srcmac,
    in_pdst     => gate_pdst,
    in_psrc     => gate_psrc,
    in_meta     => gate_meta,
    out_data    => fwd_data,
    out_nlast   => fwd_nlast,
    out_valid   => fwd_valid,
    out_ready   => fwd_ready,
    out_pdst    => fwd_pdst0,
    out_psrc    => fwd_psrc,
    out_meta    => fwd_meta,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(7),
    clk         => clk,
    reset_p     => reset_p);

fwd_pdst1 <= '0' & fwd_pdst0;

-- Inline metadata updates and other processing for PTP.
-- Note: This block may insert new frames for two-step conversion.
-- Note: Use PORT_COUNT + 1 to account for the offload port.
gen_ptp1 : if SUPPORT_PTP generate
    u_ptp : entity work.ptp_adjust
        generic map(
        IO_BYTES    => IO_BYTES,
        PORT_COUNT  => PORT_COUNT+1,
        PTP_DOPPLER => PTP_DOPPLER,
        PTP_STRICT  => PTP_STRICT,
        MIXED_STEP  => PTP_MIXED_STEP)
        port map(
        in_meta     => fwd_meta,
        in_pdst     => fwd_pdst1,
        in_psrc     => fwd_psrc,
        in_data     => fwd_data,
        in_nlast    => fwd_nlast,
        in_valid    => fwd_valid,
        in_ready    => fwd_ready,
        out_meta    => ptp_meta,
        out_pdst    => ptp_pdst,
        out_psrc    => ptp_psrc,
        out_data    => ptp_data,
        out_nlast   => ptp_nlast,
        out_valid   => ptp_write,
        out_ready   => '1',
        cfg_2step   => cfg_stpmask,
        frm_pmask   => ptpf_mask1,
        frm_meta    => ptpf_meta,
        frm_psrc    => ptpf_psrc,
        frm_valid   => ptpf_valid,
        frm_ready   => packet_done,
        error_mask  => error_ptp_i,
        clk         => clk,
        reset_p     => reset_p);
end generate;

gen_ptp0 : if not SUPPORT_PTP generate
    ptp_meta    <= fwd_meta;
    ptp_pdst    <= fwd_pdst1;
    ptp_psrc    <= fwd_psrc;
    ptp_data    <= fwd_data;
    ptp_nlast   <= fwd_nlast;
    ptp_write   <= fwd_valid;
    fwd_ready   <= '1';
end generate;

ptp_last    <= bool2bit(ptp_nlast > 0);
ptp_psrc_v  <= i2s(ptp_psrc, 8);
ptpf_mask0  <= ptpf_mask1(PORT_COUNT-1 downto 0);

-----------------------------------------------------------
-- Note: Blocks below this point cannot apply flow-control
-- backpressure and must not insert or delete packets.
-----------------------------------------------------------

-- Virtual-LAN lookup (optional)
-- Note: VLAN blocks store per-packet metadata in a FIFO,
--  but they do not affect the main data pipeline.
gen_vport : if SUPPORT_VPORT generate
    u_vport : entity work.mac_vlan_mask
        generic map(
        DEV_ADDR    => DEV_ADDR,
        REG_ADDR_V  => RT_ADDR_VLAN_VID,
        REG_ADDR_M  => RT_ADDR_VLAN_MASK,
        PORT_COUNT  => PORT_COUNT+1)
        port map(
        in_psrc     => ptp_psrc,
        in_vtag     => ptp_meta.vtag,
        in_last     => ptp_last,
        in_write    => ptp_write,
        out_vtag    => vport_vtag,
        out_pmask   => vport_mask,
        out_hipri   => vport_hipri,
        out_valid   => vport_valid,
        out_ready   => packet_done,
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(8),
        clk         => clk,
        reset_p     => reset_p);
end generate;

gen_vrate : if SUPPORT_VRATE generate
    u_vrate : entity work.mac_vlan_rate
        generic map(
        DEV_ADDR    => DEV_ADDR,
        REG_ADDR    => RT_ADDR_VLAN_RATE,
        IO_BYTES    => IO_BYTES,
        PORT_COUNT  => PORT_COUNT+1,
        CORE_CLK_HZ => CORE_CLK_HZ)
        port map(
        in_vtag     => ptp_meta.vtag,
        in_nlast    => ptp_nlast,
        in_write    => ptp_write,
        out_pmask   => vrate_mask,
        out_himask  => vrate_allow,
        out_valid   => vrate_valid,
        out_ready   => packet_done,
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(9),
        clk         => clk,
        reset_p     => reset_p);
end generate;

-- Combined queue-depth monitoring and queue-selector
qstate_pad <= x"00" & queue_state;

u_qsel : entity work.router2_qsel
    generic map(
    IO_BYTES    => IO_BYTES,
    META_WIDTH  => PORT_COUNT,
    PORT_COUNT  => PORT_COUNT+1,
    REFCLK_HZ   => CORE_CLK_HZ)
    port map(
    raw_qdepth  => qstate_pad,
    in_data     => ptp_data,
    in_meta     => ptp_pdst(PORT_COUNT-1 downto 0),
    in_nlast    => ptp_nlast,
    in_pdst     => ptp_pdst,
    in_write    => ptp_write,
    out_data    => qsel_data,
    out_meta    => qsel_pdst,
    out_nlast   => qsel_nlast,
    out_write   => qsel_write,
    out_qdepth  => qsel_qdepth,
    clk         => clk,
    reset_p     => reset_p);

-- Congestion notification (ECN) based on queue status
u_ecn : entity work.router2_ecn_red
    generic map(
    IO_BYTES    => IO_BYTES,
    META_WIDTH  => PORT_COUNT,
    DEVADDR     => DEV_ADDR,
    REGADDR     => RT_ADDR_ECN_RED)
    port map(
    in_data     => qsel_data,
    in_nlast    => qsel_nlast,
    in_meta     => qsel_pdst,
    in_write    => qsel_write,
    in_qdepth   => qsel_qdepth,
    out_data    => ecn_data,
    out_nlast   => ecn_nlast,
    out_drop    => ecn_drop,
    out_meta    => ecn_pdst,
    out_write   => ecn_write,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(10),
    clk         => clk,
    reset_p     => reset_p);

ecn_pmod <= (others => '0') when (ecn_drop = '1') else (ecn_pdst);

-- Recalculate IP header checksum after various changes
u_chksum : entity work.router2_ipchksum
    generic map(
    IO_BYTES    => IO_BYTES,
    META_WIDTH  => PORT_COUNT)
    port map(
    in_data     => ecn_data,
    in_nlast    => ecn_nlast,
    in_meta     => ecn_pmod,
    in_write    => ecn_write,
    out_data    => chk_data,
    out_nlast   => chk_nlast,
    out_meta    => chk_pdst,
    out_write   => chk_write,
    clk         => clk,
    reset_p     => reset_p);

-- Consolidate metadata from various sources.
chk_meta.pmsg   <= ptpf_meta.pmsg;
chk_meta.pfreq  <= ptpf_meta.pfreq;
chk_meta.tstamp <= ptpf_meta.tstamp;
chk_meta.tfreq  <= ptpf_meta.tfreq;
chk_meta.vtag   <= vport_vtag;

chk_keep <= chk_pdst and ptpf_mask0 and vport_mask and vrate_mask;

chk_result <= frm_result_silent(DROP_IPROUTE)  when (chk_pdst = MASK0_NONE)
         else frm_result_error(DROP_PTPERR)    when (ptpf_mask1 = MASK1_NONE)
         else frm_result_error(DROP_VLAN)      when (vport_mask = MASK0_NONE)
         else frm_result_silent(DROP_VRATE)    when (vrate_mask = MASK0_NONE)
         else frm_result_ok;

-- Optional diagnostic logging.
gen_log1 : if SUPPORT_LOG generate
    -- Log as overflow if ALL applicable outputs drop the packet.
    ovr_strobe <= bool2bit(out_overflow = ovr_dmask);

    u_log : entity work.eth_frame_log
        generic map(
        INPUT_BYTES => IO_BYTES,
        FILTER_MODE => false,   -- Log all packets
        OUT_BUFFER  => false,   -- Unbuffered OK
        OVR_DELAY   => OVR_DELAY,
        PORT_COUNT  => PORT_COUNT)
        port map(
        in_data     => chk_data,
        in_dmask    => chk_keep,
        in_meta     => chk_meta,
        in_psrc     => ptpf_psrc,
        in_nlast    => chk_nlast,
        in_result   => chk_result,
        in_write    => chk_write,
        ovr_dmask   => ovr_dmask,
        ovr_strobe  => ovr_strobe,
        out_data    => log_data,
        out_dmask   => log_dmask,
        out_psrc    => log_psrc,
        out_strobe  => log_write,
        clk         => clk,
        reset_p     => reset_p);
end generate;

gen_log0 : if not SUPPORT_LOG generate
    log_data    <= LOG_META_NULL;
    log_psrc    <= 0;
    log_dmask   <= (others => '0');
    log_write   <= '0';
end generate;

-- Drive top-level outputs.
-- Final "KEEP" flag is the bitwise-AND of all port masks.
out_data        <= chk_data;
out_meta        <= chk_meta;
out_nlast       <= chk_nlast;
out_write       <= chk_write;
out_priority    <= vport_hipri and vrate_allow;
out_keep        <= chk_keep;
packet_done     <= chk_write and bool2bit(chk_nlast > 0);
port_2step      <= cfg_stpmask;
error_ptp       <= error_ptp_i(PORT_COUNT-1 downto 0);

-- Packet counting diagnostics.
u_pcount : cfgbus_counter
    generic map(
    DEVADDR     => DEV_ADDR,
    REGADDR     => RT_ADDR_PKT_COUNT,
    COUNT_WIDTH => 24)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(11),
    sync_clk    => clk,
    sync_evt    => packet_done);

-- Combine ConfigBus replies.
cfg_ack <= cfgbus_merge(cfg_acks);

-- Simulation-only sanity checks.
p_sim : process(clk)
begin
    if rising_edge(clk) then
        if (packet_done = '1') then
            assert (ptpf_valid = '1')
                report "LATE PTPF" severity error;
            assert (vport_valid = '1')
                report "LATE VPORT" severity error;
            assert (vrate_valid = '1')
                report "LATE VRATE" severity error;
        end if;
    end if;
end process;

end router2_pipeline;
