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
-- Free-running or CPU-controlled counter for PTP timestamps
--
-- This block generates a free-running, fixed-increment counter in the
-- designated clock domain, in the 48-bit PTP format.  If REF_CLK_DIV is
-- specified, it updates once every N clock cycles.
--
-- The optional ConfigBus interface allows runtime adjustments to the counter
-- rate.  This can be used for software-controlled PLLs.  If this feature is
-- not needed, leave the ConfigBus interface disconnected.  Otherwise, the
-- control register is a 32-bit signed integer N that offsets the time
-- increment by N / 2^32 nanoseconds:
--  * Tnom(nsec)        = 1e9 * REF_CLK_DIV / REF_CLK_HZ
--  * Toffset(nsec)     = Register value / 2^32
--  * Timestamp[n+1]    = Timestamp[n] + Tnom + Toffset
--
-- The typical increment rate is ~10 MHz, giving an overall drift-rate
-- resolution of 0.002 nanoseconds per second and a full-scale tuning
-- range of +/-50 kHz (0.5% = 5,000 ppm).
--
-- See "ptp_counter_gen" for a complete VPLL global reference source.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.ptp_types.all;

entity ptp_counter_free is
    generic (
    REF_CLK_HZ  : real;
    REF_CLK_DIV : positive := 1;
    DEVADDR     : integer := CFGBUS_ADDR_NONE;
    REGADDR     : integer := CFGBUS_ADDR_NONE);
    port (
    -- Basic interface.
    ref_clk     : in  std_logic;
    ref_ctr     : out tstamp_t;
    ref_cken    : out std_logic;
    reset_p     : in  std_logic := '0';
    -- Optional ConfigBus interface.
    cfg_cmd     : in  cfgbus_cmd := CFGBUS_CMD_NULL;
    cfg_ack     : out cfgbus_ack);
end ptp_counter_free;

architecture ptp_counter_free of ptp_counter_free is

-- Internal counter uses a finer resolution than the final timestamp.
-- (Note: Scale here isn't intrinsically tied to ConfigBus word size,
--        but this is the finest we can set with a simple register.)
constant TFINE_SCALE    : integer := CFGBUS_WORD_SIZE;
constant TFINE_EXTRA    : integer := TFINE_SCALE - TSTAMP_SCALE;
constant TFINE_WIDTH    : integer := TSTAMP_WIDTH + TFINE_EXTRA;
subtype tfine_t is unsigned(TFINE_WIDTH-1 downto 0);

-- Calculate the nominal increment based on effective clock rate.
constant ONE_SEC    : real := 1.0e9 * (2.0 ** TFINE_SCALE);
constant INCR_R     : real := real(REF_CLK_DIV) * ONE_SEC / REF_CLK_HZ;
constant INCR_U     : tfine_t := r2u(INCR_R, TFINE_WIDTH);

-- Free-running counter state.
signal tnext        : std_logic := bool2bit(REF_CLK_DIV = 1);
signal tstamp       : tfine_t := (others => '0');
signal cpu_incr     : tfine_t := (others => '0');
signal cpu_word     : cfgbus_word := (others => '0');

begin

-- Drive main output.
ref_ctr  <= tstamp(tstamp'left downto TFINE_EXTRA);
ref_cken <= tnext;

-- Main counter state machine.
p_ctr : process(ref_clk)
    constant DIV_MAX : natural := REF_CLK_DIV - 1;
    variable div_ctr : integer range 0 to DIV_MAX := DIV_MAX;
begin
    if rising_edge(ref_clk) then
        -- Counter increments once on each CKEN strobe.
        if (reset_p = '1') then
            tstamp <= (others => '0');
        elsif (tnext = '1') then
            tstamp <= tstamp + INCR_U + cpu_incr;
        end if;

        -- Clock-enable once every N clock cycles.
        tnext <= bool2bit(div_ctr = 0);
        if (reset_p = '1' or div_ctr = 0) then
            div_ctr := DIV_MAX;
        else
            div_ctr := div_ctr - 1;
        end if;
    end if;
end process;

-- Rescale the CPU adjustment word.
cpu_incr <= unsigned(resize(signed(cpu_word), TFINE_WIDTH));

-- Optional ConfigBus register.
-- Note: This optimizes down to a constant zero if ConfigBus is disconnected.
u_cpu : cfgbus_register_sync
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => REGADDR,
    WR_ATOMIC   => true,
    RSTVAL      => (others => '0'))
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    sync_clk    => ref_clk,
    sync_val    => cpu_word);

end ptp_counter_free;
