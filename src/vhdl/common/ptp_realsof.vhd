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
-- Software-readable real-time-clock timestamps for Precision Time Protocol
--
-- This block allows software to read the RTC timestamp for the start of
-- each transmit or received frame.  The ConfigBus interface mirrors that
-- of the "ptp_realtime" block.
--
-- The ConfigBus interface uses four consecutive read-only registers:
--  * Base + 0: Seconds MSBs
--      Bits 31..16: Reserved (reads as sign-extension)
--      Bits 15..00: Signed "Seconds" field, bits 47..32
--  * Base + 1: Seconds LSBs
--      Bits 31..00: Signed "Seconds" field, bits 31..00
--  * Base + 2: Nanoseconds (bits 31..00)
--      Bits 31..00: Unsigned "Nanoseconds" field
--  * Base + 3: Command + Subnanoseconds (bits 15..00)
--      Bits 31..16: Reserved (reads as zero)
--      Bits 15..00: Unsigned "Subnanoseconds" field (1 LSB = 2^-16 nsec)
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.ptp_types.all;

entity ptp_realsof is
    generic (
    DEV_ADDR    : integer;      -- ConfigBus device address
    REG_BASE    : integer);     -- Note: Four consecutive registers
    port (
    -- Current time and input stream.  (Sync to cfg_cmd.clk)
    in_tnow     : in  ptp_time_t;
    in_last     : in  std_logic;
    in_write    : in  std_logic;

    -- ConfigBus interface.
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack);
end ptp_realsof;

architecture ptp_realsof of ptp_realsof is

signal in_first     : std_logic := '1';
signal time_reg     : ptp_time_t := PTP_TIME_ZERO;
signal cfg_ack_i    : cfgbus_ack := cfgbus_idle;
signal cfg_sec_msb  : cfgbus_word;
signal cfg_sec_lsb  : cfgbus_word;
signal cfg_nsec     : cfgbus_word;
signal cfg_subns    : cfgbus_word;

begin

-- Drive top-level outputs.
cfg_ack <= cfg_ack_i;

-- Track start-of-frame and latch timestamp.
p_tstamp : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- Update the start-of-frame indicator.
        if (cfg_cmd.reset_p = '1') then
            in_first <= '1';        -- Global reset, next is SOF
        elsif (in_write = '1') then
            in_first <= in_last;    -- End of frame, next is SOF
        end if;

        -- Latch the start-of-frame timestamp.
        if (in_write = '1' and in_first = '1') then
            time_reg <= in_tnow;
        end if;
    end if;
end process;

-- ConfigBus interface.
cfg_sec_msb <= std_logic_vector(resize(time_reg.sec(47 downto 32), 32));
cfg_sec_lsb <= std_logic_vector(time_reg.sec(31 downto 0));
cfg_nsec    <= std_logic_vector(resize(time_reg.nsec, 32));
cfg_subns   <= std_logic_vector(resize(time_reg.subns, 32));

p_cfgbus : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- Handle reads for each register.
        if (cfgbus_rdcmd(cfg_cmd, DEV_ADDR, REG_BASE+0)) then
            cfg_ack_i <= cfgbus_reply(cfg_sec_msb);
        elsif (cfgbus_rdcmd(cfg_cmd, DEV_ADDR, REG_BASE+1)) then
            cfg_ack_i <= cfgbus_reply(cfg_sec_lsb);
        elsif (cfgbus_rdcmd(cfg_cmd, DEV_ADDR, REG_BASE+2)) then
            cfg_ack_i <= cfgbus_reply(cfg_nsec);
        elsif (cfgbus_rdcmd(cfg_cmd, DEV_ADDR, REG_BASE+3)) then
            cfg_ack_i <= cfgbus_reply(cfg_subns);
        else
            cfg_ack_i <= cfgbus_idle;
        end if;
    end if;
end process;

end ptp_realsof;
