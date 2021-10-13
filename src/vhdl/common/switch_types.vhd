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

    -- Define arrays for each port type:
    type array_rx_m2s is array(natural range<>) of port_rx_m2s;
    type array_tx_m2s is array(natural range<>) of port_tx_m2s;
    type array_tx_s2m is array(natural range<>) of port_tx_s2m;

    -- Generic 8-bit data stream with AXI flow-control:
    type axi_stream8 is record
        data    : std_logic_vector(7 downto 0);
        last    : std_logic;
        valid   : std_logic;
        ready   : std_logic;
    end record;
    
    constant AXI_STREAM8_IDLE : axi_stream8 := (
        data => (others => '0'), last => '0', valid => '0', ready => '0');

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
end package;

package body SWITCH_TYPES is
    -- Currently, the rate word is simply the rate in Mbps.
    -- Always use this function if possible, because the format may change.
    function get_rate_word(rate_mbps : positive) return port_rate_t is
    begin
        return std_logic_vector(to_unsigned(rate_mbps, 16));
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
