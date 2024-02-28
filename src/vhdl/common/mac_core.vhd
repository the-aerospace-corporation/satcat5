--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- High-level wrapper for the MAC-processing pipeline
--
-- This block is the high-bandwidth engine at the heart of "switch_core",
-- providing MAC-address lookup, IGMP snooping, and other services to
-- determine which packets should be written to each output FIFO.
--
-- The input is a stream of Ethernet frames, plus the selected port index.
-- The width of this port can be as narrow as 1 byte per clock, or as wide
-- as necessary to support the desired throughput.
--
-- The output is a delayed copy of the same stream, plus the packet
-- priority flag (if enabled), plus per-port "keep" strobes.
--
-- ConfigBus is used to report configuration parameters and configure
-- various runtime options.  To disable these features entirely, set
-- the device-address to CFGBUS_ADDR_NONE and leave the cfg_cmd port
-- disconnected (i.e., CFGBUS_CMD_NULL).
--
-- If enabled, the configuration register map follows the definitions
-- from "switch_types.vhd".
--
-- If ALLOW_PRECOMMIT is enabled, generate a pre-commit flag for the
-- output FIFO associated with each port.  (See also: fifo_packet)
-- Since the MAC pipeline always uses 100% duty-cycle and should always
-- be designed to exceed the bandwidth of any one port, this satisfies
-- all prerequisites for reduced latency "cut-through" mode.
--
-- Unit-test coverage for this block is provided by "switch_core_tb".
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.switch_types.all;
use     work.tcam_constants.all;

