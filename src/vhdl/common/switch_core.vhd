--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation
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
-- scheduler, and MAC lookup table to form the packet-switching pipeline:
--
--      In0--FrmChk--FIFO--+--Scheduler--+--Delay (Data)---+--FIFO--Out0
--      In1--FrmChk--FIFO--+             +--Lookup (Ctrl)--+--FIFO--Out1
--      In2--FrmChk--FIFO--+                               +--FIFO--Out2
--      In3--FrmChk--FIFO--+                               +--FIFO--Out3
--
-- Multiple configurations are possible, selected by generic parameters.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.switch_types.all;
use     work.synchronization.all;

entity switch_core is
    generic (
    ALLOW_JUMBO     : boolean := false; -- Allow jumbo frames? (Size up to 9038 bytes)
    ALLOW_RUNT      : boolean;          -- Allow runt frames? (Size < 64 bytes)
    PORT_COUNT      : integer;          -- Total number of Ethernet ports
    DATAPATH_BYTES  : integer;          -- Width of shared pipeline
    IBUF_KBYTES     : integer := 2;     -- Input buffer size (kilobytes)
    OBUF_KBYTES     : integer;          -- Output buffer size (kilobytes)
    OBUF_PACKETS    : integer := 64;    -- Output buffer max packets
    MAC_LOOKUP_TYPE : string;           -- MAC lookup (BINARY, BRUTE, SIMPLE, ...)
    MAC_TABLE_SIZE  : integer;          -- Max stored MAC addresses
    MAC_LOOKUP_DLY  : integer := 0;     -- Matched delay for MAC lookup? (optional)
    SCRUB_TIMEOUT   : integer := 15);   -- Timeout for stale MAC entries
    port (
    -- Input from each port.
    ports_rx_data   : in  array_rx_m2s(PORT_COUNT-1 downto 0);

    -- Output to each port.
    ports_tx_data   : out array_tx_m2s(PORT_COUNT-1 downto 0);
    ports_tx_ctrl   : in  array_tx_s2m(PORT_COUNT-1 downto 0);

    -- Error events are marked by toggling these bits.
    errvec_t        : out std_logic_vector(SWITCH_ERR_WIDTH-1 downto 0);

    -- System interface.
    scrub_req_t     : in  std_logic;    -- Request MAC-lookup scrub
    core_clk        : in  std_logic;    -- Core datapath clock.
    core_reset_p    : in  std_logic);   -- Core sync. reset
end switch_core;

architecture switch_core of switch_core is

-- Define various local types.
subtype byte_t is std_logic_vector(7 downto 0);
subtype word_t is std_logic_vector(8*DATAPATH_BYTES-1 downto 0);
subtype bcount_t is integer range 0 to DATAPATH_BYTES-1;
subtype bit_array is std_logic_vector(PORT_COUNT-1 downto 0);
type byte_array is array(PORT_COUNT-1 downto 0) of byte_t;
type word_array is array(PORT_COUNT-1 downto 0) of word_t;
type bcount_array is array(PORT_COUNT-1 downto 0) of bcount_t;

-- Frame check.
signal eth_chk_clk      : bit_array;
signal eth_chk_data     : byte_array;
signal eth_chk_write    : bit_array;
signal eth_chk_commit   : bit_array;
signal eth_chk_revert   : bit_array;

-- Input packet FIFO.
signal pktin_data       : word_array;
signal pktin_bcount     : bcount_array;
signal pktin_last       : bit_array;
signal pktin_valid      : bit_array;
signal pktin_ready      : bit_array;
signal pktin_overflow   : bit_array;
signal pktin_rxerror    : bit_array;
signal pktin_crcerror   : bit_array;

-- Round-robin scheduler.
signal sched_error      : std_logic;
signal sched_data       : word_t;
signal sched_bcount     : bcount_t;
signal sched_last       : std_logic;
signal sched_valid      : std_logic;
signal sched_ready      : std_logic;
signal sched_write      : std_logic;
signal sched_select     : integer range 0 to PORT_COUNT-1;

