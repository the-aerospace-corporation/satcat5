--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Top-level interface for the IPv4 router
--
-- This module ties together the frame-check, packet-FIFO, round-robin
-- scheduler, and shared pipeline to form the complete router:
--
--      In0--FrmChk--FIFO--+--Scheduler--+--Pipeline--+--FIFO--Out0
--      In1--FrmChk--FIFO--+                          +--FIFO--Out1
--      In2--FrmChk--FIFO--+                          +--FIFO--Out2
--      In3--FrmChk--FIFO--+                          +--FIFO--Out3
--
-- Many configurations are possible, selected by generic parameters.
-- Note that all configurations require software support to offload
-- certain rare-but-complex edge cases, such as deferred forwarding.
--
-- All ports use the same input and output buffer sizes.  See FAQ for
-- more information on how to choose these parameters.  Prioritization
-- uses a second output FIFO on each port, typically much smaller than
-- the primary output FIFO.  (High-priority mode should never be used
-- for bulk traffic.)  The FIFO size (HBUF_KBYTES) is in addition to
-- and independent of the primary output buffer size (OBUF_KBYTES).
-- This feature is disabled if HBUF_KBYTES = 0.
--
-- A brief explanation of each build-time configuration parameter:
--  * DEV_ADDR
--      ConfigBus device address for the management and offload interface.
--      See "router2_common.vhd" for a list of defined register addresses.
--  * CORE_CLK_HZ
--      Clock rate of the "core_clk" signal, in Hz.
--      Used to scale various real-time parameters and timeouts.
--  * DEBUG_VERBOSE
--      For simulation only, enables additional diagnostic logs.
--  * SUPPORT_PAUSE (default: true)
--      Support or ignore 802.3x "PAUSE" frames?
--      This feature is recommended for compatibility (e.g., many USB-Ethernet
--      adapters rely on this feature), but may be disabled to save resources.
--  * SUPPORT_PTP (default: false)
--      Support precise IEEE-1588 timestamps in transparent clock mode?
--      Each PTP-enabled port must also be provided with a Vernier reference
--      (ptp_counter_gen) and set VCONFIG (create_vernier_config).
--  * SUPPORT_VLAN (default: false)
--      Support or ignore 802.1q VLAN tags?
--      VLAN support requires additional BRAM.
--  * ALLOW_RUNT (default: false)
--      Accept runt Ethernet frames? (Size < 64 bytes)
--      Many 10/100/1000BASE-T PHYs cannot support runt frames, but they can
--      be used with SPI and UART ports.  See "port_adapter.vhd" for an inline
--      adapter that can be used to pad outgoing packets as needed.
--  * PTP_DOPPLER (default: false)
--      Enable support for an experimental extension to PTP, which allows
--      end-to-end measurement of Doppler frequency offsets.
--  * PTP_STRICT (default: true)
--      Sets policy for dropping PTP messages when timestamps are not
--      available for the affected ports.  It is typically better to drop
--      the message entirely than to propagate with unknown degradation.
--  * PORT_COUNT (default: 0)
--      Total standard Ethernet ports (ports_*)
--  * PORTX_COUNT (default: 0)
--      Total 10 Gbps Ethernet ports (portx_*)
--  * DATAPATH_BYTES
--      Width of shared pipeline, which sets available bandwidth:
--          TOTAL_BANDWIDTH(bps) = CORE_CLK_HZ * DATAPATH_BYTES * 8
--      Choose DATAPATH_BYTES such that TOTAL_BANDWIDTH exceeds the sum
--      of all input ports.  For example, a switch with eight gigabit
--      ports and CORE_CLK_HZ = 200 MHz requires DATAPATH_BYTES >= 5.
--      Additional margin can reduce required IBUF_KBYTES.
--  * IBUF_KBYTES (default: 2)
--      Input buffer size for each port (kilobytes)
--      Increase this to at least 4 if DATAPATH_BYTES leaves low margin.
--      Increase this to at least 10 if ALLOW_JUMBO is enabled.
--  * HBUF_KBYTES (default: 0)
--      High-priority output buffer size for each port (kilobytes)
--      Any value greater than zero enables packet prioritization, which
--      is set by VLAN (SUPPORT_VLAN) ID and/or priority codes.
--  * OBUF_KBYTES
--      Normal-priority output buffer size for each port (kilobytes)
--      Recommended setting is at least 8-16, depending on traffic statistics.
--      Increase this setting if congestion packet losses are excessive.
--  * IBUF_PACKETS (default: 32)
--      Maximum allowed packets in each port's input queue.
--      Decreasing this figure can save slices on some platforms.
--  * OBUF_PACKETS (default: 32)
--      Maximum allowed packets in each port's output queue.
--      Decreasing this figure can save slices on some platforms.
--  * PTP_MIXED_STEP (default: true)
--      Support PTP format conversion?  (One-step to two-step conversion.)
--      Required for full PTP compatibility, disable to save resources.
--      This parameter has no effect if SUPPORT_PTP = false.
--  * CIDR_TABLE_SIZE (default: 64)
--      Maximum number of static routes and cached MAC addresses.
--      On small LANs, this should match or exceed the number of endpoints.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity router2_core is
    generic (
    DEV_ADDR        : natural;          -- ConfigBus device address (required)
    CORE_CLK_HZ     : positive;         -- Rate of core_clk (Hz)
    DEBUG_VERBOSE   : boolean := false; -- Enable simulation logs?
    SUPPORT_PAUSE   : boolean := true;  -- Support or ignore 802.3x "PAUSE" frames?
    SUPPORT_PTP     : boolean := false; -- Support precise frame timestamps?
    SUPPORT_VLAN    : boolean := false; -- Support or ignore 802.1q VLAN tags?
    ALLOW_RUNT      : boolean := false; -- Allow runt frames? (Size < 64 bytes)
    PTP_DOPPLER     : boolean := false; -- Support for experimental Doppler-PTP?
    PTP_STRICT      : boolean := true;  -- Drop frames with missing timestamps?
    PORT_COUNT      : natural := 0;     -- Total standard Ethernet ports
    PORTX_COUNT     : natural := 0;     -- Total 10 Gbps Ethernet ports
    DATAPATH_BYTES  : positive;         -- Width of shared pipeline
    IBUF_KBYTES     : positive := 2;    -- Input buffer size (kilobytes)
    HBUF_KBYTES     : natural := 0;     -- High-priority output buffer (kilobytes)
    OBUF_KBYTES     : positive;         -- Normal-priority output buffer (kilobytes)
    IBUF_PACKETS    : positive := 32;   -- Input buffer max packets
    OBUF_PACKETS    : positive := 32;   -- Output buffer max packets
    PTP_MIXED_STEP  : boolean := true;  -- Support PTP format conversion?
    CIDR_TABLE_SIZE : positive := 64);  -- Size of routing table and ARP cache
    port (
    -- Switch ports (0-1 Gbps)
    ports_rx_data   : in  array_rx_m2s(PORT_COUNT-1 downto 0) := (others => RX_M2S_IDLE);
    ports_tx_data   : out array_tx_s2m(PORT_COUNT-1 downto 0);
    ports_tx_ctrl   : in  array_tx_m2s(PORT_COUNT-1 downto 0) := (others => TX_M2S_IDLE);

    -- Switch ports (2-10 Gbps)
    portx_rx_data   : in  array_rx_m2sx(PORTX_COUNT-1 downto 0) := (others => RX_M2SX_IDLE);
    portx_tx_data   : out array_tx_s2mx(PORTX_COUNT-1 downto 0);
    portx_tx_ctrl   : in  array_tx_m2sx(PORTX_COUNT-1 downto 0) := (others => TX_M2SX_IDLE);

    -- Error events are marked by toggling these bits.
    err_ports       : out array_port_error(PORTX_COUNT+PORT_COUNT-1 downto 0);
    err_router      : out switch_error_t;

    -- Configuration interface
    cfg_cmd         : in  cfgbus_cmd := CFGBUS_CMD_NULL;
    cfg_ack         : out cfgbus_ack;   -- Optional ConfigBus interface

    -- System interface.
    core_clk        : in  std_logic;    -- Core datapath clock
    core_reset_p    : in  std_logic);   -- Core async reset
