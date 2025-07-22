--------------------------------------------------------------------------
-- Copyright 2019-2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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

    -- Ingress and egress metadata used by the switch and router.
    type switch_meta_t is record
        pmsg    : tlvpos_t;     -- PTP start-of-message offset (0 = N/A)
        pfreq   : tlvpos_t;     -- PTP Doppler TLV offset (0 = N/A)
        tstamp  : tstamp_t;     -- PTP timestamp (original or modified)
        tfreq   : tfreq_t;      -- PTP frequency (original or modified)
        vtag    : vlan_hdr_t;   -- VLAN header (eth_frame_common.vhd)
    end record;

    constant SWITCH_META_NULL : switch_meta_t := (
        pmsg    => TLVPOS_NONE,
        pfreq   => TLVPOS_NONE,
        tstamp  => TSTAMP_DISABLED,
        tfreq   => TFREQ_DISABLED,
        vtag    => VHDR_NONE);

    type switch_meta_array is array(natural range<>) of switch_meta_t;

    -- Metadata used for optional diagnostics. (See "packet_logging".)
    type log_meta_t is record
        dst_mac : mac_addr_t;
        src_mac : mac_addr_t;
        etype   : mac_type_t;
        vtag    : vlan_hdr_t;
        reason  : reason_t;
    end record;

    constant LOG_META_NULL : log_meta_t := (
        dst_mac => MAC_ADDR_NONE,
        src_mac => MAC_ADDR_NONE,
        etype   => ETYPE_NONE,
        vtag    => VHDR_NONE,
        reason  => REASON_KEEP);

    type log_meta_array is array(natural range<>) of log_meta_t;

    -- Conversion from metadata to std_logic_vector and back.
    constant SWITCH_META_WIDTH : integer :=
        2*TLVPOS_WIDTH + TSTAMP_WIDTH + TFREQ_WIDTH + VLAN_HDR_WIDTH;
    subtype switch_meta_v is std_logic_vector(SWITCH_META_WIDTH-1 downto 0);

    function switch_m2v(x: switch_meta_t) return switch_meta_v;
    function switch_v2m(x: switch_meta_v) return switch_meta_t;

    constant LOG_META_WIDTH : integer :=
        2*MAC_ADDR_WIDTH + MAC_TYPE_WIDTH + VLAN_HDR_WIDTH + 8;
    subtype log_meta_v is std_logic_vector(LOG_META_WIDTH-1 downto 0);

    function log_m2v(x: log_meta_t) return log_meta_v;
    function log_v2m(x: log_meta_v) return log_meta_t;

    -- Port definition for 1 GbE and below:
    -- For more details, refer to "Custom Ports" in "docs/INTERFACES.md".
    -- Note: "M2S" = MAC/PHY to Switch, "S2M" = Switch to MAC/PHY.
    type port_rx_m2s is record
        clk     : std_logic;        -- Clock for all Rx signals
        data    : byte_t;           -- Received data, including FCS
        last    : std_logic;        -- Last word in frame
        write   : std_logic;        -- Write-enable strobe
        rxerr   : std_logic;        -- PHY/MAC error strobe
        rate    : port_rate_t;      -- PHY/MAC rate word
        status  : port_status_t;    -- PHY/MAC status word
        tsof    : tstamp_t;         -- Start-of-frame timestamp
        tfreq   : tfreq_t;          -- Normalized frequency offset
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
        pstart  : std_logic;        -- PTP start (see "ptp_egress.vhd")
        tnow    : tstamp_t;         -- Current system timestamp
        tfreq   : tfreq_t;          -- Normalized frequency offset
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
        tfreq   => TFREQ_DISABLED,
        reset_p => '0');
    constant TX_S2M_IDLE : port_tx_s2m := (
        data    => (others => '0'),
        last    => '0',
        valid   => '0');
    constant TX_M2S_IDLE : port_tx_m2s := (
        clk     => '0',
        ready   => '0',
        pstart  => '0',
        tnow    => TSTAMP_DISABLED,
        tfreq   => TFREQ_DISABLED,
        txerr   => '0',
        reset_p => '0');

    -- Port definition for 10 GbE
    -- For more details, refer to "Custom Ports" in "docs/INTERFACES.md".
    type port_rx_m2sx is record     -- From MAC/PHY to switch (Rx-data)
        clk     : std_logic;        -- Clock for all Rx signals
        data    : xword_t;          -- Received data, including FCS
        nlast   : xlast_i;          -- Length of last word in frame
        write   : std_logic;        -- Write-enable strobe
        rxerr   : std_logic;        -- PHY/MAC error strobe
        rate    : port_rate_t;      -- PHY/MAC rate word
        status  : port_status_t;    -- PHY/MAC status word
        tsof    : tstamp_t;         -- Start-of-frame timestamp
        tfreq   : tfreq_t;          -- Normalized frequency offset
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
        pstart  : std_logic;        -- PTP start (see "ptp_egress.vhd")
        tnow    : tstamp_t;         -- Current system timestamp
        tfreq   : tfreq_t;          -- Normalized frequency offset
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
        tfreq   => TFREQ_DISABLED,
        reset_p => '0');
    constant TX_S2MX_IDLE : port_tx_s2mx := (
        data    => (others => '0'),
        nlast   => 0,
        valid   => '0');
    constant TX_M2SX_IDLE : port_tx_m2sx := (
        clk     => '0',
        ready   => '0',
        pstart  => '0',
        tnow    => TSTAMP_DISABLED,
        tfreq   => TFREQ_DISABLED,
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
        mii_err    : std_logic;    -- MAC/PHY reports error
        ovr_tx     : std_logic;    -- Overflow in Tx FIFO (common)
        ovr_rx     : std_logic;    -- Overflow in Rx FIFO (rare)
        pkt_err    : std_logic;    -- Packet error (Bad checksum, length, etc.)
        tx_ptp_err : std_logic;    -- invalid egress ptp_tstamp
        rx_ptp_err : std_logic;    -- invalid ingress ptp_tstamp
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

    -- Placeholder for port-indexing, for use with SW_ADDR_PORT_BASE function.
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
    --  * REGADDR = 17: Packet logging diagnostics.
    --      Refer to "mag_log_cfgbus" for details
    --  * REGADDR = 18 - 511: Reserved
    --  * REGADDR = 512 - 527: Configuration for Port #0
    --      Each port is allocated a segment of sixteen registers.
    --      The lower eight registers in each segment are reserved for use by
    --       the port interface itself.  If so configured, ports that only
    --       need a handful of registers (e.g., "port_serial_auto") can then
    --       share the ConfigBus device-address with the Ethernet switch.
    --      The upper 8 registers of each port are reserved for switch
    --       management functions (i.e., REGOFFSET_*) as listed below.
    --      Use "SW_ADDR_PORT_BASE" to find the base address for a given port.
    --  * REGADDR = 528 - 543: Configuration for Port #1
    --  * REGADDR = 544 - 559: Configuration for Port #2
    --      ... (repeat for Port #3 - Port #30) ...
    --  * REGADDR = 1008 - 1023: Configuration for Port #31
    -- ("SW_ADDR_*" prefix avoids conflicts with router control registers.)
    constant SW_ADDR_PORT_COUNT     : integer := 0;
    constant SW_ADDR_DATA_WIDTH     : integer := 1;
    constant SW_ADDR_CORE_CLOCK     : integer := 2;
    constant SW_ADDR_TABLE_SIZE     : integer := 3;
    constant SW_ADDR_PROMISCUOUS    : integer := 4;
    constant SW_ADDR_PRIORITY       : integer := 5;
    constant SW_ADDR_PKT_COUNT      : integer := 6;
    constant SW_ADDR_FRAME_SIZE     : integer := 7;
    constant SW_ADDR_VLAN_PORT      : integer := 8;
    constant SW_ADDR_VLAN_VID       : integer := 9;
    constant SW_ADDR_VLAN_MASK      : integer := 10;
    constant SW_ADDR_QUERY_MAC_LSB  : integer := 11;
    constant SW_ADDR_QUERY_MAC_MSB  : integer := 12;
    constant SW_ADDR_QUERY_CTRL     : integer := 13;
    constant SW_ADDR_MISS_BCAST     : integer := 14;
    constant SW_ADDR_PTP_2STEP      : integer := 15;
    constant SW_ADDR_VLAN_RATE      : integer := 16;
    constant SW_ADDR_LOGGING        : integer := 17;
    function SW_ADDR_PORT_BASE(idx : integer) return natural;

    -- Define per-port ConfigBus registers relative to SW_ADDR_PORT_BASE:
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

    function log_m2v(x: log_meta_t) return log_meta_v is
        -- Concatenate all the fields together.
        constant result : log_meta_v :=
            x.dst_mac & x.src_mac & x.etype & x.vtag & x.reason;
    begin
        return result;
    end function;

    function log_v2m(x: log_meta_v) return log_meta_t is
        variable v : log_meta_v := x;
        variable result : log_meta_t := LOG_META_NULL;
    begin
        -- Pop each field from vector, starting from LSBs.
        -- (More readable and maintainable than calculating offsets manually.)
        result.reason   := v(REASON_WIDTH-1 downto 0);
        v               := shift_right(v, REASON_WIDTH);
        result.vtag     := v(VLAN_HDR_WIDTH-1 downto 0);
        v               := shift_right(v, VLAN_HDR_WIDTH);
        result.etype    := v(MAC_TYPE_WIDTH-1 downto 0);
        v               := shift_right(v, MAC_TYPE_WIDTH);
        result.src_mac  := v(MAC_ADDR_WIDTH-1 downto 0);
        v               := shift_right(v, MAC_ADDR_WIDTH);
        result.dst_mac  := v(MAC_ADDR_WIDTH-1 downto 0);
        v               := shift_right(v, MAC_ADDR_WIDTH);
        return result;
    end function;

    function switch_m2v(x: switch_meta_t) return switch_meta_v is
        -- Concatenate all the fields together.
        -- Selected fields are XOR'd to ensure that unsupported ports can
        -- be optimized to constant zero, to allow better FIFO pruning.
        constant result : switch_meta_v :=
            x.pmsg & x.pfreq &
            std_logic_vector(x.tstamp xor TSTAMP_DISABLED) &
            std_logic_vector(x.tfreq xor TFREQ_DISABLED) &
            x.vtag;
    begin
        return result;
    end function;

    function switch_v2m(x: switch_meta_v) return switch_meta_t is
        variable v : switch_meta_v := x;
        variable result : switch_meta_t := SWITCH_META_NULL;
    begin
        -- Pop each field from vector, starting from LSBs.
        -- (More readable and maintainable than calculating offsets manually.)
        result.vtag     := v(VLAN_HDR_WIDTH-1 downto 0);
        v               := shift_right(v, VLAN_HDR_WIDTH);
        result.tfreq    := signed(v(TFREQ_WIDTH-1 downto 0)) xor TFREQ_DISABLED;
        v               := shift_right(v, TFREQ_WIDTH);
        result.tstamp   := unsigned(v(TSTAMP_WIDTH-1 downto 0)) xor TSTAMP_DISABLED;
        v               := shift_right(v, TSTAMP_WIDTH);
        result.pfreq    := v(TLVPOS_WIDTH-1 downto 0);
        v               := shift_right(v, TLVPOS_WIDTH);
        result.pmsg     := v(TLVPOS_WIDTH-1 downto 0);
        v               := shift_right(v, TLVPOS_WIDTH);
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

    function SW_ADDR_PORT_BASE(idx : integer) return natural is
    begin
        if (idx < 0) then
            return 0;   -- Not part of switch address space -> Base = 0
        else
            return 512 + 16 * idx;
        end if;
    end function;

end package body;
