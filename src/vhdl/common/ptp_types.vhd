--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation
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
-- Data-type and function definitions for PTP timestamps
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

package PTP_TYPES is
    -- Define the internal timestamp format used to measure propagation
    -- delay for IEEE 1588 Precision Time Protocol (PTP).  Resolution is
    -- in 1/65536th-nanosecond increments with rollover every ~4.3 seconds.
    -- The value may represent a modulo-timestamp or a duration.
    constant TSTAMP_SCALE : integer := 16;  -- One nanosecond = 2^N units
    constant TSTAMP_WIDTH : integer := 48;  -- Total counter width
    subtype tstamp_t is unsigned(TSTAMP_WIDTH-1 downto 0);

    -- Special case if timestamp is unavailable or unsupported.
    constant TSTAMP_DISABLED : tstamp_t := (others => '0');

    -- Multiply a timestamp duration by an integer scaling factor.
    function tstamp_mult(x: tstamp_t; m: natural) return tstamp_t;

    -- Constants or psuedo-constants for various common time durations.
    constant TSTAMP_ONE_NSEC : tstamp_t := to_unsigned(2**TSTAMP_SCALE, TSTAMP_WIDTH);
    function TSTAMP_ONE_USEC return tstamp_t;
    function TSTAMP_ONE_MSEC return tstamp_t;
    function TSTAMP_ONE_SEC  return tstamp_t;

    -- Given nominal clock frequency in Hz, calculate increment per clock.
    -- Note: NCOs will accumulate small frequency errors over time, and
    --       should generally use finer resolution than "tstamp_t" allows.
    function get_tstamp_incr(clk_hz : natural) return tstamp_t;
    function get_tstamp_incr(clk_hz : real) return tstamp_t;

    -- Given a time interval in engineering units, convert to timestamp.
    function get_tstamp_sec(t: real) return tstamp_t;
    function get_tstamp_nsec(t: real) return tstamp_t;

    -- Convert timestamp-difference to seconds or nanoseconds.
    function get_time_sec(t: tstamp_t) return real;
    function get_time_nsec(t: tstamp_t) return real;

    -- Auto-scaling for tracking loop coefficients.
    -- Given floating-point gain, return recommended fixed-point scaling.
    -- Optional hint parameter can be used to override automatic mode.
    function auto_scale(gain: real; bmin, hint: natural := 0) return natural;

    -- PTP timestamp for real-time clocks referenced to the PTP epoch.
    -- As defined IEEE-1588 Section 5.3.3, plus a "subnanoseconds" field.
    type ptp_time_t is record
        sec     : signed(47 downto 0);      -- Whole seconds from PTP epoch
        nsec    : unsigned(31 downto 0);    -- Whole nanoseconds [0..1e9)
        subns   : unsigned(15 downto 0);    -- 1 LSB = 1/65536 nanoseconds
    end record;

    constant PTP_TIME_ZERO  : ptp_time_t := (
        sec     => (others => '0'),
        nsec    => (others => '0'),
        subns   => (others => '0'));

    -- PTP frame-type metadata for the ptp_adjust and ptp_egress blocks.
    -- (Indicates presence and position of specific fields for replacement.)
    constant PTP_MODE_WIDTH : positive := 2;
    subtype ptp_mode_t is std_logic_vector(PTP_MODE_WIDTH-1 downto 0);
    constant PTP_MODE_NONE  : ptp_mode_t := "00";
    constant PTP_MODE_ETH   : ptp_mode_t := "01";
    constant PTP_MODE_UDP   : ptp_mode_t := "10";

    -- Signal bundle required for Vernier time-reference distribution.
    type port_timeref is record
        vclka   : std_logic;    -- Vernier clock (slightly slow)
        vclkb   : std_logic;    -- Vernier clock (slightly fast)
        tnext   : std_logic;    -- Counter update strobe (in VCLKA domain)
        tstamp  : tstamp_t;     -- Reference counter (in VCLKA domain)
    end record;

    constant PORT_TIMEREF_NULL : port_timeref := (
        vclka   => '0',
        vclkb   => '0',
        tnext   => '0',
        tstamp  => (others => '0'));

    -- Define byte offsets for fields in the PTP message.
    -- Does not include Ethernet/IP/UDP headers, if applicable.
    -- (IEEE 1588-2019, Section 13.3.1, Table 35)
    constant PTP_HDR_TYPE   : integer := 0;     -- U8 majorSdoId + messageType
    constant PTP_HDR_VER    : integer := 1;     -- U8 minorVersionPTP + versionPTP
    constant PTP_HDR_LEN    : integer := 2;     -- U16 messageLength
    constant PTP_HDR_DOMAIN : integer := 4;     -- U8 domainNumber
    constant PTP_HDR_SDOID  : integer := 5;     -- U8 minorSdoId
    constant PTP_HDR_FLAG   : integer := 6;     -- U16 flagField
    constant PTP_HDR_CORR   : integer := 8;     -- U64 correctionField
    constant PTP_HDR_SUBTYP : integer := 16;    -- U32 messageTypeSpecific
    constant PTP_HDR_SRCID  : integer := 20;    -- U64+U16 sourcePortIdentity
    constant PTP_HDR_SEQID  : integer := 30;    -- U16 sequenceId
    constant PTP_HDR_CTRL   : integer := 32;    -- U8 controlField
    constant PTP_HDR_INTVAL : integer := 33;    -- U8 logMessageInterval
    constant PTP_HDR_MSGDAT : integer := 34;    -- Start of message data

    -- Define various PTP messageType values:
    -- (IEEE 1588-2019, Section 13.3.2.3, Table 36)
    constant PTP_MSG_SYNC       : nybb_t := x"0";   -- Sync
    constant PTP_MSG_DLYREQ     : nybb_t := x"1";   -- Delay_req
    constant PTP_MSG_PDLYREQ    : nybb_t := x"2";   -- Pdelay_req
    constant PTP_MSG_PDLYRSP    : nybb_t := x"3";   -- Pdelay_resp
    constant PTP_MSG_FOLLOW     : nybb_t := x"8";   -- Follow_up
    constant PTP_MSG_DLYRSP     : nybb_t := x"9";   -- Delay_resp
    constant PTP_MSG_PDLYRFU    : nybb_t := x"A";   -- Pdelay_resp_follow_up
    constant PTP_MSG_ANNOUNCE   : nybb_t := x"B";   -- Announce
    constant PTP_MSG_SIGNAL     : nybb_t := x"C";   -- Signaling
    constant PTP_MSG_MANAGE     : nybb_t := x"D";   -- Management