end router2_core;

architecture router2_core of router2_core is

-- Define various local types.
constant PORT_TOTAL : natural := PORT_COUNT + PORTX_COUNT;
subtype word_t is std_logic_vector(8*DATAPATH_BYTES-1 downto 0);
subtype nlast_t is integer range 0 to DATAPATH_BYTES;
subtype bit_array is std_logic_vector(PORT_TOTAL-1 downto 0);
type meta_array is array(PORT_TOTAL-1 downto 0) of switch_meta_t;
type word_array is array(PORT_TOTAL-1 downto 0) of word_t;
type nlast_array is array(PORT_TOTAL-1 downto 0) of nlast_t;

-- Input packet FIFO.
signal pktin_clk        : bit_array;
signal pktin_data       : word_array;
signal pktin_meta       : meta_array;
signal pktin_nlast      : nlast_array;
signal pktin_last       : bit_array;
signal pktin_valid      : bit_array;
signal pktin_ready      : bit_array;
signal pktin_badfrm     : bit_array;
signal pktin_overflow   : bit_array;
signal pktin_ptperror   : bit_array;
signal pktin_rxerror    : bit_array;

-- Round-robin scheduler.
signal sched_error      : std_logic;
signal sched_data       : word_t;
signal sched_meta       : switch_meta_t;
signal sched_nlast      : nlast_t;
signal sched_valid      : std_logic;
signal sched_ready      : std_logic;
signal sched_select     : integer range 0 to PORT_TOTAL-1;

