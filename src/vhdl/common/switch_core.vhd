--------------------------------------------------------------------------
-- Copyright 2019, 2020, 2021 The Aerospace Corporation
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
-- Core packet-switching pipeline
--
-- This module ties together the frame-check, packet-FIFO, round-robin
-- scheduler, and MAC core form the packet-switching pipeline:
--
--      In0--FrmChk--FIFO--+--Scheduler--+--MAC Core --+--FIFO--Out0
--      In1--FrmChk--FIFO--+                           +--FIFO--Out1
--      In2--FrmChk--FIFO--+                           +--FIFO--Out2
--      In3--FrmChk--FIFO--+                           +--FIFO--Out3
--
-- Many configurations are possible, selected by generic parameters.
--
-- Optional managed-switch features (e.g., packet priority, promiscuous
-- ports, etc.) use ConfigBus.  Each switch_core should use a unique
-- device-address.  The register-map is defined in mac_core.vhd.
--
-- All ports use the same input and output buffer sizes.  See FAQ for
-- more information on how to choose these parameters.  Prioritization
-- uses a second output FIFO on each port, typically much smaller than
-- the primary output FIFO.  (High-priority mode should never be used
-- for bulk traffic.)  The FIFO size (HBUF_KBYTES) is in addition to
-- and independent of the primary output buffer size (OBUF_KBYTES).
-- This feature is disabled if HBUF_KBYTES = 0.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity switch_core is
    generic (
    DEV_ADDR        : integer := CFGBUS_ADDR_NONE;  -- ConfigBus device address
    CORE_CLK_HZ     : positive;         -- Rate of core_clk (Hz)
    SUPPORT_PAUSE   : boolean := true;  -- Support or ignore 802.3x "PAUSE" frames?
    SUPPORT_PTP     : boolean := false; -- Support precise frame timestamps?
    SUPPORT_VLAN    : boolean := false; -- Support or ignore 802.1q VLAN tags?
    ALLOW_JUMBO     : boolean := false; -- Allow jumbo frames? (Size up to 9038 bytes)
    ALLOW_RUNT      : boolean := false; -- Allow runt frames? (Size < 64 bytes)
    PORT_COUNT      : natural := 0;     -- Total standard Ethernet ports
    PORTX_COUNT     : natural := 0;     -- Total 10 Gbps Ethernet ports
    DATAPATH_BYTES  : positive;         -- Width of shared pipeline
    IBUF_KBYTES     : positive := 2;    -- Input buffer size (kilobytes)
    HBUF_KBYTES     : natural := 0;     -- High-priority output buffer (kilobytes)
    OBUF_KBYTES     : positive;         -- Normal-priority output buffer (kilobytes)
    IBUF_PACKETS    : positive := 64;   -- Input buffer max packets
    OBUF_PACKETS    : positive := 64;   -- Output buffer max packets
    MAC_TABLE_SIZE  : positive := 64;   -- Max stored MAC addresses
    PRI_TABLE_SIZE  : positive := 16);  -- Max high-priority EtherTypes
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
    err_switch      : out switch_error_t;
    errvec_t        : out switch_errvec_t;  -- Legacy compatibility

    -- Configuration interface
    cfg_cmd         : in  cfgbus_cmd := CFGBUS_CMD_NULL;
    cfg_ack         : out cfgbus_ack;   -- Optional ConfigBus interface
    scrub_req_t     : in  std_logic;    -- Request MAC-lookup scrub

    -- System interface.
    core_clk        : in  std_logic;    -- Core datapath clock
    core_reset_p    : in  std_logic);   -- Core async reset
end switch_core;

architecture switch_core of switch_core is

-- Define various local types.
constant PORT_TOTAL : natural := PORT_COUNT + PORTX_COUNT;
subtype word_t is std_logic_vector(8*DATAPATH_BYTES-1 downto 0);
subtype nlast_t is integer range 0 to DATAPATH_BYTES;
subtype bit_array is std_logic_vector(PORT_TOTAL-1 downto 0);
type meta_array is array(PORT_TOTAL-1 downto 0) of switch_meta_t;
type word_array is array(PORT_TOTAL-1 downto 0) of word_t;
type nlast_array is array(PORT_TOTAL-1 downto 0) of nlast_t;

