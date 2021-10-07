--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation
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
-- If enabled, the configuration register map is as follows
--  * REGADDR = 0:  Number of ports (read-only)
--  * REGADDR = 1:  Datapath width, in bits (read-only)
--  * REGADDR = 2:  Core clock frequency, in Hz (read-only)
--  * REGADDR = 3:  MAC-address table size (read-only)
--  * REGADDR = 4:  Promisicuous port mask (read-write)
--      Ports in this mode attempt to receive almost all network packets,
--      regardless of destination.  Writing a bit-mask enables this mode
--      for the designated ports. (LSB = Port #0, MSB = Port #31, etc.)
--  * REGADDR = 5:  Packet prioritization by EtherType (read-write, optional)
--      This register is enabled only if PRI_TABLE_SIZE > 0.
--      Refer to "mac_priority" for details.
--  * REGADDR = 6:  Packet-counting for diagnostics (read-write)
--      Refer to "mac_counter" for details.
--  * REGADDR = 7:  Packet size limits
--      Bits 31-16: Maximum frame size (in bytes)
--      Bits 15-00: Minimum frame size (in bytes)
--
-- Unit-test coverage for this block is provided by "switch_core_tb".
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.tcam_constants.all;

entity mac_core is
    generic (
    DEV_ADDR        : integer;          -- Device address for all registers
    INPUT_BYTES     : positive;         -- Width of main data port
    PORT_COUNT      : positive;         -- Number of Ethernet ports
    CORE_CLK_HZ     : positive;         -- Core clock frequency (Hz)
    MIN_FRM_BYTES   : positive;         -- Minimum frame size
    MAX_FRM_BYTES   : positive;         -- Maximum frame size
    MAC_TABLE_SIZE  : positive;         -- Max stored MAC addresses
    PRI_TABLE_SIZE  : natural;          -- Max high-priority EtherTypes (0 = disable)
    MISS_BCAST      : std_logic := '1'; -- Broadcast or drop unknown MAC?
    IGMP_TIMEOUT    : positive := 63;   -- IGMP timeout (0 = disable)
    CACHE_POLICY    : repl_policy := TCAM_REPL_PLRU);
    port (
    -- Main input
    -- PSRC is the input port-index and must be held for the full frame.
    in_psrc         : in  integer range 0 to PORT_COUNT-1;
    in_nlast        : in  integer range 0 to INPUT_BYTES;
    in_data         : in  std_logic_vector(8*INPUT_BYTES-1 downto 0);
    in_write        : in  std_logic;

    -- Main output, with end-of-frame strobes for each port.
    out_data        : out std_logic_vector(8*INPUT_BYTES-1 downto 0);
    out_nlast       : out integer range 0 to INPUT_BYTES;
    out_write       : out std_logic;
    out_priority    : out std_logic;
    out_keep        : out std_logic_vector(PORT_COUNT-1 downto 0);

    -- Configuration interface
    cfg_cmd         : in  cfgbus_cmd := CFGBUS_CMD_NULL;
    cfg_ack         : out cfgbus_ack;   -- Optional ConfigBus interface
    scrub_req       : in  std_logic;    -- Timekeeping strobe (~1 Hz)
    error_change    : out std_logic;    -- MAC address changed ports
    error_other     : out std_logic;    -- Other internal error
    error_table     : out std_logic;    -- Table integrity check failed

    -- System interface
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end mac_core;

architecture mac_core of mac_core is

-- Define register addresses:
constant REGADDR_PORT_COUNT     : cfgbus_regaddr := 0;
constant REGADDR_DATA_WIDTH     : cfgbus_regaddr := 1;
constant REGADDR_CORE_CLOCK     : cfgbus_regaddr := 2;
constant REGADDR_TABLE_SIZE     : cfgbus_regaddr := 3;
constant REGADDR_PROMISCUOUS    : cfgbus_regaddr := 4;
constant REGADDR_PRIORITY       : cfgbus_regaddr := 5;
constant REGADDR_PKT_COUNT      : cfgbus_regaddr := 6;
constant REGADDR_FRAME_SIZE     : cfgbus_regaddr := 7;

-- Convenience types:
subtype data_word is std_logic_vector(8*INPUT_BYTES-1 downto 0);
subtype port_mask is std_logic_vector(PORT_COUNT-1 downto 0);

-- Main datapath
signal buf_psrc     : integer range 0 to PORT_COUNT-1 := 0;
signal buf_nlast    : integer range 0 to INPUT_BYTES := INPUT_BYTES;
signal buf_data     : data_word := (others => '0');
signal buf_last     : std_logic := '0';
signal buf_write    : std_logic := '0';
signal buf_wcount   : mac_bcount_t := 0; 
signal out_nlast_i  : integer range 0 to INPUT_BYTES;
signal out_write_i  : std_logic;
signal packet_done  : std_logic;

-- MAC-address lookup
signal lookup_mask  : port_mask;
signal lookup_valid : std_logic;

-- Packet-priority lookup (optional)
signal pri_hipri    : std_logic := '0';
signal pri_valid    : std_logic := '1';
signal pri_error    : std_logic := '0';

-- IGMP-snooping (optional)
signal igmp_mask    : port_mask := (others => '1');
signal igmp_valid   : std_logic := '1';
signal igmp_error   : std_logic := '0';

-- Promiscuous-port mode (optional)
signal cfg_prword   : cfgbus_word := (others => '0');
signal cfg_prmask   : port_mask := (others => '0');

-- ConfigBus combining.
signal cfg_acks     : cfgbus_ack_array(0 to 7) := (others => cfgbus_idle);

begin

-- General-purpose ConfigBus registers:
gen_cfgbus : if (DEV_ADDR > CFGBUS_ADDR_NONE) generate
    -- Read-only configuration reporting.
    -- See top comment for complete register map.
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
        reg_val     => i2s(8*INPUT_BYTES, CFGBUS_WORD_SIZE));
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
        INPUT_BYTES => INPUT_BYTES)
        port map(
        in_wcount   => buf_wcount,
        in_data     => buf_data,
        in_last     => buf_last,
        in_write    => buf_write,
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(5),
        clk         => clk,
        reset_p     => reset_p);

    -- Promiscuous-port configuration register
    u_register : cfgbus_register_sync
        generic map(
        DEVADDR     => DEV_ADDR,
        REGADDR     => REGADDR_PROMISCUOUS,
        WR_ATOMIC   => true,
        WR_MASK     => cfgbus_mask_lsb(PORT_COUNT))
        port map(
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(6),
        sync_clk    => clk,
        sync_val    => cfg_prword);

    -- Zero-pad or truncate the CPU register as needed.
    cfg_prmask <= resize(cfg_prword, PORT_COUNT);