-- Packet processing pipeline
signal macerr_tbl       : std_logic;
signal pktout_clk       : bit_array;
signal pktout_data      : word_t;
signal pktout_meta      : switch_meta_t;
signal pktout_nlast     : nlast_t;
signal pktout_write     : std_logic;
signal pktout_hipri     : std_logic;
signal pktout_pdst      : bit_array;

-- Output packet FIFO
signal pktout_overflow  : bit_array;
signal pktout_txerror   : bit_array;
signal pktout_2step     : bit_array;
signal pktout_pause     : bit_array;
signal pktout_ptperror  : bit_array;
signal pktout_qstate    : unsigned(8*PORT_TOTAL-1 downto 0);

-- Error toggles for switch_aux and port_statistics.
signal err_prt          : array_port_error(PORT_TOTAL-1 downto 0) := (others => PORT_ERROR_NONE);
signal err_sw           : switch_error_t := SWITCH_ERROR_NONE;

-- Synchronized version of external reset.
signal core_reset_sync  : std_logic;

-- Consolidate ConfigBus replies.
signal cfg_ack_all      : cfgbus_ack_array(0 to 2) := (others => cfgbus_idle);
signal cfg_ack_rx       : cfgbus_ack_array(0 to PORT_TOTAL-1) := (others => cfgbus_idle);
signal cfg_ack_tx       : cfgbus_ack_array(0 to PORT_TOTAL-1) := (others => cfgbus_idle);

begin

-- Drive the final error vectors:
err_ports   <= err_prt;
err_router  <= err_sw;

