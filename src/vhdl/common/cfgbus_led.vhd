--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