-- MAC lookup and matched delay.
signal macerr_ovr       : std_logic;
signal macerr_tbl       : std_logic;
signal scrub_req        : std_logic;
signal pktout_clk       : bit_array;
signal pktout_data      : word_t;
signal pktout_bcount    : bcount_t;
signal pktout_last      : std_logic;
signal pktout_write     : std_logic;
signal pktout_pdst      : bit_array;
signal pktout_pvalid    : std_logic;
signal pktout_pready    : std_logic;

-- Output packet FIFO
signal pktout_commit    : bit_array;
signal pktout_revert    : bit_array;
signal pktout_overflow  : bit_array;
signal pktout_txerror   : bit_array;

-- Error toggles for switch_aux.
signal errtog_mac_late  : std_logic := '0';
signal errtog_mac_ovr   : std_logic := '0';
signal errtog_mac_tbl   : std_logic := '0';
signal errtog_pkt_crc   : std_logic := '0';
signal errtog_ovr_rx    : std_logic := '0';
signal errtog_ovr_tx    : std_logic := '0';
signal errtog_mii_tx    : std_logic := '0';
signal errtog_mii_rx    : std_logic := '0';

-- Synchronized version of external reset.
signal core_reset_sync  : std_logic;

begin

-- Drive the final error vector:
errvec_t <= errtog_pkt_crc      -- Bit 7
          & errtog_mii_tx       -- Bit 6
          & errtog_mii_rx       -- Bit 5
          & errtog_mac_tbl      -- Bit 4
          & errtog_mac_ovr      -- Bit 3
          & errtog_mac_late     -- Bit 2
          & errtog_ovr_tx       -- Bit 1
          & errtog_ovr_rx;      -- Bit 0

-- Misc utility functions:
p_util : process(core_clk)
begin
    if rising_edge(core_clk) then
        -- Confirm end-of-packet timing constraint holds.
        -- Note: If this error occurs, need a faster MAC lookup implementation.
        if (pktout_write = '1' and pktout_last = '1' and pktout_pvalid = '0') then
            report "MAC-lookup arrived late." severity error;
            errtog_mac_late <= not errtog_mac_late;
        end if;

        -- Convert strobe to toggle as needed.
        if (macerr_ovr = '1') then
            report "MAC-table overflow" severity warning;
            errtog_mac_ovr <= not errtog_mac_ovr;
        end if;
        if (macerr_tbl = '1') then
            report "MAC-table internal error" severity error;
            errtog_mac_tbl <= not errtog_mac_tbl;
        end if;

        -- Consolidate per-port error strobes and convert to toggle.
        if (or_reduce(pktin_crcerror) = '1') then
            report "Packet CRC mismatch" severity warning;
            errtog_pkt_crc <= not errtog_pkt_crc;
        end if;
        if (or_reduce(pktin_overflow) = '1') then
            report "Input buffer overflow" severity warning;
            errtog_ovr_rx <= not errtog_ovr_rx;
        end if;
        if (or_reduce(pktout_overflow) = '1') then
            report "Output buffer overflow" severity warning;
            errtog_ovr_tx <= not errtog_ovr_tx;
        end if;
        if (or_reduce(pktin_rxerror) = '1') then
            report "Input interface error" severity error;
            errtog_mii_rx <= not errtog_mii_rx;
        end if;
        if (or_reduce(pktout_txerror) = '1') then
            report "Output interface error" severity error;
            errtog_mii_tx <= not errtog_mii_tx;
        end if;
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
        clk         => eth_chk_clk(n),
        reset_p     => ports_rx_data(n).reset_p);

    -- Instantiate this port's input FIFO.
    u_fifo : entity work.packet_fifo
        generic map(
        INPUT_BYTES     => 1,
        OUTPUT_BYTES    => DATAPATH_BYTES,
        BUFFER_KBYTES   => IBUF_KBYTES)
        port map(
        in_clk          => eth_chk_clk(n),
        in_data         => eth_chk_data(n),
        in_last_commit  => eth_chk_commit(n),
        in_last_revert  => eth_chk_revert(n),
        in_write        => eth_chk_write(n),
        in_overflow     => open,
        out_clk         => core_clk,
        out_data        => pktin_data(n),
        out_bcount      => pktin_bcount(n),
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
        in_strobe   => eth_chk_revert(n),
        in_clk      => eth_chk_clk(n),
        out_strobe  => pktin_crcerror(n),
        out_clk     => core_clk);