-- Error reporting and aggregation:
p_err_sw : process(core_clk)
begin
    if rising_edge(core_clk) then
        -- Convert strobe to toggle as needed.
        if (macerr_tbl = '1') then
            report "Routing table error" severity error;
            err_sw.mac_tbl <= not err_sw.mac_tbl;
        end if;

        -- Consolidate per-port error strobes and convert to toggle.
        if (or_reduce(pktin_badfrm) = '1') then
            report "Input packet invalid" severity warning;
            err_sw.pkt_err <= not err_sw.pkt_err;
        end if;
        if (or_reduce(pktin_overflow) = '1') then
            report "Input buffer overflow" severity warning;
            err_sw.ovr_rx <= not err_sw.ovr_rx;
        end if;
        if (or_reduce(pktout_overflow) = '1') then
            report "Output buffer overflow" severity warning;
            err_sw.ovr_tx <= not err_sw.ovr_tx;
        end if;
        if (or_reduce(pktin_rxerror) = '1') then
            report "Input interface error" severity error;
            err_sw.mii_rx <= not err_sw.mii_rx;
        end if;
        if (or_reduce(pktout_txerror) = '1') then
            report "Output interface error" severity error;
            err_sw.mii_tx <= not err_sw.mii_tx;
        end if;

        -- Per-port error reporting.
        for n in PORT_TOTAL-1 downto 0 loop
            if (pktin_rxerror(n) = '1' or pktout_txerror(n) = '1') then
                err_prt(n).mii_err <= not err_prt(n).mii_err;
            end if;
            if (pktin_overflow(n) = '1') then
                err_prt(n).ovr_rx <= not err_prt(n).ovr_rx;
            end if;
            if (pktout_overflow(n) = '1') then
                err_prt(n).ovr_tx <= not err_prt(n).ovr_tx;
            end if;
            if (pktin_badfrm(n) = '1') then
                err_prt(n).pkt_err <= not err_prt(n).pkt_err;
            end if;
            if (pktin_ptperror(n) = '1') then
                err_prt(n).rx_ptp_err <= not err_prt(n).rx_ptp_err;
            end if;
            if (pktout_ptperror(n) = '1') then
                err_prt(n).tx_ptp_err <= not err_prt(n).tx_ptp_err;
            end if;
        end loop;
    end if;
end process;

-- Synchronize the external reset signal.
u_rsync : sync_reset
    port map(
    in_reset_p  => core_reset_p,
    out_reset_p => core_reset_sync,
    out_clk     => core_clk);

----------------------------- INPUT LOGIC ---------------------------
-- For each 1Gbps input port...
gen_input : for n in PORT_COUNT-1 downto 0 generate
    -- Force clock assignment, as a workaround for bugs in Vivado XSIM.
    -- Clocks that come directly from a record do not correctly propagate
    -- process sensitivity events in XSIM 2015.4 and 2016.3.
    -- This has no effect on synthesis results.
    pktin_clk(n) <= to_01_std(ports_rx_data(n).clk);

    -- Frame validity check and other ingress processing.
    u_input : entity work.switch_port_rx
        generic map(
        DEV_ADDR        => DEV_ADDR,
        CORE_CLK_HZ     => CORE_CLK_HZ,
        PORT_INDEX      => n,
        PTP_DOPPLER     => PTP_DOPPLER,
        STRIP_FCS       => true,
        SUPPORT_PAUSE   => SUPPORT_PAUSE,
        SUPPORT_PTP     => SUPPORT_PTP,
        SUPPORT_VLAN    => SUPPORT_VLAN,
        ALLOW_JUMBO     => false,
        ALLOW_RUNT      => ALLOW_RUNT,
        INPUT_BYTES     => 1,
        OUTPUT_BYTES    => DATAPATH_BYTES,
        IBUF_KBYTES     => IBUF_KBYTES,
        IBUF_PACKETS    => IBUF_PACKETS)
        port map(
        rx_clk          => pktin_clk(n),
        rx_data         => ports_rx_data(n).data,
        rx_last         => ports_rx_data(n).last,
        rx_write        => ports_rx_data(n).write,
        rx_macerr       => ports_rx_data(n).rxerr,
        rx_rate         => ports_rx_data(n).rate,
        rx_tsof         => ports_rx_data(n).tsof,
        rx_tfreq        => ports_rx_data(n).tfreq,
        rx_reset_p      => ports_rx_data(n).reset_p,
        out_data        => pktin_data(n),
        out_meta        => pktin_meta(n),
        out_nlast       => pktin_nlast(n),
        out_last        => pktin_last(n),
        out_valid       => pktin_valid(n),
        out_ready       => pktin_ready(n),
        pause_tx        => pktout_pause(n),
        err_badfrm      => pktin_badfrm(n),
        err_rxmac       => pktin_rxerror(n),
        err_overflow    => pktin_overflow(n),
        cfg_cmd         => cfg_cmd,
        cfg_ack         => cfg_ack_rx(n),
        core_clk        => core_clk,
        core_reset_p    => core_reset_sync);
