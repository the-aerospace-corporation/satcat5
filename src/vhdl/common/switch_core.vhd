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
    ALLOW_JUMBO     : boolean := false; -- Allow jumbo frames? (Size up to 9038 bytes)
    ALLOW_RUNT      : boolean;          -- Allow runt frames? (Size < 64 bytes)
    PORT_COUNT      : positive;         -- Total number of Ethernet ports
    DATAPATH_BYTES  : positive;         -- Width of shared pipeline
    IBUF_KBYTES     : positive := 2;    -- Input buffer size (kilobytes)
    HBUF_KBYTES     : natural := 0;     -- High-priority output buffer (kilobytes)
    OBUF_KBYTES     : positive;         -- Normal-priority output buffer (kilobytes)
    IBUF_PACKETS    : positive := 64;   -- Input buffer max packets
    OBUF_PACKETS    : positive := 64;   -- Output buffer max packets
    MAC_TABLE_SIZE  : positive := 64;   -- Max stored MAC addresses
    PRI_TABLE_SIZE  : positive := 16);  -- Max high-priority EtherTypes
    port (
    -- Input from each port.
    ports_rx_data   : in  array_rx_m2s(PORT_COUNT-1 downto 0);

    -- Output to each port.
    ports_tx_data   : out array_tx_s2m(PORT_COUNT-1 downto 0);
    ports_tx_ctrl   : in  array_tx_m2s(PORT_COUNT-1 downto 0);

    -- Error events are marked by toggling these bits.
    err_ports       : out array_port_error(PORT_COUNT-1 downto 0);
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
subtype byte_t is std_logic_vector(7 downto 0);
subtype word_t is std_logic_vector(8*DATAPATH_BYTES-1 downto 0);
subtype nlast_t is integer range 0 to DATAPATH_BYTES;
subtype bit_array is std_logic_vector(PORT_COUNT-1 downto 0);
type byte_array is array(PORT_COUNT-1 downto 0) of byte_t;
type word_array is array(PORT_COUNT-1 downto 0) of word_t;
type nlast_array is array(PORT_COUNT-1 downto 0) of nlast_t;

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

-- Frame check.
signal eth_chk_clk      : bit_array;
signal eth_chk_data     : byte_array;
signal eth_chk_write    : bit_array;
signal eth_chk_commit   : bit_array;
signal eth_chk_revert   : bit_array;
signal eth_chk_error    : bit_array;

-- Input packet FIFO.
signal pktin_data       : word_array;
signal pktin_nlast      : nlast_array;
signal pktin_last       : bit_array;
signal pktin_valid      : bit_array;
signal pktin_ready      : bit_array;
signal pktin_overflow   : bit_array;
signal pktin_rxerror    : bit_array;
signal pktin_crcerror   : bit_array;

-- Round-robin scheduler.
signal sched_error      : std_logic;
signal sched_data       : word_t;
signal sched_nlast      : nlast_t;
signal sched_write      : std_logic;
signal sched_select     : integer range 0 to PORT_COUNT-1;

-- MAC lookup and matched delay.
signal macerr_dup       : std_logic;
signal macerr_int       : std_logic;
signal macerr_tbl       : std_logic;
signal scrub_req        : std_logic;
signal pktout_clk       : bit_array;
signal pktout_data      : word_t;
signal pktout_nlast     : nlast_t;
signal pktout_write     : std_logic;
signal pktout_hipri     : std_logic;
signal pktout_pdst      : bit_array;

-- Output packet FIFO
signal pktout_overflow  : bit_array;
signal pktout_txerror   : bit_array;
signal pktout_pause     : bit_array;

-- Error toggles for switch_aux and port_statistics.
signal err_prt          : array_port_error(PORT_COUNT-1 downto 0) := (others => PORT_ERROR_NONE);
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
        if (or_reduce(pktin_crcerror) = '1') then
            report "Packet CRC mismatch" severity warning;
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
        for n in PORT_COUNT-1 downto 0 loop
            if (pktin_rxerror(n) = '1' or pktout_txerror(n) = '1') then
                err_prt(n).mii_err <= not err_prt(n).mii_err;
            end if;
            if (pktin_overflow(n) = '1') then
                err_prt(n).ovr_rx <= not err_prt(n).ovr_rx;
            end if;
            if (pktout_overflow(n) = '1') then
                err_prt(n).ovr_tx <= not err_prt(n).ovr_tx;
            end if;
            if (pktin_crcerror(n) = '1') then
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
-- For each input port...
gen_input : for n in PORT_COUNT-1 downto 0 generate
    -- Force clock assignment, as a workaround for bugs in Vivado XSIM.
    -- Clocks that come directly from a record do not correctly propagate
    -- process sensitivity events in XSIM 2015.4 and 2016.3.
    -- This has no effect on synthesis results.
    eth_chk_clk(n) <= to_01_std(ports_rx_data(n).clk);

    -- Optionally monitor incoming traffic for PAUSE requests.
    gen_pause1 : if SUPPORT_PAUSE generate
        u_pause : entity work.eth_pause_ctrl
            generic map(
            REFCLK_HZ   => CORE_CLK_HZ)
            port map(
            port_rx     => ports_rx_data(n),
            pause_tx    => pktout_pause(n),
            ref_clk     => core_clk,
            reset_p     => core_reset_sync);
    end generate;
    
    gen_pause0 : if not SUPPORT_PAUSE generate
        pktout_pause(n) <= '0';
    end generate;

    -- Check each frame and drive the commit / revert strobes.
    u_frmchk : entity work.eth_frame_check
        generic map(
        ALLOW_JUMBO => ALLOW_JUMBO,
        ALLOW_RUNT  => ALLOW_RUNT)
        port map(
        in_data     => ports_rx_data(n).data,
        in_last     => ports_rx_data(n).last,
        in_write    => ports_rx_data(n).write,
        out_data    => eth_chk_data(n),
        out_write   => eth_chk_write(n),
        out_commit  => eth_chk_commit(n),
        out_revert  => eth_chk_revert(n),
        out_error   => eth_chk_error(n),
        clk         => eth_chk_clk(n),
        reset_p     => ports_rx_data(n).reset_p);

    -- Instantiate this port's input FIFO.
    u_fifo : entity work.fifo_packet
        generic map(
        INPUT_BYTES     => 1,
        OUTPUT_BYTES    => DATAPATH_BYTES,
        BUFFER_KBYTES   => IBUF_KBYTES,
        MAX_PACKETS     => IBUF_PACKETS,
        MAX_PKT_BYTES   => get_max_frame)
        port map(
        in_clk          => eth_chk_clk(n),
        in_data         => eth_chk_data(n),
        in_last_commit  => eth_chk_commit(n),
        in_last_revert  => eth_chk_revert(n),
        in_write        => eth_chk_write(n),
        in_overflow     => open,
        out_clk         => core_clk,
        out_data        => pktin_data(n),
        out_nlast       => pktin_nlast(n),
        out_last        => pktin_last(n),
        out_valid       => pktin_valid(n),
        out_ready       => pktin_ready(n),
        out_overflow    => pktin_overflow(n),
        reset_p         => ports_rx_data(n).reset_p);

    -- Detect error strobes from MII Rx.
    u_err : sync_toggle2pulse
        generic map(RISING_ONLY => true)
        port map(
        in_toggle   => ports_rx_data(n).rxerr,
        out_strobe  => pktin_rxerror(n),
        out_clk     => core_clk);
    u_pkt : sync_pulse2pulse
        port map(
        in_strobe   => eth_chk_error(n),
        in_clk      => eth_chk_clk(n),
        out_strobe  => pktin_crcerror(n),
        out_clk     => core_clk);
end generate;

----------------------------- SHARED PIPELINE -----------------------
-- Round-robin scheduler chooses which input is active.
u_robin : entity work.packet_round_robin
    generic map(
    INPUT_COUNT     => PORT_COUNT)
    port map(
    in_last         => pktin_last,
    in_valid        => pktin_valid,
    in_ready        => pktin_ready,
    in_select       => sched_select,
    in_error        => sched_error,
    out_valid       => sched_write,
    out_ready       => '1',
    clk             => core_clk);

sched_data   <= pktin_data(sched_select);
sched_nlast  <= pktin_nlast(sched_select);

-- Core MAC pipeline
u_mac : entity work.mac_core
    generic map(
    DEV_ADDR        => DEV_ADDR,
    INPUT_BYTES     => DATAPATH_BYTES,
    PORT_COUNT      => PORT_COUNT,
    CORE_CLK_HZ     => CORE_CLK_HZ,
    MIN_FRM_BYTES   => get_min_frame,
    MAX_FRM_BYTES   => get_max_frame,
    MAC_TABLE_SIZE  => MAC_TABLE_SIZE,
    PRI_TABLE_SIZE  => get_pri_table_size)
    port map(
    in_psrc         => sched_select,
    in_nlast        => sched_nlast,
    in_data         => sched_data,
    in_write        => sched_write,
    out_data        => pktout_data,
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
-- For each output port...
gen_output : for n in PORT_COUNT-1 downto 0 generate
    -- Clock workaround (refer to eth_chk_clk for details).
    pktout_clk(n) <= to_01_std(ports_tx_ctrl(n).clk);

    -- Instantiate this port's output FIFO.
    u_fifo : entity work.fifo_priority
        generic map(
        INPUT_BYTES     => DATAPATH_BYTES,
        BUFF_HI_KBYTES  => HBUF_KBYTES,
        BUFF_LO_KBYTES  => OBUF_KBYTES,
        MAX_PACKETS     => OBUF_PACKETS,
        MAX_PKT_BYTES   => get_max_frame)
        port map(
        in_clk          => core_clk,
        in_data         => pktout_data,
        in_nlast        => pktout_nlast,
        in_last_keep    => pktout_pdst(n),
        in_last_hipri   => pktout_hipri,
        in_write        => pktout_write,
        in_overflow     => pktout_overflow(n),
        out_clk         => pktout_clk(n),
        out_data        => ports_tx_data(n).data,
        out_last        => ports_tx_data(n).last,
        out_valid       => ports_tx_data(n).valid,
        out_ready       => ports_tx_ctrl(n).ready,
        async_pause     => pktout_pause(n),
        reset_p         => ports_tx_ctrl(n).reset_p);

    -- Detect error strobes from MII Tx.
    u_err : sync_toggle2pulse
        generic map(RISING_ONLY => true)
        port map(
        in_toggle   => ports_tx_ctrl(n).txerr,
        out_strobe  => pktout_txerror(n),
        out_clk     => core_clk);
end generate;

end switch_core;