-- Minimum frame size for checking incoming frames.
function get_min_frame return positive is
begin
    if ALLOW_RUNT then
        return MIN_RUNT_BYTES;
    else
        return MIN_FRAME_BYTES;
    end if;
end function;

-- Maximum frame size for checking incoming frames.
function get_max_frame return positive is
begin
    if ALLOW_JUMBO then
        return MAX_JUMBO_BYTES;
    else
        return MAX_FRAME_BYTES;
    end if;
end function;

-- Maximum number of priority packet types.
function get_pri_table_size return natural is
begin
    if (HBUF_KBYTES > 0) then
        return PRI_TABLE_SIZE;
    else
        return 0;
    end if;
end function;

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
signal pktin_rxerror    : bit_array;

-- Round-robin scheduler.
signal sched_error      : std_logic;
signal sched_data       : word_t;
signal sched_meta       : switch_meta_t;
signal sched_nlast      : nlast_t;
signal sched_write      : std_logic;
signal sched_select     : integer range 0 to PORT_TOTAL-1;

-- MAC lookup and matched delay.
signal macerr_dup       : std_logic;
signal macerr_int       : std_logic;
signal macerr_tbl       : std_logic;
signal scrub_req        : std_logic;
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
signal pktout_pause     : bit_array;

-- Error toggles for switch_aux and port_statistics.
signal err_prt          : array_port_error(PORT_TOTAL-1 downto 0) := (others => PORT_ERROR_NONE);
signal err_sw           : switch_error_t := SWITCH_ERROR_NONE;

-- Synchronized version of external reset.
signal core_reset_sync  : std_logic;

begin

-- Drive the final error vectors:
err_ports   <= err_prt;
err_switch  <= err_sw;
errvec_t    <= swerr2vector(err_sw);

-- Error reporting and aggregation:
p_err_sw : process(core_clk)
begin
    if rising_edge(core_clk) then
        -- Convert strobe to toggle as needed.
        if (macerr_dup = '1') then
            report "MAC-pipeline duplicate or port change" severity warning;
            err_sw.mac_dup <= not err_sw.mac_dup;
        end if;
        if (macerr_int = '1') then
            report "MAC-pipeline internal error" severity error;
            err_sw.mac_int <= not err_sw.mac_int;
        end if;
        if (macerr_tbl = '1') then
            report "MAC-pipeline table error" severity error;
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
        SUPPORT_PAUSE   => SUPPORT_PAUSE,
        SUPPORT_PTP     => SUPPORT_PTP,
        SUPPORT_VLAN    => SUPPORT_VLAN,
        ALLOW_JUMBO     => ALLOW_JUMBO,
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
        SUPPORT_PAUSE   => SUPPORT_PAUSE,
        SUPPORT_PTP     => SUPPORT_PTP,
        SUPPORT_VLAN    => SUPPORT_VLAN,
        ALLOW_JUMBO     => ALLOW_JUMBO,
        ALLOW_RUNT      => ALLOW_RUNT,
        INPUT_BYTES     => 8,
        OUTPUT_BYTES    => DATAPATH_BYTES,
        IBUF_KBYTES     => IBUF_KBYTES,
        IBUF_PACKETS    => IBUF_PACKETS)
        port map(
        rx_clk          => pktin_clk(PORT_COUNT+n),
        rx_data         => portx_rx_data(n).data,
        --???
        rx_nlast        => portx_rx_data(n).nlast,
        rx_write        => portx_rx_data(n).write,
        rx_macerr       => portx_rx_data(n).rxerr,
        rx_rate         => portx_rx_data(n).rate,
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
    out_valid       => sched_write,
    out_ready       => '1',
    clk             => core_clk);

sched_data  <= pktin_data(sched_select);
sched_meta  <= pktin_meta(sched_select);
sched_nlast <= pktin_nlast(sched_select);