end generate;

-- For each 10Gbps input port...
gen_xinput : for n in PORTX_COUNT-1 downto 0 generate
    -- Force clock assignment, as a workaround for bugs in Vivado XSIM.
    -- Clocks that come directly from a record do not correctly propagate
    -- process sensitivity events in XSIM 2015.4 and 2016.3.
    -- This has no effect on synthesis results.
    pktin_clk(PORT_COUNT+n) <= to_01_std(portx_rx_data(n).clk);

    -- Frame validity check and other ingress processing.
    u_input : entity work.switch_port_rx
        generic map(
        DEV_ADDR        => DEV_ADDR,
        CORE_CLK_HZ     => CORE_CLK_HZ,
        PORT_INDEX      => PORT_COUNT+n,
        PTP_DOPPLER     => PTP_DOPPLER,
        STRIP_FCS       => true,
        SUPPORT_PAUSE   => SUPPORT_PAUSE,
        SUPPORT_PTP     => SUPPORT_PTP,
        SUPPORT_VLAN    => SUPPORT_VLAN,
        ALLOW_JUMBO     => false,
        ALLOW_RUNT      => ALLOW_RUNT,
        INPUT_BYTES     => 8,
        OUTPUT_BYTES    => DATAPATH_BYTES,
        IBUF_KBYTES     => IBUF_KBYTES,
        IBUF_PACKETS    => IBUF_PACKETS)
        port map(
        rx_clk          => pktin_clk(PORT_COUNT+n),
        rx_data         => portx_rx_data(n).data,
        rx_nlast        => portx_rx_data(n).nlast,
        rx_write        => portx_rx_data(n).write,
        rx_macerr       => portx_rx_data(n).rxerr,
        rx_rate         => portx_rx_data(n).rate,
        rx_tsof         => portx_rx_data(n).tsof,
        rx_tfreq        => portx_rx_data(n).tfreq,
        rx_reset_p      => portx_rx_data(n).reset_p,
        out_data        => pktin_data(PORT_COUNT+n),
        out_meta        => pktin_meta(PORT_COUNT+n),
        out_nlast       => pktin_nlast(PORT_COUNT+n),
        out_last        => pktin_last(PORT_COUNT+n),
        out_valid       => pktin_valid(PORT_COUNT+n),
        out_ready       => pktin_ready(PORT_COUNT+n),
        pause_tx        => pktout_pause(PORT_COUNT+n),
        err_badfrm      => pktin_badfrm(PORT_COUNT+n),
        err_rxmac       => pktin_rxerror(PORT_COUNT+n),
        err_overflow    => pktin_overflow(PORT_COUNT+n),
        cfg_cmd         => cfg_cmd,
        cfg_ack         => cfg_ack_rx(PORT_COUNT+n),
        core_clk        => core_clk,
        core_reset_p    => core_reset_sync);
end generate;

----------------------------- SHARED PIPELINE -----------------------
-- Round-robin scheduler chooses which input is active.
u_robin : entity work.packet_round_robin
    generic map(
    INPUT_COUNT     => PORT_TOTAL)
    port map(
    in_last         => pktin_last,
    in_valid        => pktin_valid,
    in_ready        => pktin_ready,
    in_select       => sched_select,
    in_error        => sched_error,
    out_valid       => sched_valid,
    out_ready       => sched_ready,
    clk             => core_clk);

