--------------------------------------------------------------------------
-- Copyright 2022, 2023 The Aerospace Corporation
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
-- Software-controlled real-time clock for Precision Time Protocol
--
-- This block implements a real-time clock (RTC) using the "timestamp"
-- data-structure defined in IEEE-1588, Section 5.3.3:
--  * 48-bit signed: Seconds (1 LSB = 1 second)
--  * 32-bit unsigned: Nanoseconds (1 LSB = 1 nanosecond, rollover at 1e9)
--  * 16-bit unsigned: Subnanoseconds (1 LSB = 1/65536 nanoseconds)
--
-- The block provides a ConfigBus interface that allows software to adjust
-- the time and rate of this clock to keep it locked to real-time.  Once
-- locked, it represents the elapsed time since the PTP epoch defined in
-- IEEE-1588, Section 7.2.3 (i.e., 1970 January 1, 00:00:00 TAI).
--
-- The rate-control register offsets the time increment that is applied on
-- each ConfigBus clock cycle.  It is a signed integer N that offsets the
-- nominal increment by N / 2^TFINE_SCALE nanoseconds per clock:
--  * Tnom(nsec)        = 1e9 / CFG_CLK_HZ
--  * Toffset(nsec)     = Register value / 2^TFINE_SCALE
--  * Timestamp[n+1]    = Timestamp[n] + Tnom + Toffset
--
-- The resulting dynamic range depends on CFG_CLK_HZ.  For a typical rate of
-- 100 MHz, this gives an overall drift-rate resolution of 0.09 picoseconds
-- per second.  The full-scale tuning range is fixed at +/- 16 nanoseconds per
-- clock, which usually exceeds the nominal clock rate.
--
-- The ConfigBus interface uses six consecutive registers:
--  * Base + 0: Seconds MSBs
--      Indirect register, see discussion below.
--      Bits 31..16: Reserved (reads as sign-extension)
--      Bits 15..00: Signed "Seconds" field, bits 47..32
--  * Base + 1: Seconds LSBs
--      Indirect register, see discussion below.
--      Bits 31..00: Signed "Seconds" field, bits 31..00
--  * Base + 2: Nanoseconds
--      Indirect register, see discussion below.
--      Note: Written values must be strictly less than 1e9.
--      Bits 31..00: Unsigned "Nanoseconds" field.
--  * Base + 3: Subnanoseconds (bits 15..00)
--      Reads are used for indirect reporting of the "subnanoseconds" field.
--      Bits 15..00: Unsigned "Subnanoseconds" field (1 LSB = 2^-16 nsec)
--  * Base + 4: Command
--      Writes immediately execute the specified opcode.
--      Bits 31..24: Opcode (reads as zero)
--          0x00: No-op
--          0x01: Read current time, immediate
--              Immediately latch current time to all registers.
--          0x02: Set current time, immediate
--              Immediately overwrite current time with register contents.
--          0x03: Set current time at pulse
--              Overwrite current time with register contents at the next
--              rising edge of the `time_write` signal.
--          0x04: Increment current time
--              Increment current time by register contents.
--          All other opcodes reserved.
--      Bits 23..00: Reserved (write zeros)
--  * Base + 5: Rate (write-only)
--      "Wide" register that sets the new rate-control offset.
--      Requires multiple writes to set the new configuration:
--      * 1st write: MSBs (signed bits 63..32)
--      * 2nd write: LSBs (signed bits 31..00)
--      * Read from the register to latch the new value.
--      (The read-value is zero and should be discarded.)
--
-- Example usage:
--  * Read current time:
--      Write opcode 0x01 to register 4.
--      Read registers 0, 1, 2, and 3 in any order to obtain each field.
--  * Set current time (e.g., initial setup):
--      Write registers 0, 1, 2, and 3 with the desired time fields.
--      Write opcode 0x02 to register 4.
--  * Adjust current time (e.g., fine adjustment)
--      Write registers 0, 1, 2, and 3 with the desired incremental amount.
--      Write opcode 0x04 to register 4.
--  * Adjust PLL rate (e.g., closed-loop software PLL):
--      Update register 5 (write, write, read) with the new frequency offset.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.eth_frame_common.byte_t;
use     work.ptp_types.all;

entity ptp_realtime is
    generic (
    CFG_CLK_HZ  : positive;     -- ConfigBus clock frequency
    DEV_ADDR    : integer;      -- ConfigBus device address
    REG_BASE    : integer;      -- Note: Six consecutive registers
    TFINE_SCALE : positive := 40);
    port (
    -- Current estimated time.
    time_now    : out ptp_time_t;

    -- Optional "read" strobe (same as READ opcode).
    time_read   : in  std_logic := '0';

    -- Optional "write" strobe (ex. PPS)
    time_write  : in  std_logic := '0';

    -- ConfigBus interface.
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack);
end ptp_realtime;