end generate;

----------------------------- SHARED PIPELINE -----------------------
-- Round-robin scheduler chooses which input is active.
u_robin : entity work.round_robin
    generic map(
    INPUT_COUNT     => PORT_COUNT)
    port map(
    in_last         => pktin_last,
    in_valid        => pktin_valid,
    in_ready        => pktin_ready,
    in_select       => sched_select,
    in_error        => sched_error,
    out_last        => sched_last,
    out_valid       => sched_valid,
    out_ready       => sched_ready,
    clk             => core_clk);

sched_data   <= pktin_data(sched_select);
sched_bcount <= pktin_bcount(sched_select);
sched_write  <= sched_valid and sched_ready;

-- Some implementations need a small delay buffer to ensure that
-- MAC-lookup always finishes before end of packet.
u_delay : entity work.packet_delay
    generic map(
    INPUT_BYTES     => DATAPATH_BYTES,
    DELAY_COUNT     => MAC_LOOKUP_DLY)
    port map(
    in_data         => sched_data,
    in_bcount       => sched_bcount,
    in_last         => sched_last,
    in_write        => sched_write,
    out_data        => pktout_data,
    out_bcount      => pktout_bcount,
    out_last        => pktout_last,
    out_write       => pktout_write,
    io_clk          => core_clk,
    reset_p         => core_reset_sync);

-- MAC-address lookup (one of several implementation options).
u_lookup : entity work.mac_lookup_generic
    generic map(
    IMPL_TYPE       => MAC_LOOKUP_TYPE,
    INPUT_WIDTH     => 8*DATAPATH_BYTES,
    PORT_COUNT      => PORT_COUNT,
    TABLE_SIZE      => MAC_TABLE_SIZE,
    SCRUB_TIMEOUT   => SCRUB_TIMEOUT)
    port map(
    in_psrc         => sched_select,
    in_data         => sched_data,
    in_last         => sched_last,
    in_valid        => sched_valid,
    in_ready        => sched_ready,
    out_pdst        => pktout_pdst,
    out_valid       => pktout_pvalid,
    out_ready       => pktout_pready,
    scrub_req       => scrub_req,
    scrub_busy      => open,
    scrub_remove    => open,
    error_full      => macerr_ovr,
    error_table     => macerr_tbl,
    clk             => core_clk,
    reset_p         => core_reset_sync);

pktout_pready <= pktout_write and pktout_last;

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

    -- Drive the commit / revert strobes for this channel.
    pktout_commit(n) <= pktout_write and pktout_last and pktout_pdst(n);
    pktout_revert(n) <= pktout_write and pktout_last and not pktout_pdst(n);

    -- Instantiate this port's output FIFO.
    u_fifo : entity work.packet_fifo
        generic map(
        INPUT_BYTES     => DATAPATH_BYTES,
        OUTPUT_BYTES    => 1,
        BUFFER_KBYTES   => OBUF_KBYTES,
        MAX_PACKETS     => OBUF_PACKETS)
        port map(
        in_clk          => core_clk,
        in_data         => pktout_data,
        in_bcount       => pktout_bcount,
        in_last_commit  => pktout_commit(n),
        in_last_revert  => pktout_revert(n),
        in_write        => pktout_write,
        in_overflow     => pktout_overflow(n),
        out_clk         => pktout_clk(n),
        out_data        => ports_tx_data(n).data,
        out_bcount      => open,
        out_last        => ports_tx_data(n).last,
        out_valid       => ports_tx_data(n).valid,
        out_ready       => ports_tx_ctrl(n).ready,
        out_overflow    => open,
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