sched_data  <= pktin_data(sched_select);
sched_meta  <= pktin_meta(sched_select);
sched_nlast <= pktin_nlast(sched_select);

-- Shared router pipeline
u_router : entity work.router2_pipeline
    generic map(
    DEV_ADDR        => DEV_ADDR,
    IO_BYTES        => DATAPATH_BYTES,
    PORT_COUNT      => PORT_TOTAL,
    TABLE_SIZE      => CIDR_TABLE_SIZE,
    CORE_CLK_HZ     => CORE_CLK_HZ,
    PTP_DOPPLER     => PTP_DOPPLER,
    PTP_MIXED_STEP  => PTP_MIXED_STEP,
    PTP_STRICT      => PTP_STRICT,
    SUPPORT_PTP     => SUPPORT_PTP,
    SUPPORT_VPORT   => SUPPORT_VLAN,
    SUPPORT_VRATE   => SUPPORT_VLAN,
    DEBUG_VERBOSE   => DEBUG_VERBOSE)
    port map(
    in_psrc         => sched_select,
    in_data         => sched_data,
    in_meta         => sched_meta,
    in_nlast        => sched_nlast,
    in_valid        => sched_valid,
    in_ready        => sched_ready,
    out_data        => pktout_data,
    out_meta        => pktout_meta,
    out_nlast       => pktout_nlast,
    out_write       => pktout_write,
    out_priority    => pktout_hipri,
    out_keep        => pktout_pdst,
    cfg_cmd         => cfg_cmd,
    cfg_ack         => cfg_ack_all(0),
    port_2step      => pktout_2step,
    queue_state     => pktout_qstate,
    error_table     => macerr_tbl,
    error_ptp       => pktin_ptperror,
    clk             => core_clk,
    reset_p         => core_reset_sync);

----------------------------- OUTPUT LOGIC --------------------------
-- For each 1 Gbps output port...
gen_output : for n in PORT_COUNT-1 downto 0 generate
    -- Clock workaround; see "pktin_clk", above.
    pktout_clk(n) <= to_01_std(ports_tx_ctrl(n).clk);

    -- Output FIFO and other processing for each port.
    u_output : entity work.switch_port_tx
        generic map(
        DEV_ADDR        => DEV_ADDR,
        PORT_INDEX      => n,
        SUPPORT_PTP     => SUPPORT_PTP,
        SUPPORT_VLAN    => SUPPORT_VLAN,
        ALLOW_JUMBO     => false,
        ALLOW_RUNT      => ALLOW_RUNT,
        INPUT_HAS_FCS   => false,
        PTP_DOPPLER     => PTP_DOPPLER,
        PTP_STRICT      => PTP_STRICT,
        INPUT_BYTES     => DATAPATH_BYTES,
        OUTPUT_BYTES    => 1,
        HBUF_KBYTES     => HBUF_KBYTES,
        OBUF_KBYTES     => OBUF_KBYTES,
        OBUF_PACKETS    => OBUF_PACKETS)
        port map(
        in_data         => pktout_data,
        in_meta         => pktout_meta,
        in_nlast        => pktout_nlast,
        in_precommit    => '0',
        in_keep         => pktout_pdst(n),
        in_hipri        => pktout_hipri,
        in_write        => pktout_write,
        tx_clk          => pktout_clk(n),
        tx_data         => ports_tx_data(n).data,
        tx_last         => ports_tx_data(n).last,
        tx_valid        => ports_tx_data(n).valid,
        tx_ready        => ports_tx_ctrl(n).ready,
        tx_pstart       => ports_tx_ctrl(n).pstart,
        tx_tnow         => ports_tx_ctrl(n).tnow,
        tx_tfreq        => ports_tx_ctrl(n).tfreq,
        tx_macerr       => ports_tx_ctrl(n).txerr,
        tx_reset_p      => ports_tx_ctrl(n).reset_p,
        pause_tx        => pktout_pause(n),
        port_2step      => pktout_2step(n),
        queue_state     => pktout_qstate(8*n+7 downto 8*n),
        err_overflow    => pktout_overflow(n),
        err_txmac       => pktout_txerror(n),
        err_ptp         => pktout_ptperror(n),
        cfg_cmd         => cfg_cmd,
        cfg_ack         => cfg_ack_tx(n),
        core_clk        => core_clk,
        core_reset_p    => core_reset_sync);