architecture ptp_realtime of ptp_realtime is

-- Define command opcodes:
constant OPCODE_READ    : byte_t := x"01";
constant OPCODE_WRITE   : byte_t := x"02";
constant OPCODE_WPULSE  : byte_t := x"03";
constant OPCODE_INCR    : byte_t := x"04";

-- PTP mandates a 48-bit field for counting seconds; we treat it as signed.
constant TSEC_WIDTH     : integer := 48;
subtype tsec_t is signed(TSEC_WIDTH-1 downto 0);

-- Internal counters use a finer resolution than the final timestamp.
constant RATE_WIDTH     : positive := TFINE_SCALE + 5;  -- +/- 16 nsec/clk
constant TFINE_EXTRA    : natural  := TFINE_SCALE - TSTAMP_SCALE;
constant TFINE_WIDTH    : positive := TSTAMP_WIDTH + TFINE_EXTRA;
subtype tfine_t is unsigned(TFINE_WIDTH-1 downto 0);

function reg2fine(x: cfgbus_word; scale: natural) return tfine_t is
    constant y : tfine_t := resize(unsigned(x), TFINE_WIDTH);
begin
    return shift_left(y, scale);
end function;

-- Calculate the nominal increment based on CFG_CLK_HZ.
constant ONE_SEC_R  : real := 1.0e9 * (2.0 ** TFINE_SCALE);
constant ONE_SEC_U  : tfine_t := r2u(ONE_SEC_R, TFINE_WIDTH);
constant INCR_R     : real := ONE_SEC_R / real(CFG_CLK_HZ);
constant INCR_U     : tfine_t := r2u(INCR_R, TFINE_WIDTH);

-- RTC time has separate fields for "seconds" and "subnanoseconds".
type rtc_time_t is record
    sec     : tsec_t;       -- Whole seconds from PTP epoch
    fine    : tfine_t;      -- 1 LSB = 2^-TFINE_SCALE nanoseconds
end record;

constant RTC_TIME_ZERO : rtc_time_t := (
    sec     => (others => '0'),
    fine    => (others => '0'));

-- Calculate X + Y + Z
function rtc_incr(x: rtc_time_t; y: rtc_time_t; z: tfine_t) return rtc_time_t is
    variable sum : rtc_time_t := (
        sec  => x.sec + y.sec,
        fine => x.fine + y.fine + z);
begin
    assert (x.fine < ONE_SEC_U and y.fine < ONE_SEC_U and z < ONE_SEC_U)
        report "Inputs out of range." severity error;
    if (sum.fine >= ONE_SEC_U) then
        sum.sec  := sum.sec + 1;
        sum.fine := sum.fine - ONE_SEC_U;
    end if;
    return sum;
end function;

-- Real-time clock.
signal time_rtc     : rtc_time_t := RTC_TIME_ZERO;
signal time_cmd     : rtc_time_t;
signal time_adj     : tfine_t;

-- ConfigBus interface.
signal cmd_read     : std_logic := '0';
signal cmd_write    : std_logic := '0';
signal cmd_wpulse   : std_logic := '0';
signal cmd_incr     : std_logic := '0';
signal cfg_ack_i    : cfgbus_ack := cfgbus_idle;
signal cfg_opcode   : byte_t;
signal cfg_sec_msb  : cfgbus_word := (others => '0');
signal cfg_sec_lsb  : cfgbus_word := (others => '0');
signal cfg_nsec     : cfgbus_word := (others => '0');
signal cfg_subns    : cfgbus_word := (others => '0');
signal cfg_rate     : std_logic_vector(RATE_WIDTH-1 downto 0) := (others => '0');

begin

-- Drive top-level outputs.
cfg_ack         <= cfg_ack_i;
time_now.sec    <= time_rtc.sec;
time_now.nsec   <= time_rtc.fine(TFINE_WIDTH-1 downto TFINE_SCALE);
time_now.subns  <= time_rtc.fine(TFINE_SCALE-1 downto TFINE_EXTRA);

