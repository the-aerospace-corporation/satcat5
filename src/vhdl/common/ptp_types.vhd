--------------------------------------------------------------------------
-- Copyright 2022-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
    -- Note: Since TSTAMP is uniformly distributed over the full range,
    --  using zero for the special DISABLED codeword is acceptable.
    constant TSTAMP_DISABLED : tstamp_t := (others => '0');
    constant TSTAMP_ZERO : tstamp_t := (others => '0');

    -- Multiply a timestamp duration by an integer scaling factor.
    function tstamp_mult(x: tstamp_t; m: natural) return tstamp_t;

    -- Divide a timestamp duration by an integer divisor.
    function tstamp_div(x: tstamp_t; d: positive) return tstamp_t;

    -- Find the absolute difference between two timestamps.
    function tstamp_diff(x, y: tstamp_t) return tstamp_t;

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

    -- Normalized frequency offsets are measured relative to the expected or
    -- nominal frequency. They are expressed in timestamp units per second.
    -- i.e., 65,536 LSB = 1 nanosecond per second = 1 part per billion (PPB).
    -- Positive values indicate the target clock is faster than the reference.
    constant TFREQ_SCALE : integer := TSTAMP_SCALE;
    constant TFREQ_WIDTH : integer := 40;
    subtype tfreq_t is signed(TFREQ_WIDTH-1 downto 0);

    -- Multiply, divide, or find the absolute difference between offsets.
    function tfreq_mult(x: tfreq_t; m: integer) return tfreq_t;
    function tfreq_div(x: tfreq_t; d: positive) return tfreq_t;
    function tfreq_diff(x, y: tfreq_t) return tfreq_t;

    -- Constants or psuedo-constants for various common frequency offsets.
    -- Note: Valid frequency offsets are randomly distributed near zero, so
    --  the "DISABLED" codeword should have a large absolute value, while
    --  remaining visually distinctive as a debugging aide.
    constant TFREQ_DISABLED     : tfreq_t := x"80DEADBEEF";
    constant TFREQ_ZERO         : tfreq_t := (others => '0');
    constant TFREQ_FAST_1PPB    : tfreq_t := to_signed(2**TFREQ_SCALE, TFREQ_WIDTH);
    function TFREQ_FAST_1PPM    return tfreq_t;
    function TFREQ_FAST_1PPK    return tfreq_t;
    constant TFREQ_SLOW_1PPB    : tfreq_t := to_signed(-2**TFREQ_SCALE, TFREQ_WIDTH);
    function TFREQ_SLOW_1PPM    return tfreq_t;
    function TFREQ_SLOW_1PPK    return tfreq_t;

    -- Convert frequency-difference to commonly used units.
    function get_freq_ppb(f: tfreq_t) return real;
    function get_freq_ppm(f: tfreq_t) return real;

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

    -- Define the maximum byte-offset of interest for parsing PTP messages.
    function ptp_parse_bytes(support_tlv, support_l3: boolean) return positive;

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

    -- Expected message lengths for each PTP message type, including PTP
    -- header and message contents, but not the Ethernet/IP/UDP header(s).
    -- This byte offset marks the end of the regular message and the start
    -- of any appended TLV metadata (i.e., type/length/value triplets).
    function ptp_msg_len(msg_type: nybb_t) return natural;

    -- Each TLV is a tlvType/lengthField/valueField triplet (Section 1.4.1).
    -- Define various tlvType values of interest (Section 14.1.1 / Table 52).
    -- The DOPPLER tlvType is drawn from the "experimental values" pool
    -- and should only be used on private networks (Section 4.2.9).
    subtype tlvtype_t is std_logic_vector(15 downto 0);
    constant TLVTYPE_NONE       : tlvtype_t := x"0000";
    constant TLVTYPE_ORG_EXT    : tlvtype_t := x"0003";
    constant TLVTYPE_DOPPLER    : tlvtype_t := x"20AE";
    constant TLVTYPE_ORG_EXT_P  : tlvtype_t := x"4000";
    constant TLVTYPE_ORG_EXT_NP : tlvtype_t := x"8000";
    constant TLVTYPE_PAD        : tlvtype_t := x"8008";

    -- Return specified tlvType if enabled, otherwise TLVTYPE_NONE.
    function tlvtype_if(tlv: tlvtype_t; en: boolean) return tlvtype_t;

    -- The TLV lengthField is measured in bytes; it is always even.
    constant TLVLEN_WIDTH       : positive := 16;
    subtype tlvlen_t is unsigned(TLVLEN_WIDTH-1 downto 0);
    constant TLVLEN_ZERO        : tlvlen_t := (others => '0');

    -- To save space, we encode parsed TLV positions as "tlvpos_t", which
    -- counts 16-bit words from the start of the packet.  Reserved index
    -- zero indicates the associated TLV was not found.
    constant TLVPOS_WIDTH       : positive := 10;
    subtype tlvpos_t is std_logic_vector(TLVPOS_WIDTH-1 downto 0);
    function bidx_to_tlvpos(x: natural) return tlvpos_t;
    function tlvpos_to_bidx(x: tlvpos_t) return natural;
    constant TLVPOS_NONE        : tlvpos_t := (others => '0');
    function TLVPOS_PTP_L2      return tlvpos_t;
    function TLVPOS_PTP_L3      return tlvpos_t;