end generate;

-- For each 10 Gbps output port...
gen_xoutput : for n in PORTX_COUNT-1 downto 0 generate
    -- Clock workaround; see "pktin_clk", above.
    pktout_clk(PORT_COUNT+n) <= to_01_std(portx_tx_ctrl(n).clk);

    -- Output FIFO and other processing for each port.
    u_output : entity work.switch_port_tx
        generic map(
        DEV_ADDR        => DEV_ADDR,
        PORT_INDEX      => PORT_COUNT+n,
        SUPPORT_PTP     => SUPPORT_PTP,
        SUPPORT_VLAN    => SUPPORT_VLAN,
        ALLOW_JUMBO     => false,
        ALLOW_RUNT      => ALLOW_RUNT,
        INPUT_HAS_FCS   => false,
        PTP_DOPPLER     => PTP_DOPPLER,
        PTP_STRICT      => PTP_STRICT,
        INPUT_BYTES     => DATAPATH_BYTES,
        OUTPUT_BYTES    => 8,
        HBUF_KBYTES     => HBUF_KBYTES,
        OBUF_KBYTES     => OBUF_KBYTES,
        OBUF_PACKETS    => OBUF_PACKETS)
        port map(
        in_data         => pktout_data,
        in_meta         => pktout_meta,
        in_nlast        => pktout_nlast,
        in_precommit    => '0',
        in_keep         => pktout_pdst(PORT_COUNT+n),
        in_hipri        => pktout_hipri,
        in_write        => pktout_write,
        tx_clk          => pktout_clk(PORT_COUNT+n),
        tx_data         => portx_tx_data(n).data,
        tx_nlast        => portx_tx_data(n).nlast,
        tx_valid        => portx_tx_data(n).valid,
        tx_ready        => portx_tx_ctrl(n).ready,
        tx_pstart       => portx_tx_ctrl(n).pstart,
        tx_tnow         => portx_tx_ctrl(n).tnow,
        tx_tfreq        => portx_tx_ctrl(n).tfreq,
        tx_macerr       => portx_tx_ctrl(n).txerr,
        tx_reset_p      => portx_tx_ctrl(n).reset_p,
        pause_tx        => pktout_pause(PORT_COUNT+n),
        port_2step      => pktout_2step(PORT_COUNT+n),
        queue_state     => pktout_qstate(8*(PORT_COUNT+n)+7 downto 8*(PORT_COUNT+n)),
        err_overflow    => pktout_overflow(PORT_COUNT+n),
        err_txmac       => pktout_txerror(PORT_COUNT+n),
        err_ptp         => pktout_ptperror(PORT_COUNT+n),
        cfg_cmd         => cfg_cmd,
        cfg_ack         => cfg_ack_tx(PORT_COUNT+n),
        core_clk        => core_clk,
        core_reset_p    => core_reset_sync);
end generate;

-- Consolidate ConfigBus replies.
cfg_ack_all(1) <= cfgbus_merge(cfg_ack_rx);
cfg_ack_all(2) <= cfgbus_merge(cfg_ack_tx);

p_cfgbus : process(cfg_cmd.clk) is
begin
    if rising_edge(cfg_cmd.clk) then
        cfg_ack <= cfgbus_merge(cfg_ack_all);
    end if;
end process;

end router2_core;