-- Real-time clock.
p_rtc : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- Update the main RTC counters.
        if (cfg_cmd.reset_p = '1') then     -- Reset
            time_rtc <= RTC_TIME_ZERO;
        elsif (cmd_write = '1' or           -- Overwrite
            (cmd_wpulse = '1' and time_write = '1')) then
            time_rtc <= time_cmd;
        elsif (cmd_incr = '1') then         -- One-time adjustment
            time_rtc <= rtc_incr(time_rtc, time_cmd, time_adj);
        else                                -- Normal increment
            time_rtc <= rtc_incr(time_rtc, RTC_TIME_ZERO, time_adj);
        end if;

        -- Precalculate the adjusted rate parameter.
        time_adj <= INCR_U + unsigned(resize(signed(cfg_rate), TFINE_WIDTH));
    end if;
end process;

-- ConfigBus interface.
cfg_opcode      <= cfg_cmd.wdata(31 downto 24);
time_cmd.sec    <= resize(signed(cfg_sec_msb) & signed(cfg_sec_lsb), TSEC_WIDTH);
time_cmd.fine   <= reg2fine(cfg_nsec, TFINE_SCALE)
                or reg2fine(cfg_subns, TFINE_EXTRA);

p_cfg : process(cfg_cmd.clk)
    function time2reg(x: signed) return cfgbus_word is
        constant y : signed(31 downto 0) := resize(x, 32);
    begin
        return std_logic_vector(y);
    end function;

    function time2reg(x: unsigned) return cfgbus_word is
        constant y : unsigned(31 downto 0) := resize(x, 32);
    begin
        return std_logic_vector(y);
    end function;
begin
    if rising_edge(cfg_cmd.clk) then
        -- Detect each command opcode.
        if (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, REG_BASE+4)) then
            cmd_read    <= bool2bit(cfg_opcode = OPCODE_READ);
            cmd_write   <= bool2bit(cfg_opcode = OPCODE_WRITE);
            cmd_wpulse  <= bool2bit(cfg_opcode = OPCODE_WPULSE);
            cmd_incr    <= bool2bit(cfg_opcode = OPCODE_INCR);
        else
            cmd_read    <= '0';
            cmd_write   <= '0';
            if (time_write = '1') then
                cmd_wpulse  <= '0'; -- Reset only after time latched in
            end if;
            cmd_incr    <= '0';
        end if;

        -- Register writes.
        if (cmd_read = '1' or time_read = '1') then
            cfg_sec_msb <= time2reg(time_rtc.sec(TSEC_WIDTH-1 downto 32));
            cfg_sec_lsb <= time2reg(time_rtc.sec(31 downto 0));
            cfg_nsec    <= time2reg(time_rtc.fine(TFINE_WIDTH-1 downto TFINE_SCALE));
            cfg_subns   <= time2reg(time_rtc.fine(TFINE_SCALE-1 downto TFINE_EXTRA));
        elsif (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, REG_BASE+0)) then
            cfg_sec_msb <= cfg_cmd.wdata;
        elsif (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, REG_BASE+1)) then
            cfg_sec_lsb <= cfg_cmd.wdata;
        elsif (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, REG_BASE+2)) then
            cfg_nsec    <= cfg_cmd.wdata;
        elsif (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, REG_BASE+3)) then
            cfg_subns   <= cfg_cmd.wdata;
        end if;

        -- Register reads.
        if (cfgbus_rdcmd(cfg_cmd, DEV_ADDR, REG_BASE+0)) then
            cfg_ack_i <= cfgbus_reply(cfg_sec_msb);
        elsif (cfgbus_rdcmd(cfg_cmd, DEV_ADDR, REG_BASE+1)) then
            cfg_ack_i <= cfgbus_reply(cfg_sec_lsb);
        elsif (cfgbus_rdcmd(cfg_cmd, DEV_ADDR, REG_BASE+2)) then
            cfg_ack_i <= cfgbus_reply(cfg_nsec);
        elsif (cfgbus_rdcmd(cfg_cmd, DEV_ADDR, REG_BASE+3)) then
            cfg_ack_i <= cfgbus_reply(cfg_subns);
        elsif (cfgbus_rdcmd(cfg_cmd, DEV_ADDR, REG_BASE+5)) then
            cfg_ack_i <= cfgbus_reply(CFGBUS_WORD_ZERO);
        else
            cfg_ack_i <= cfgbus_idle;
        end if;
    end if;
end process;

u_rate : cfgbus_register_wide
    generic map(
    DWIDTH      => RATE_WIDTH,
    DEVADDR     => DEV_ADDR,
    REGADDR     => REG_BASE + 5)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => open,
    sync_clk    => cfg_cmd.clk,
    sync_val    => cfg_rate);

end ptp_realtime;