end generate;


-- Buffer incoming data for better routing and timing.
p_buff : process(clk)
    constant WCOUNT_MAX : mac_bcount_t := mac_wcount_max(INPUT_BYTES);
begin
    if rising_edge(clk) then
        -- Buffer incoming data.
        buf_psrc    <= in_psrc;
        buf_nlast   <= in_nlast;
        buf_data    <= in_data;
        buf_last    <= bool2bit(in_nlast > 0);
        buf_write   <= in_write and not reset_p;

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
    INPUT_BYTES     => INPUT_BYTES,
    DELAY_COUNT     => 15)
    port map(
    in_data         => buf_data,
    in_nlast        => buf_nlast,
    in_write        => buf_write,
    out_data        => out_data,
    out_nlast       => out_nlast_i,
    out_write       => out_write_i,
    io_clk          => clk,
    reset_p         => reset_p);

-- Final "KEEP" flag is the bitwise-AND of all port masks.
out_write       <= out_write_i;
out_nlast       <= out_nlast_i;
out_priority    <= pri_hipri;
out_keep        <= lookup_mask and igmp_mask;
error_other     <= igmp_error or pri_error;
packet_done     <= out_write_i and bool2bit(out_nlast_i > 0);

-- MAC-address lookup
u_lookup : entity work.mac_lookup
    generic map(
    INPUT_BYTES     => INPUT_BYTES,
    PORT_COUNT      => PORT_COUNT,
    TABLE_SIZE      => MAC_TABLE_SIZE,
    MISS_BCAST      => MISS_BCAST,
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
    cfg_prmask      => cfg_prmask,
    error_change    => error_change,
    error_table     => error_table,
    clk             => clk,
    reset_p         => reset_p);

-- IGMP snooping (optional)
gen_igmp : if (IGMP_TIMEOUT > 0) generate
    u_igmp : entity work.mac_igmp_simple
        generic map(
        INPUT_BYTES     => INPUT_BYTES,
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

-- Packet-priority lookup (optional)
gen_priority : if (DEV_ADDR > CFGBUS_ADDR_NONE
               and PRI_TABLE_SIZE > 0) generate
    u_priority : entity work.mac_priority
        generic map(
        DEVADDR     => DEV_ADDR,
        REGADDR     => REGADDR_PRIORITY,
        INPUT_BYTES => INPUT_BYTES,
        TABLE_SIZE  => PRI_TABLE_SIZE)
        port map(
        in_wcount   => buf_wcount,
        in_data     => buf_data,
        in_last     => buf_last,
        in_write    => buf_write,
        out_pri     => pri_hipri,
        out_valid   => pri_valid,
        out_ready   => packet_done,
        out_error   => pri_error,
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(7),
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
            assert (pri_valid = '1')
                report "LATE Priority" severity error;
        end if;
    end if;
end process;

end mac_core;