-- Core MAC pipeline
u_mac : entity work.mac_core
    generic map(
    DEV_ADDR        => DEV_ADDR,
    IO_BYTES        => DATAPATH_BYTES,
    PORT_COUNT      => PORT_TOTAL,
    CORE_CLK_HZ     => CORE_CLK_HZ,
    SUPPORT_VLAN    => SUPPORT_VLAN,
    MIN_FRM_BYTES   => get_min_frame,
    MAX_FRM_BYTES   => get_max_frame,
    MAC_TABLE_SIZE  => MAC_TABLE_SIZE,
    PRI_TABLE_SIZE  => get_pri_table_size)
    port map(
    in_psrc         => sched_select,
    in_data         => sched_data,
    in_meta         => sched_meta,
    in_nlast        => sched_nlast,
    in_write        => sched_write,
    out_data        => pktout_data,
    out_meta        => pktout_meta,
    out_nlast       => pktout_nlast,
    out_write       => pktout_write,
    out_priority    => pktout_hipri,
    out_keep        => pktout_pdst,
    cfg_cmd         => cfg_cmd,
    cfg_ack         => cfg_ack,
    scrub_req       => scrub_req,
    error_change    => macerr_dup,
    error_other     => macerr_int,
    error_table     => macerr_tbl,
    clk             => core_clk,
    reset_p         => core_reset_sync);

u_scrub_req : sync_toggle2pulse
    port map(
    in_toggle   => scrub_req_t,
    out_strobe  => scrub_req,
    out_clk     => core_clk);

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
        ALLOW_JUMBO     => ALLOW_JUMBO,
        ALLOW_RUNT      => ALLOW_RUNT,
        INPUT_BYTES     => DATAPATH_BYTES,
        OUTPUT_BYTES    => 1,
        HBUF_KBYTES     => HBUF_KBYTES,
        OBUF_KBYTES     => OBUF_KBYTES,
        OBUF_PACKETS    => OBUF_PACKETS)
        port map(
        in_data         => pktout_data,
        in_meta         => pktout_meta,
        in_nlast        => pktout_nlast,
        in_keep         => pktout_pdst(n),
        in_hipri        => pktout_hipri,
        in_write        => pktout_write,
        tx_clk          => pktout_clk(n),
        tx_data         => ports_tx_data(n).data,
        tx_last         => ports_tx_data(n).last,
        tx_valid        => ports_tx_data(n).valid,
        tx_ready        => ports_tx_ctrl(n).ready,
        tx_macerr       => ports_tx_ctrl(n).txerr,
        tx_reset_p      => ports_tx_ctrl(n).reset_p,
        pause_tx        => pktout_pause(n),
        err_overflow    => pktout_overflow(n),
        err_txmac       => pktout_txerror(n),
        cfg_cmd         => cfg_cmd,
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
        ALLOW_JUMBO     => ALLOW_JUMBO,
        ALLOW_RUNT      => ALLOW_RUNT,
        INPUT_BYTES     => DATAPATH_BYTES,
        OUTPUT_BYTES    => 8,
        HBUF_KBYTES     => HBUF_KBYTES,
        OBUF_KBYTES     => OBUF_KBYTES,
        OBUF_PACKETS    => OBUF_PACKETS)
        port map(
        in_data         => pktout_data,
        in_meta         => pktout_meta,
        in_nlast        => pktout_nlast,
        in_keep         => pktout_pdst(PORT_COUNT+n),
        in_hipri        => pktout_hipri,
        in_write        => pktout_write,
        tx_clk          => pktout_clk(PORT_COUNT+n),
        tx_data         => portx_tx_data(n).data,
        tx_nlast        => portx_tx_data(n).nlast,
        tx_valid        => portx_tx_data(n).valid,
        tx_ready        => portx_tx_ctrl(n).ready,
        tx_macerr       => portx_tx_ctrl(n).txerr,
        tx_reset_p      => portx_tx_ctrl(n).reset_p,
        pause_tx        => pktout_pause(PORT_COUNT+n),
        err_overflow    => pktout_overflow(PORT_COUNT+n),
        err_txmac       => pktout_txerror(PORT_COUNT+n),
        cfg_cmd         => cfg_cmd,
        core_clk        => core_clk,
        core_reset_p    => core_reset_sync);
end generate;

end switch_core;
