--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation
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
-- ConfigBus-controlled array of PWM LEDs.
--
-- This block implements an array PWM controllers, each controlled by
-- a single ConfigBus register:
--  * REGADDR = N: Set brightness of Nth LED (read/write)
--      Bits 31-08: Reserved (write zeros)
--      Bits 07-00: New brightness (0-255)
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.io_leds.pwm_led;

entity cfgbus_led is
    generic (
    DEVADDR     : integer;              -- Control register address
    LED_COUNT   : positive;             -- Number of PWM channels
    LED_LIT     : std_logic := '0');    -- LED polarity
    port (
    led_out     : out std_logic_vector(LED_COUNT-1 downto 0);
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack);
end cfgbus_led;

architecture cfgbus_led of cfgbus_led is

signal cfg_acks : cfgbus_ack_array(LED_COUNT-1 downto 0);

begin

-- Instantiate each LED controller
gen_led : for n in led_out'range generate
    blk_led : block is
        signal brt : cfgbus_word;
    begin
        -- ConfigBus control register.
        u_cfg : cfgbus_register
            generic map(
            DEVADDR     => DEVADDR,
            REGADDR     => n,
            WR_ATOMIC   => true,
            WR_MASK     => x"000000FF")
            port map(
            cfg_cmd     => cfg_cmd,
            cfg_ack     => cfg_acks(n),
            reg_val     => brt);

        -- PWM controller
        u_pwm : pwm_led
            generic map(LED_LIT => LED_LIT)
            port map(
            led   => led_out(n),
            clk   => cfg_cmd.clk,
            brt   => unsigned(brt(7 downto 0)));
    end block;
end generate;

-- Consolidate ConfigBus responses.
cfg_ack <= cfgbus_merge(cfg_acks);

end cfgbus_led;