end package;

package body PTP_TYPES is
    function tstamp_mult(x: tstamp_t; m: natural) return tstamp_t is
    begin
        -- Note: No intermediate integers to avoid overflow > 2^31.
        return resize(x * to_unsigned(m, 32), TSTAMP_WIDTH);
    end function;

    function tstamp_div(x: tstamp_t; d: positive) return tstamp_t is
    begin
        -- Note: No intermediate integers to avoid overflow > 2^31.
        return resize(x / to_unsigned(d, 32), TSTAMP_WIDTH);
    end function;

    function tstamp_diff(x, y: tstamp_t) return tstamp_t is
    begin
        return unsigned(abs(signed(x - y)));
    end function;

    function tfreq_mult(x: tfreq_t; m: integer) return tfreq_t is
    begin
        -- Note: No intermediate integers to avoid overflow > 2^31.
        return resize(x * to_signed(m, 32), TFREQ_WIDTH);
    end function;

    function tfreq_div(x: tfreq_t; d: positive) return tfreq_t is
    begin
        -- Note: No intermediate integers to avoid overflow > 2^31.
        return resize(x / to_signed(d, 32), TFREQ_WIDTH);
    end function;

    function tfreq_diff(x, y: tfreq_t) return tfreq_t is
    begin
        return abs(signed(x - y));
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

    function TFREQ_FAST_1PPM return tfreq_t is begin
        return tfreq_mult(TFREQ_FAST_1PPB, 1_000);
    end function;

    function TFREQ_FAST_1PPK return tfreq_t is begin
        return tfreq_mult(TFREQ_FAST_1PPB, 1_000_000);
    end function;

    function TFREQ_SLOW_1PPM return tfreq_t is begin
        return tfreq_mult(TFREQ_SLOW_1PPB, 1_000);
    end function;

    function TFREQ_SLOW_1PPK return tfreq_t is begin
        return tfreq_mult(TFREQ_SLOW_1PPB, 1_000_000);
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

    function get_freq_ppb(f: tfreq_t) return real is begin
        return s2r(f) / s2r(TFREQ_FAST_1PPB);
    end function;

    function get_freq_ppm(f: tfreq_t) return real is begin
        return s2r(f) / s2r(TFREQ_FAST_1PPM);
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

    function ptp_parse_bytes(support_tlv, support_l3: boolean) return positive is
    begin
        if support_tlv then
            -- If TLV parsing is enabled, then we must parse the entire packet.
            return MAX_FRAME_BYTES;
        elsif support_l3 then
            -- If UDP is enabled, then stop at the end of the PTP common header.
            -- (PTP does not allow IPv4 header options, so no need to read IHL.)
            return UDP_HDR_MIN + PTP_HDR_MSGDAT;
        else
            -- As above, but allowing the Ethernet frame header only.
            return ETH_HDR_DATA + PTP_HDR_MSGDAT;
        end if;
    end function;

    function ptp_msg_len(msg_type: nybb_t) return natural is
    begin
        -- As defined in IEEE-1588 Section 13.5 through 13.13.
        case msg_type is
            when PTP_MSG_SYNC       => return 44;   -- Sync
            when PTP_MSG_DLYREQ     => return 44;   -- Delay_req
            when PTP_MSG_PDLYREQ    => return 54;   -- Pdelay_req
            when PTP_MSG_PDLYRSP    => return 54;   -- Pdelay_resp
            when PTP_MSG_FOLLOW     => return 44;   -- Follow_up
            when PTP_MSG_DLYRSP     => return 54;   -- Delay_resp
            when PTP_MSG_PDLYRFU    => return 54;   -- Pdelay_resp_follow_up
            when PTP_MSG_ANNOUNCE   => return 64;   -- Announce
            when PTP_MSG_SIGNAL     => return 44;   -- Signaling
            when PTP_MSG_MANAGE     => return 48;   -- Management
            when others             => return 0;    -- Unknown/invalid
        end case;
    end function;

    function tlvtype_if(tlv: tlvtype_t; en: boolean) return tlvtype_t is
    begin
        if en then
            return tlv;
        else
            return TLVTYPE_NONE;
        end if;
    end function;

    function bidx_to_tlvpos(x: natural) return tlvpos_t is
    begin
        if (x mod 2 > 0) or (x >= 2048) then
            report "Invalid TLV position." severity warning;
            return TLVPOS_NONE;
        else
            return i2s(x/2, TLVPOS_WIDTH);
        end if;
    end function;

    function tlvpos_to_bidx(x: tlvpos_t) return natural is
    begin
        return u2i(x) * 2;
    end function;

    function TLVPOS_PTP_L2 return tlvpos_t is
    begin
        -- L2 PTP message starts after the Ethernet frame header.
        return bidx_to_tlvpos(ETH_HDR_DATA);
    end function;

    function TLVPOS_PTP_L3 return tlvpos_t is
    begin
        -- L3 PTP message starts after the UDP frame header with fixed-length
        -- IPv4 header (no options allowed per IEEE 1588-2019, Appendix C.5).
        return bidx_to_tlvpos(UDP_HDR_DAT(IP_IHL_MIN));
    end function;
end package body;