entity mac_core is
    generic (
    DEV_ADDR        : integer;          -- Device address for all registers
    IO_BYTES        : positive;         -- Width of main data ports
    PORT_COUNT      : positive;         -- Number of Ethernet ports
    CORE_CLK_HZ     : positive;         -- Core clock frequency (Hz)
    MIN_FRM_BYTES   : positive;         -- Minimum frame size
    MAX_FRM_BYTES   : positive;         -- Maximum frame size
    MAC_TABLE_EDIT  : boolean;          -- Manual read/write of MAC table?
    MAC_TABLE_SIZE  : positive;         -- Max cached MAC addresses
    PRI_TABLE_SIZE  : natural;          -- Max high-priority EtherTypes (0 = disable)
    ALLOW_RUNT      : boolean;          -- Allow undersize frames?
    ALLOW_PRECOMMIT : boolean;          -- Allow output FIFO cut-through?
    PTP_STRICT      : boolean;          -- Drop frames with missing timestamps?
    SUPPORT_PTP     : boolean;          -- Support Precision Time Protocol?
    SUPPORT_VPORT   : boolean;          -- Support virtual-LAN port control?
    SUPPORT_VRATE   : boolean;          -- Support virtual-LAN rate control?
    MISS_BCAST      : std_logic := '1'; -- Broadcast or drop unknown MAC?
    IGMP_TIMEOUT    : positive := 63;   -- IGMP timeout (0 = disable)
    PTP_MIXED_STEP  : boolean := true;  -- Support PTP format conversion?
    CACHE_POLICY    : repl_policy := TCAM_REPL_PLRU);
    port (
    -- Main input
    -- PSRC is the input port-index and must be held for the full frame.
    in_psrc         : in  integer range 0 to PORT_COUNT-1;
    in_data         : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_meta         : in  switch_meta_t;
    in_nlast        : in  integer range 0 to IO_BYTES;
    in_valid        : in  std_logic;
    in_ready        : out std_logic;

    -- Main output, with end-of-frame strobes for each port.
    out_data        : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_meta        : out switch_meta_t;
    out_nlast       : out integer range 0 to IO_BYTES;
    out_write       : out std_logic;
    out_precommit   : out std_logic;
    out_priority    : out std_logic;
    out_keep        : out std_logic_vector(PORT_COUNT-1 downto 0);

    -- Configuration interface
    cfg_cmd         : in  cfgbus_cmd := CFGBUS_CMD_NULL;
    cfg_ack         : out cfgbus_ack;   -- Optional ConfigBus interface
    port_2step      : out std_logic_vector(PORT_COUNT-1 downto 0);
    scrub_req       : in  std_logic;    -- Timekeeping strobe (~1 Hz)
    error_change    : out std_logic;    -- MAC address changed ports
    error_other     : out std_logic;    -- Other internal error
    error_table     : out std_logic;    -- Table integrity check failed
    error_ptp       : out std_logic;
    ptp_err_psrc    : out integer range 0 to PORT_COUNT-1;

    -- System interface
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end mac_core;

architecture mac_core of mac_core is

-- Convenience types:
subtype data_word is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype port_mask is std_logic_vector(PORT_COUNT-1 downto 0);
subtype port_idx_t is integer range 0 to PORT_COUNT-1;

-- Main datapath
signal ptp_psrc     : port_idx_t := 0;
signal ptp_data     : data_word := (others => '0');
signal ptp_meta     : switch_meta_t := SWITCH_META_NULL;
signal ptp_nlast    : integer range 0 to IO_BYTES := IO_BYTES;
signal ptp_write    : std_logic := '0';
signal buf_psrc     : port_idx_t := 0;
signal buf_data     : data_word := (others => '0');
signal buf_meta     : switch_meta_t := SWITCH_META_NULL;
signal buf_nlast    : integer range 0 to IO_BYTES := IO_BYTES;
signal buf_last     : std_logic := '0';
signal buf_write    : std_logic := '0';
signal buf_wcount   : mac_bcount_t := 0;
signal dly_nlast    : integer range 0 to IO_BYTES;
signal dly_write    : std_logic;
signal packet_done  : std_logic;

-- MAC-address lookup
signal lookup_mask  : port_mask;
signal lookup_valid : std_logic;
signal tbl_clear    : std_logic := '0';
signal tbl_learn    : std_logic := '1';
signal tbl_rd_index : integer range 0 to MAC_TABLE_SIZE-1 := 0;
signal tbl_rd_valid : std_logic := '0';
signal tbl_rd_ready : std_logic;
signal tbl_rd_addr  : mac_addr_t;
signal tbl_rd_psrc  : port_idx_t;
signal tbl_wr_addr  : mac_addr_t := (others => '0');
signal tbl_wr_psrc  : port_idx_t := 0;
signal tbl_wr_valid : std_logic := '0';
signal tbl_wr_ready : std_logic;

-- Packet-priority lookup by EtherType (optional)
signal epri_hipri   : std_logic := '0';
signal epri_valid   : std_logic := '1';
signal epri_error   : std_logic := '0';

-- IGMP-snooping (optional)
signal igmp_mask    : port_mask := (others => '1');
signal igmp_valid   : std_logic := '1';
signal igmp_error   : std_logic := '0';

-- PTP routing and timestamps (optional)
signal ptpf_mask    : port_mask := (others => '1');
signal ptpf_pmode   : ptp_mode_t := PTP_MODE_NONE;
signal ptpf_tstamp  : tstamp_t := TSTAMP_DISABLED;
signal ptpf_valid   : std_logic := '1';

-- VLAN lookup (optional)
signal vport_mask   : port_mask := (others => '1');
signal vport_vtag   : vlan_hdr_t := (others => '0');
signal vport_hipri  : std_logic := '0';
signal vport_valid  : std_logic := '1';
signal vrate_mask   : port_mask := (others => '1');
signal vrate_allow  : std_logic := '1';
signal vrate_valid  : std_logic := '1';

-- Per-port configuration masks.
-- MB = Miss-as-broadcast, PR = Promiscuous, STP = PTP-2step
-- (Each one is effectively a constant if ConfigBus is disabled.)
signal cfg_mbword   : cfgbus_word := (others => MISS_BCAST);
signal cfg_mbmask   : port_mask := (others => MISS_BCAST);
signal cfg_prword   : cfgbus_word := (others => '0');
signal cfg_prmask   : port_mask := (others => '0');
signal cfg_stpword  : cfgbus_word := (others => '0');
signal cfg_stpmask  : port_mask := (others => '0');

-- ConfigBus combining.
signal cfg_acks     : cfgbus_ack_array(0 to 12) := (others => cfgbus_idle);

begin

-- General-purpose ConfigBus registers:
gen_cfgbus : if (DEV_ADDR > CFGBUS_ADDR_NONE) generate
    -- Read-only configuration reporting.
    -- See "switch_types" for complete register map.
    u_portcount : cfgbus_readonly
        generic map(
        DEVADDR     => DEV_ADDR,
        REGADDR     => REGADDR_PORT_COUNT)
        port map(
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(0),
        reg_val     => i2s(PORT_COUNT, CFGBUS_WORD_SIZE));
    u_datawidth : cfgbus_readonly
        generic map(
        DEVADDR     => DEV_ADDR,
        REGADDR     => REGADDR_DATA_WIDTH)
        port map(
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(1),
        reg_val     => i2s(8*IO_BYTES, CFGBUS_WORD_SIZE));
    u_coreclock : cfgbus_readonly
        generic map(
        DEVADDR     => DEV_ADDR,
        REGADDR     => REGADDR_CORE_CLOCK)
        port map(
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(2),
        reg_val     => i2s(CORE_CLK_HZ, CFGBUS_WORD_SIZE));
    u_mactable : cfgbus_readonly
        generic map(
        DEVADDR     => DEV_ADDR,
        REGADDR     => REGADDR_TABLE_SIZE)
        port map(
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(3),
        reg_val     => i2s(MAC_TABLE_SIZE, CFGBUS_WORD_SIZE));
    u_frmsize : cfgbus_readonly
        generic map(
        DEVADDR     => DEV_ADDR,
        REGADDR     => REGADDR_FRAME_SIZE)
        port map(
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(4),
        reg_val     => i2s(MAX_FRM_BYTES, CFGBUS_WORD_SIZE/2)
                     & i2s(MIN_FRM_BYTES, CFGBUS_WORD_SIZE/2));

    -- Packet counting diagnostics.
    u_counter : entity work.mac_counter
        generic map(
        DEV_ADDR    => DEV_ADDR,
        REG_ADDR    => REGADDR_PKT_COUNT,
        IO_BYTES    => IO_BYTES)
        port map(
        in_wcount   => buf_wcount,
        in_data     => buf_data,
        in_last     => buf_last,
        in_write    => buf_write,
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(5),
        clk         => clk,
        reset_p     => reset_p);

    -- Miss-as-broadcast configuration register
    u_mbword : cfgbus_register_sync
        generic map(
        DEVADDR     => DEV_ADDR,
        REGADDR     => REGADDR_MISS_BCAST,
        RSTVAL      => (others => MISS_BCAST),
        WR_ATOMIC   => true,
        WR_MASK     => cfgbus_mask_lsb(PORT_COUNT))
        port map(
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(6),
        sync_clk    => clk,
        sync_val    => cfg_mbword);

    -- Promiscuous-port configuration register
    u_prword : cfgbus_register_sync
        generic map(
        DEVADDR     => DEV_ADDR,
        REGADDR     => REGADDR_PROMISCUOUS,
        WR_ATOMIC   => true,
        WR_MASK     => cfgbus_mask_lsb(PORT_COUNT))
        port map(
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(7),
        sync_clk    => clk,
        sync_val    => cfg_prword);

    -- Zero-pad or truncate CPU registers as needed.
    cfg_mbmask <= resize(cfg_mbword, PORT_COUNT);
    cfg_prmask <= resize(cfg_prword, PORT_COUNT);
end generate;

-- Optional: Manual read/write of the MAC-address table?
gen_query : if (DEV_ADDR > CFGBUS_ADDR_NONE and MAC_TABLE_EDIT) generate
    u_query : entity work.mac_query
        generic map(
        DEV_ADDR    => DEV_ADDR,
        PORT_COUNT  => PORT_COUNT,
        TABLE_SIZE  => MAC_TABLE_SIZE)
        port map(
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(8),
        mac_clk     => clk,
        mac_clear   => tbl_clear,
        mac_learn   => tbl_learn,
        read_index  => tbl_rd_index,
        read_valid  => tbl_rd_valid,
        read_ready  => tbl_rd_ready,
        read_addr   => tbl_rd_addr,
        read_psrc   => tbl_rd_psrc,
        write_addr  => tbl_wr_addr,
        write_psrc  => tbl_wr_psrc,
        write_valid => tbl_wr_valid,
        write_ready => tbl_wr_ready);
end generate;

-- Optional: Two-step register for PTP format conversion.
gen_2step : if (DEV_ADDR > CFGBUS_ADDR_NONE and SUPPORT_PTP and PTP_MIXED_STEP) generate
    u_register : cfgbus_register
        generic map(
        DEVADDR     => DEV_ADDR,
        REGADDR     => REGADDR_PTP_2STEP,
        WR_ATOMIC   => true,
        WR_MASK     => cfgbus_mask_lsb(PORT_COUNT))
        port map(
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(9),
        reg_val     => cfg_stpword);

    cfg_stpmask <= resize(cfg_stpword, PORT_COUNT);
end generate;

-- Optional pre-processing for PTP.
-- (This step comes before the others, since it generates new frames
--  that must be processed by the rest of the MAC pipeline.)
gen_ptp1 : if SUPPORT_PTP generate
    u_ptp : entity work.ptp_adjust
        generic map(
        IO_BYTES    => IO_BYTES,
        PORT_COUNT  => PORT_COUNT,
        PTP_STRICT  => PTP_STRICT,
        MIXED_STEP  => PTP_MIXED_STEP)
        port map(
        in_meta     => in_meta,
        in_psrc     => in_psrc,
        in_data     => in_data,
        in_nlast    => in_nlast,
        in_valid    => in_valid,
        in_ready    => in_ready,
        out_meta    => ptp_meta,
        out_psrc    => ptp_psrc,
        out_data    => ptp_data,
        out_nlast   => ptp_nlast,
        out_valid   => ptp_write,
        out_ready   => '1',
        cfg_2step   => cfg_stpmask,
        frm_pmask   => ptpf_mask,
        frm_pmode   => ptpf_pmode,
        frm_tstamp  => ptpf_tstamp,
        frm_valid   => ptpf_valid,
        frm_ready   => packet_done,
        ptp_err     => error_ptp,
        ptp_err_psrc=> ptp_err_psrc,
        clk         => clk,
        reset_p     => reset_p);
end generate;

gen_ptp0 : if not SUPPORT_PTP generate
    ptp_psrc    <= in_psrc;
    ptp_data    <= in_data;
    ptp_meta    <= in_meta;
    ptp_nlast   <= in_nlast;
    ptp_write   <= in_valid;
    in_ready    <= '1';
end generate;

-- Buffer incoming data for better routing and timing.
p_buff : process(clk)
    constant WCOUNT_MAX : mac_bcount_t := mac_wcount_max(IO_BYTES);
begin
    if rising_edge(clk) then
        -- Buffer incoming data.
        buf_psrc    <= ptp_psrc;
        buf_data    <= ptp_data;
        buf_meta    <= ptp_meta;
        buf_nlast   <= ptp_nlast;
        buf_last    <= bool2bit(ptp_nlast > 0);
        buf_write   <= ptp_write and not reset_p;

        -- Word-counter for later packet parsing.
        if (reset_p = '1') then
            buf_wcount <= 0;    -- Global reset
        elsif (buf_write = '1' and buf_nlast > 0) then
            buf_wcount <= 0;    -- Start of new frame
        elsif (buf_write = '1' and buf_wcount < WCOUNT_MAX) then
            buf_wcount <= buf_wcount + 1;
        end if;
    end if;
end process;

-- Fixed delay for the main datapath.
-- (Must exceed the worst-case pipeline delay for each other unit.)
u_delay : entity work.packet_delay
    generic map(
    IO_BYTES    => IO_BYTES,
    DELAY_COUNT => 15)
    port map(
    in_data     => buf_data,
    in_nlast    => buf_nlast,
    in_write    => buf_write,
    out_data    => out_data,
    out_nlast   => dly_nlast,
    out_write   => dly_write,
    io_clk      => clk,
    reset_p     => reset_p);

-- Final "KEEP" flag is the bitwise-AND of all port masks.
out_meta.pmode  <= ptpf_pmode;
out_meta.tstamp <= ptpf_tstamp;
out_meta.vtag   <= vport_vtag;
out_write       <= dly_write;
out_nlast       <= dly_nlast;
out_precommit   <= bool2bit(ALLOW_PRECOMMIT)
               and lookup_valid and igmp_valid and epri_valid
               and ptpf_valid and vport_valid and vrate_valid;
out_priority    <= (epri_hipri or vport_hipri) and vrate_allow;
out_keep        <= lookup_mask and igmp_mask and ptpf_mask
               and vport_mask and vrate_mask;
error_other     <= igmp_error or epri_error;
packet_done     <= dly_write and bool2bit(dly_nlast > 0);
port_2step      <= cfg_stpmask;

-- MAC-address lookup
u_lookup : entity work.mac_lookup
    generic map(
    ALLOW_RUNT      => ALLOW_RUNT,
    IO_BYTES        => IO_BYTES,
    PORT_COUNT      => PORT_COUNT,
    TABLE_SIZE      => MAC_TABLE_SIZE,
    CACHE_POLICY    => CACHE_POLICY)
    port map(
    in_psrc         => buf_psrc,
    in_wcount       => buf_wcount,
    in_data         => buf_data,
    in_last         => buf_last,
    in_write        => buf_write,
    out_psrc        => open,
    out_pmask       => lookup_mask,
    out_valid       => lookup_valid,
    out_ready       => packet_done,
    cfg_clear       => tbl_clear,
    cfg_learn       => tbl_learn,
    cfg_mbmask      => cfg_mbmask,
    cfg_prmask      => cfg_prmask,
    error_change    => error_change,
    error_table     => error_table,
    read_index      => tbl_rd_index,
    read_valid      => tbl_rd_valid,
    read_ready      => tbl_rd_ready,
    read_addr       => tbl_rd_addr,
    read_psrc       => tbl_rd_psrc,
    read_found      => open,
    write_addr      => tbl_wr_addr,
    write_psrc      => tbl_wr_psrc,
    write_valid     => tbl_wr_valid,
    write_ready     => tbl_wr_ready,
    clk             => clk,
    reset_p         => reset_p);

-- IGMP snooping (optional)
gen_igmp : if (IGMP_TIMEOUT > 0) generate
    u_igmp : entity work.mac_igmp_simple
        generic map(
        IO_BYTES        => IO_BYTES,
        PORT_COUNT      => PORT_COUNT,
        IGMP_TIMEOUT    => IGMP_TIMEOUT)
        port map(
        in_psrc         => buf_psrc,
        in_wcount       => buf_wcount,
        in_data         => buf_data,
        in_last         => buf_last,
        in_write        => buf_write,
        out_pdst        => igmp_mask,
        out_valid       => igmp_valid,
        out_ready       => packet_done,
        out_error       => igmp_error,
        cfg_prmask      => cfg_prmask,
        scrub_req       => scrub_req,
        clk             => clk,
        reset_p         => reset_p);
end generate;

-- Packet-priority lookup by EtherType (optional)
gen_priority : if (DEV_ADDR > CFGBUS_ADDR_NONE
               and PRI_TABLE_SIZE > 0) generate
    u_priority : entity work.mac_priority
        generic map(
        DEVADDR     => DEV_ADDR,
        REGADDR     => REGADDR_PRIORITY,
        IO_BYTES    => IO_BYTES,
        TABLE_SIZE  => PRI_TABLE_SIZE)
        port map(
        in_wcount   => buf_wcount,
        in_data     => buf_data,
        in_last     => buf_last,
        in_write    => buf_write,
        out_pri     => epri_hipri,
        out_valid   => epri_valid,
        out_ready   => packet_done,
        out_error   => epri_error,
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(10),
        clk         => clk,
        reset_p     => reset_p);
end generate;

-- Virtual-LAN lookup (optional)
gen_vport : if SUPPORT_VPORT generate
    u_vport : entity work.mac_vlan_mask
        generic map(
        DEV_ADDR    => DEV_ADDR,
        REG_ADDR_V  => REGADDR_VLAN_VID,
        REG_ADDR_M  => REGADDR_VLAN_MASK,
        PORT_COUNT  => PORT_COUNT)
        port map(
        in_psrc     => buf_psrc,
        in_vtag     => buf_meta.vtag,
        in_last     => buf_last,
        in_write    => buf_write,
        out_vtag    => vport_vtag,
        out_pmask   => vport_mask,
        out_hipri   => vport_hipri,
        out_valid   => vport_valid,
        out_ready   => packet_done,
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(11),
        clk         => clk,
        reset_p     => reset_p);
end generate;

gen_vrate : if SUPPORT_VRATE generate
    u_vrate : entity work.mac_vlan_rate
        generic map(
        DEV_ADDR    => DEV_ADDR,
        REG_ADDR    => REGADDR_VLAN_RATE,
        IO_BYTES    => IO_BYTES,
        PORT_COUNT  => PORT_COUNT,
        CORE_CLK_HZ => CORE_CLK_HZ)
        port map(
        in_vtag     => buf_meta.vtag,
        in_nlast    => buf_nlast,
        in_write    => buf_write,
        out_pmask   => vrate_mask,
        out_himask  => vrate_allow,
        out_valid   => vrate_valid,
        out_ready   => packet_done,
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(12),
        clk         => clk,
        reset_p     => reset_p);
end generate;

-- Combine ConfigBus replies.
cfg_ack <= cfgbus_merge(cfg_acks);

-- Simulation-only sanity checks.
p_sim : process(clk)
begin
    if rising_edge(clk) then
        if (packet_done = '1') then
            assert (lookup_valid = '1')
                report "LATE Lookup" severity error;
            assert (igmp_valid = '1')
                report "LATE IGMP" severity error;
            assert (epri_valid = '1')
                report "LATE Priority" severity error;
            assert (ptpf_valid = '1')
                report "LATE PTPF" severity error;
            assert (vport_valid = '1')
                report "LATE VPORT" severity error;
            assert (vrate_valid = '1')
                report "LATE VRATE" severity error;
        end if;
    end if;
end process;

end mac_core;
