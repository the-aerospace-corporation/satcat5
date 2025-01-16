--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- ConfigBus-controlled piezoelectric buzzer
--
-- This block generates a square wave with user-controlled frequency,
-- suitable for direct-drive and MOSFET-driven piezeoelectric buzzers.
--
-- The user sets the increment per ConfigBus clock-cycle, for a 32-bit
-- accumulator operating at the ConfigBus clock rate (REFCLK_HZ).  To
-- generate a specific output frequency (OUT_HZ), set the increment:
--      incr = round(2^32 * OUT_HZ / REFCLK_HZ)
-- A phase increment of zero freezes the output, producing no sound.
--
-- Control is through a single read/write ConfigBus register:
--  * Write = Set new phase increment (see above)
--  * Read  = Report current phase increment (optional)
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;

entity cfgbus_piezo is
    generic (
    DEVADDR     : integer;              -- Control register address
    REGADDR     : integer := CFGBUS_ADDR_ANY);
    port (
    piezo_out   : out std_logic;        -- Square-wave output
    cfg_cmd     : in  cfgbus_cmd;       -- ConfigBus control
    cfg_ack     : out cfgbus_ack);      -- Optional readback
end cfgbus_piezo;

architecture cfgbus_piezo of cfgbus_piezo is

signal accum    : unsigned(31 downto 0) := (others => '0');
signal incr     : cfgbus_word;

begin

-- Output is simply the MSB of a phase-accumulator.
piezo_out <= accum(accum'left);

p_accum : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        if (cfg_cmd.reset_p = '1') then
            accum <= (others => '0');
        else
            accum <= accum + unsigned(incr);
        end if;
    end if;
end process;

-- Instantiate the phase-increment register.
u_incr : cfgbus_register
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => REGADDR,
    WR_ATOMIC   => true)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    reg_val     => incr);

end cfgbus_piezo;