end package;

package body PTP_TYPES is
    function tstamp_mult(x: tstamp_t; m: natural) return tstamp_t is
    begin
        -- Note: No intermediate integers to avoid overflow > 2^31.
        return resize(x * to_unsigned(m, 32), TSTAMP_WIDTH);
    end function;

    function TSTAMP_ONE_USEC return tstamp_t is begin
        return tstamp_mult(TSTAMP_ONE_NSEC, 1_000);
    end function;

    function TSTAMP_ONE_MSEC return tstamp_t is begin
        return tstamp_mult(TSTAMP_ONE_NSEC, 1_000_000);
    end function;

    function TSTAMP_ONE_SEC return tstamp_t is begin
        return tstamp_mult(TSTAMP_ONE_NSEC, 1_000_000_000);
    end function;

    function get_tstamp_incr(clk_hz : natural) return tstamp_t is
        constant ONE_SEC : real := 1.0e9 * real(2**TSTAMP_SCALE);
    begin
        if (clk_hz > 0) then
            return r2u(round(ONE_SEC / real(clk_hz)), TSTAMP_WIDTH);
        else
            return to_unsigned(0, TSTAMP_WIDTH);
        end if;
    end function;

    function get_tstamp_incr(clk_hz : real) return tstamp_t is
        constant ONE_SEC : real := 1.0e9 * real(2**TSTAMP_SCALE);
    begin
        if (clk_hz > 0.1) then
            return r2u(round(ONE_SEC / clk_hz), TSTAMP_WIDTH);
        else
            return to_unsigned(0, TSTAMP_WIDTH);
        end if;
    end function;

    function get_tstamp_sec(t: real) return tstamp_t is
        constant ONE_SEC : real := 1.0e9 * real(2**TSTAMP_SCALE);
    begin
        return unsigned(r2s(t * ONE_SEC, TSTAMP_WIDTH));
    end function;

    function get_tstamp_nsec(t: real) return tstamp_t is
        constant ONE_NSEC : real := real(2**TSTAMP_SCALE);
    begin
        return unsigned(r2s(t * ONE_NSEC, TSTAMP_WIDTH));
    end function;

    function get_time_sec(t: tstamp_t) return real is
    begin
        return get_time_nsec(t) / 1.0e9;
    end function;

    function get_time_nsec(t: tstamp_t) return real is
        constant ONE_NSEC : real := real(2**TSTAMP_SCALE);
    begin
        return s2r(signed(t)) / ONE_NSEC;
    end function;

    function auto_scale(gain: real; bmin, hint: natural := 0) return natural is
        -- How many fixed-point bits required to represent gain accurately?
        variable bits : integer := integer(round(log(64.0 / gain) / log(2.0)));
    begin
        if (hint > 0) then
            return hint;    -- User-specified width
        elsif (bits > bmin) then
            return bits;    -- Automatic width
        else
            return bmin;    -- Minimum width
        end if;
    end function;

end package body;
