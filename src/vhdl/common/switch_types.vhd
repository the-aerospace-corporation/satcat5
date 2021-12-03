--------------------------------------------------------------------------
-- Copyright 2019, 2020 The Aerospace Corporation
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
-- Data-type definitions used for the switch core.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

package SWITCH_TYPES is
    -- Rx ports must report their estimated line-rate.
    -- (This is used for PAUSE-frames and other real-time calculations.)
    subtype port_rate_t is std_logic_vector(15 downto 0);

    -- Convert line rate (Mbps) to the rate word.
    function get_rate_word(rate_mbps : positive) return port_rate_t;
    constant RATE_WORD_NULL : port_rate_t := (others => '0');

    -- Rx ports should also report diagnostic status flags.
    -- Each bit is asynchronous with no specific meaning; blocks can use them
    -- to report status to a CPU or other supervisor if desired.
    subtype port_status_t is std_logic_vector(7 downto 0);
    constant STATUS_NULL : port_status_t := (others => '0');

    -- Define the internal timestamp format used to measure propagation
    -- delay for IEEE 1588 Precision Time Protocol (PTP).  Resolution is
    -- in 1/256th-nanosecond increments with rollover every ~4.3 seconds.
    constant TSTAMP_WIDTH : integer := 40;
    subtype tstamp_t is unsigned(TSTAMP_WIDTH-1 downto 0);

    -- Constants for various common time increments.
    -- Note: Some care required to handle avoid integers > 2^31.
    constant TSTAMP_ONE_NSEC    : tstamp_t := to_unsigned(256, TSTAMP_WIDTH);
    constant TSTAMP_ONE_USEC    : tstamp_t := to_unsigned(256_000, TSTAMP_WIDTH);
    constant TSTAMP_ONE_MSEC    : tstamp_t := to_unsigned(256_000_000, TSTAMP_WIDTH);
    constant TSTAMP_ONE_SEC     : tstamp_t :=
        resize(to_unsigned(1000, 10) * TSTAMP_ONE_MSEC, TSTAMP_WIDTH);

    -- Given nominal clock frequency in Hz, calculate increment per clock.
    function get_tstamp_incr(clk_hz : positive) return tstamp_t;

    -- Structure for per-frame metadata.
    type switch_meta_t is record
        tstamp  : tstamp_t;
        vtag    : vlan_hdr_t;
    end record;

    constant SWITCH_META_NULL : switch_meta_t := (
        tstamp  => (others => '0'),
        vtag    => (others => '0'));

    -- Port definition for 1 GbE and below:
    -- Note: "M2S" = MAC/PHY to Switch, "S2M" = Switch to MAC/PHY.
    type port_rx_m2s is record
        clk     : std_logic;
        data    : byte_t;
        last    : std_logic;
        write   : std_logic;
        rxerr   : std_logic;
        rate    : port_rate_t;
        status  : port_status_t;
        reset_p : std_logic;
    end record;     -- From MAC/PHY to switch (Rx-data)

    type port_tx_s2m is record
        data    : byte_t;
        last    : std_logic;
        valid   : std_logic;
    end record;     -- From switch to MAC/PHY (Tx-data)

    type port_tx_m2s is record
        clk     : std_logic;
        ready   : std_logic;
        txerr   : std_logic;
        reset_p : std_logic;
    end record;     -- From MAC/PHY to switch (Tx-ctrl)

    constant RX_M2S_IDLE : port_rx_m2s :=
        ('0', (others => '0'), '0', '0', '0', RATE_WORD_NULL, STATUS_NULL, '0');
    constant TX_S2M_IDLE : port_tx_s2m :=
        ((others => '0'), '0', '0');
    constant TX_M2S_IDLE : port_tx_m2s :=
        ('0', '0', '0', '0');

    -- Port definition for 10 GbE:
    type port_rx_m2sx is record
        clk     : std_logic;
        data    : xword_t;
        nlast   : xlast_i;
        write   : std_logic;
        rxerr   : std_logic;
        rate    : port_rate_t;
        status  : port_status_t;
        reset_p : std_logic;
    end record;     -- From MAC/PHY to switch (Rx-data)

    type port_tx_s2mx is record
        data    : xword_t;
        nlast   : xlast_i;
        valid   : std_logic;
    end record;     -- From switch to MAC/PHY (Tx-data)

    type port_tx_m2sx is record
        clk     : std_logic;
        ready   : std_logic;
        txerr   : std_logic;
        reset_p : std_logic;
    end record;     -- From MAC/PHY to switch (Tx-ctrl)

    constant RX_M2SX_IDLE : port_rx_m2sx :=
        ('0', (others => '0'), 0, '0', '0', RATE_WORD_NULL, STATUS_NULL, '0');
    constant TX_S2MX_IDLE : port_tx_s2mx :=
        ((others => '0'), 0, '0');
    constant TX_M2SX_IDLE : port_tx_m2sx :=
        ('0', '0', '0', '0');

    -- Define arrays for each port type:
    type array_rx_m2s is array(natural range<>) of port_rx_m2s;
    type array_tx_m2s is array(natural range<>) of port_tx_m2s;
    type array_tx_s2m is array(natural range<>) of port_tx_s2m;
    type array_rx_m2sx is array(natural range<>) of port_rx_m2sx;
    type array_tx_m2sx is array(natural range<>) of port_tx_m2sx;
    type array_tx_s2mx is array(natural range<>) of port_tx_s2mx;

    -- Generic 8-bit data stream with AXI flow-control:
    type axi_stream8 is record
        data    : std_logic_vector(7 downto 0);
        last    : std_logic;
        valid   : std_logic;
        ready   : std_logic;
    end record;
    
    constant AXI_STREAM8_IDLE : axi_stream8 := (
        data => (others => '0'), last => '0', valid => '0', ready => '0');

    type axi_stream64 is record
        data    : xword_t;
        nlast   : xlast_i;
        valid   : std_logic;
        ready   : std_logic;
    end record;

    constant AXI_STREAM64_IDLE : axi_stream64 := (
        data => (others => '0'), nlast => 0, valid => '0', ready => '0');

    -- Per-port structure for reporting port error events.
    -- (Each signal is an asynchronous toggle marking the designated event.
    --  i.e., Each rising or falling edge indicates that event has occurred.)
    type port_error_t is record
        mii_err : std_logic;    -- MAC/PHY reports error
        ovr_tx  : std_logic;    -- Overflow in Tx FIFO (common)
        ovr_rx  : std_logic;    -- Overflow in Rx FIFO (rare)
        pkt_err : std_logic;    -- Packet error (Bad checksum, length, etc.)
    end record;

    constant PORT_ERROR_NONE : port_error_t := (others => '0');
    type array_port_error is array(natural range<>) of port_error_t;

    -- Per-core structure for reporting switch error events.
    -- (Each signal is an asynchronous toggle marking the designated event.)
    type switch_error_t is record
        pkt_err : std_logic;    -- Packet error (Bad checksum, length, etc.)
        mii_tx  : std_logic;    -- MAC/PHY Tx reports error
        mii_rx  : std_logic;    -- MAC/PHY Rx reports error
        mac_tbl : std_logic;    -- Switch error (MAC table)
        mac_dup : std_logic;    -- Switch error (duplicate MAC or port change)
        mac_int : std_logic;    -- Switch error (other internal error)
        ovr_tx  : std_logic;    -- Overflow in Tx FIFO (common)
        ovr_rx  : std_logic;    -- Overflow in Rx FIFO (rare)
    end record;

    constant SWITCH_ERROR_NONE : switch_error_t := (others => '0');
    type array_switch_error is array(natural range<>) of switch_error_t;

    -- For legacy compatibility, switch errors can be converted to raw vector.
    constant SWITCH_ERR_WIDTH : integer := 8;
    subtype switch_errvec_t is std_logic_vector(SWITCH_ERR_WIDTH-1 downto 0);

    function swerr2vector(err : switch_error_t) return switch_errvec_t;

    -- Define ConfigBus register map for managed switches:
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
    --  * REGADDR = 7:  Packet size limits (read-only)
    --      Bits 31-16: Maximum frame size (in bytes)
    --      Bits 15-00: Minimum frame size (in bytes)
    --  * REGADDR = 8:  Per-port VLAN configuration (write-only)
    --      Refer to "eth_frame_vstrip" and "eth_frame_vtag" for details.
    --  * REGADDR = 9:  VID for configuring VLAN masks (write-only)
    --      Refer to "mac_vlan_mask" for details.
    --  * REGADDR = 10: Data for configuring VLAN masks (read-write)
    --      Refer to "mac_vlan_mask" for details.
    constant REGADDR_PORT_COUNT     : integer := 0;
    constant REGADDR_DATA_WIDTH     : integer := 1;
    constant REGADDR_CORE_CLOCK     : integer := 2;
    constant REGADDR_TABLE_SIZE     : integer := 3;
    constant REGADDR_PROMISCUOUS    : integer := 4;
    constant REGADDR_PRIORITY       : integer := 5;
    constant REGADDR_PKT_COUNT      : integer := 6;
    constant REGADDR_FRAME_SIZE     : integer := 7;
    constant REGADDR_VLAN_PORT      : integer := 8;
    constant REGADDR_VLAN_VID       : integer := 9;
    constant REGADDR_VLAN_MASK      : integer := 10;

end package;

package body SWITCH_TYPES is
    -- Currently, the rate word is simply the rate in Mbps.
    -- Always use this function if possible, because the format may change.
    function get_rate_word(rate_mbps : positive) return port_rate_t is
    begin
        return std_logic_vector(to_unsigned(rate_mbps, 16));
    end function;

    function get_tstamp_incr(clk_hz : positive) return tstamp_t is
        constant incr : natural := integer(256.0e9 / real(clk_hz));
    begin
        return to_unsigned(incr, TSTAMP_WIDTH);
    end function;

    function swerr2vector(err : switch_error_t) return switch_errvec_t is
        variable tmp : switch_errvec_t := (
            7 => err.pkt_err,
            6 => err.mii_tx,
            5 => err.mii_rx,
            4 => err.mac_tbl,
            3 => err.mac_dup,
            2 => err.mac_int,
            1 => err.ovr_tx,
            0 => err.ovr_rx);
    begin
        return tmp;
    end function;
end package body;
