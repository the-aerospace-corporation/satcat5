--------------------------------------------------------------------------
-- Copyright 2019, 2020, 2021, 2022, 2023 The Aerospace Corporation
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
use     ieee.math_real.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;

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

    -- Before and after structures for per-frame metadata.
    type switch_meta_t is record
        pmode   : ptp_mode_t;
        tstamp  : tstamp_t;
        vtag    : vlan_hdr_t;
    end record;

    constant SWITCH_META_NULL : switch_meta_t := (
        pmode   => PTP_MODE_NONE,
        tstamp  => TSTAMP_DISABLED,
        vtag    => VHDR_NONE);

    -- Conversion from metadata to std_logic_vector and back.
    constant SWITCH_META_WIDTH : integer :=
        PTP_MODE_WIDTH + TSTAMP_WIDTH + VLAN_HDR_WIDTH;
    subtype switch_meta_v is std_logic_vector(SWITCH_META_WIDTH-1 downto 0);

    function switch_m2v(x: switch_meta_t) return switch_meta_v;
    function switch_v2m(x: switch_meta_v) return switch_meta_t;

    -- Port definition for 1 GbE and below:
    -- Note: "M2S" = MAC/PHY to Switch, "S2M" = Switch to MAC/PHY.
    -- Note: The "TNOW" and "TSOF" signals are used for PTP timestamps.
    --       If PTP is not supported on a given port, drive them to TSTAMP_DISABLED.
    --       Otherwise, instantiate "ptp_counter_sync" for each clock domain.
    type port_rx_m2s is record
        clk     : std_logic;        -- Clock for all Rx signals
        data    : byte_t;           -- Received data, including FCS
        last    : std_logic;        -- Last word in frame
        write   : std_logic;        -- Write-enable strobe
        rxerr   : std_logic;        -- PHY/MAC error strobe
        rate    : port_rate_t;      -- PHY/MAC rate word
        status  : port_status_t;    -- PHY/MAC status word
        tsof    : tstamp_t;         -- Start-of-frame timestamp
        reset_p : std_logic;        -- Port reset/shutdown (async)
    end record;     -- From MAC/PHY to switch (Rx-data)

    type port_tx_s2m is record
        data    : byte_t;           -- Transmit data, including FCS
        last    : std_logic;        -- Last word in frame
        valid   : std_logic;        -- Data-VALID (AXI flow control)
    end record;     -- From switch to MAC/PHY (Tx-data)

    type port_tx_m2s is record
        clk     : std_logic;        -- Clock for all Tx signals
        ready   : std_logic;        -- Data-READY (AXI flow control)
        tnow    : tstamp_t;         -- Current system timestamp
        txerr   : std_logic;        -- PHY/MAX error strobe
        reset_p : std_logic;        -- Port reset/shutdown (async)
    end record;     -- From MAC/PHY to switch (Tx-ctrl)

    constant RX_M2S_IDLE : port_rx_m2s := (
        clk     => '0',
        data    => (others => '0'),
        last    => '0',
        write   => '0',
        rxerr   => '0',
        rate    => RATE_WORD_NULL,
        status  => STATUS_NULL,
        tsof    => TSTAMP_DISABLED,
        reset_p => '0');
    constant TX_S2M_IDLE : port_tx_s2m := (
        data    => (others => '0'),
        last    => '0',
        valid   => '0');
    constant TX_M2S_IDLE : port_tx_m2s := (
        clk     => '0',
        ready   => '0',
        tnow    => TSTAMP_DISABLED,
        txerr   => '0',
        reset_p => '0');

    -- Port definition for 10 GbE:
    type port_rx_m2sx is record     -- From MAC/PHY to switch (Rx-data)
        clk     : std_logic;        -- Clock for all Rx signals
        data    : xword_t;          -- Received data, including FCS
        nlast   : xlast_i;          -- Length of last word in frame
        write   : std_logic;        -- Write-enable strobe
        rxerr   : std_logic;        -- PHY/MAC error strobe
        rate    : port_rate_t;      -- PHY/MAC rate word
        status  : port_status_t;    -- PHY/MAC status word
        tsof    : tstamp_t;         -- Start-of-frame timestamp
        reset_p : std_logic;        -- Port reset/shutdown (async)
    end record;

    type port_tx_s2mx is record     -- From switch to MAC/PHY (Tx-data)
        data    : xword_t;          -- Transmit data, including FCS
        nlast   : xlast_i;          -- Length of last word in frame
        valid   : std_logic;        -- Data-VALID (AXI flow control)
    end record;

    type port_tx_m2sx is record     -- From MAC/PHY to switch (Tx-ctrl)
        clk     : std_logic;        -- Clock for all Tx signals
        ready   : std_logic;        -- Data-READY (AXI flow control)
        tnow    : tstamp_t;         -- Current system timestamp
        txerr   : std_logic;        -- PHY/MAX error strobe
        reset_p : std_logic;        -- Port reset/shutdown (async)
    end record;

    constant RX_M2SX_IDLE : port_rx_m2sx := (
        clk     => '0',
        data    => (others => '0'),
        nlast   => 0,
        write   => '0',
        rxerr   => '0',
        rate    => RATE_WORD_NULL,
        status  => STATUS_NULL,
        tsof    => TSTAMP_DISABLED,
        reset_p => '0');
    constant TX_S2MX_IDLE : port_tx_s2mx := (
        data    => (others => '0'),
        nlast   => 0,
        valid   => '0');
    constant TX_M2SX_IDLE : port_tx_m2sx := (
        clk     => '0',
        ready   => '0',
        tnow    => TSTAMP_DISABLED,
        txerr   => '0',
        reset_p => '0');

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

    -- Placeholder for port-indexing, for use with REGADDR_PORT_BASE function.
    constant PORTIDX_NONE : integer := -1;

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
    --  * REGADDR = 11 - 13: MAC-table access
    --      Refer to "mac_query" for details.
    --  * REGADDR = 14: Miss-as-broadcast port mask (read-write)
    --      Set policy for routing of frames with an unknown destination MAC.
    --      Ports with a '1' receive such frames. (i.e., Treat as broadcast.)
    --      Ports with a '0' do not. (i.e., Drop unknown MAC.)
    --      Default for all ports is set by the MISS_BCAST parameter.
    --  * REGADDR = 15: Per-port "twoStep" flag for PTP mode conversion.
    --      Ports in this mode enable two-step conversion for PTP messages.
    --  * REGADDR = 16: VLAN rate-control configuration
    --      Refer to "mac_vlan_rate" for details
    --  * REGADDR = 17 - 511: Reserved
    --  * REGADDR = 512 - 527: Configuration for Port #0
    --      Each port is allocated a segment of sixteen registers.
    --      The lower eight registers in each segment are reserved for use by
    --       the port interface itself.  If so configured, ports that only
    --       need a handful of registers (e.g., "port_serial_auto") can then
    --       share the ConfigBus device-address with the Ethernet switch.
    --      The upper 8 registers of each port are reserved for switch
    --       management functions (i.e., REGOFFSET_*) as listed below.
    --      Use "REGADDR_PORT_BASE" to find the base address for a given port.
    --  * REGADDR = 528 - 543: Configuration for Port #1
    --  * REGADDR = 544 - 559: Configuration for Port #2
    --      ... (repeat for Port #3 - Port #30) ...
    --  * REGADDR = 1008 - 1023: Configuration for Port #31
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
    constant REGADDR_QUERY_MAC_LSB  : integer := 11;
    constant REGADDR_QUERY_MAC_MSB  : integer := 12;
    constant REGADDR_QUERY_CTRL     : integer := 13;
    constant REGADDR_MISS_BCAST     : integer := 14;
    constant REGADDR_PTP_2STEP      : integer := 15;
    constant REGADDR_VLAN_RATE      : integer := 16;
    function REGADDR_PORT_BASE(idx : integer) return natural;

    -- Define per-port ConfigBus registers relative to REGADDR_PORT_BASE:
    constant REGOFFSET_PORT_PTP_RX  : integer := 8;
    constant REGOFFSET_PORT_PTP_TX  : integer := 9;

end package;

package body SWITCH_TYPES is
    -- Currently, the rate word is simply the rate in Mbps.
    -- Always use this function if possible, because the format may change.
    function get_rate_word(rate_mbps : positive) return port_rate_t is
    begin
        return std_logic_vector(to_unsigned(rate_mbps, 16));
    end function;

    function switch_m2v(x: switch_meta_t) return switch_meta_v is
        -- Concatenate all the fields together.
        constant result : switch_meta_v :=
            x.vtag & x.pmode & std_logic_vector(x.tstamp);
    begin
        return result;
    end function;

    function switch_v2m(x: switch_meta_v) return switch_meta_t is
        variable v : switch_meta_v := x;
        variable result : switch_meta_t := SWITCH_META_NULL;
    begin
        -- Pop each field from vector, starting from LSBs.
        -- (More readable and maintainable than calculating offsets manually?)
        result.tstamp   := unsigned(v(TSTAMP_WIDTH-1 downto 0));
        v               := shift_right(v, TSTAMP_WIDTH);
        result.pmode    := v(PTP_MODE_WIDTH-1 downto 0);
        v               := shift_right(v, PTP_MODE_WIDTH);
        result.vtag     := v(VLAN_HDR_WIDTH-1 downto 0);
        v               := shift_right(v, VLAN_HDR_WIDTH);
        return result;
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

    function REGADDR_PORT_BASE(idx : integer) return natural is
    begin
        if (idx < 0) then
            return 0;   -- Not part of switch address space -> Base = 0
        else
            return 512 + 16 * idx;
        end if;
    end function;

end package body;
