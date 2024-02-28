--------------------------------------------------------------------------
-- Copyright 2021-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- PWM LED drivers with various patterns
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.round;

package IO_LEDS is
    -- A variable-brightness LED, using pulse-width modulation (PWM).
    -- Note: By default, LEDs are assumed to be active-low (e.g. Nallatech)
    component pwm_led is
        generic (
            LED_LIT  : std_logic := '0');
        port (
            LED   : out std_logic;
            Clk   : in  std_logic;
            Brt   : in  unsigned(7 downto 0));
    end component;

    -- A variant of blink_led that uses a gentle "breathing" pattern.
    -- (The pattern is stored in a small lookup table.)
    -- The complete cycle occurs every 64 * RATE * PREDIV clock cycles.
    component breathe_led is
        generic (
            RATE     : positive := 10000000;
            PREDIV   : positive := 1;
            LED_LIT  : std_logic := '0');
        port (
            LED   : out std_logic;
            Clk   : in  std_logic);
    end component;

    -- A variant of sustain_led that instantly turns to full brightness
    -- when an input pulse is received, then dims gradually over time.
    -- The pattern is approximately exponential, exp(-t/tau), with a
    -- time constant of approximately 16 * DIV * PREDIV clock cycles.
    component sustain_exp_led is
        generic (
            DIV      : positive := 10000000;
            PREDIV   : positive := 1;
            LED_LIT  : std_logic := '0');
        port (
            LED   : out std_logic;
            Clk   : in  std_logic;
            pulse : in  std_logic);
    end component;

    -- Helper function to configure "breathe_led".
    -- Returns RATE setting to put period at ~2.0 seconds.
    function breathe_led_rate(clk_hz : positive) return positive;
    function breathe_led_rate(clk_hz : real) return positive;
end IO_LEDS;




----------------------- Function definitions --------------------------
package body IO_LEDS is
    function breathe_led_rate(clk_hz : positive) return positive is
    begin
        return (clk_hz + 16) / 32;  -- Round-nearest
    end function;

    function breathe_led_rate(clk_hz : real) return positive is
    begin
        return integer(round(clk_hz / 32.0));
    end function;
end package body;




----------------------- Definition for PWM_LED ------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pwm_led is
    generic (
        LED_LIT  : std_logic := '0');
    port (
        LED   : out std_logic;
        Clk   : in  std_logic;
        Brt   : in  unsigned(7 downto 0));
end pwm_led;

architecture behav of pwm_led is
begin
    -- Note: PWM tested successfully on an ML605 with a 125 MHz clock.
    LED_p: process(Clk)
        variable count : unsigned(7 downto 0) := (others => '0');
        variable brt_d : unsigned(7 downto 0) := (others => '0');
    begin
        if rising_edge(Clk) then
            if(count < brt_d) then
                LED <= LED_LIT;
            else
                LED <= not LED_LIT;
            end if;

            -- The duty cycle is a fraction from 0/255 to 255/255.
            -- Therefore, the counter only goes from 0 to 254, not 255.
            if(count < 254) then
                count := count + 1;
            else
                count := (others => '0');
            end if;

            brt_d := brt;       -- Local register helps with timing
        end if;
    end process;
end;




----------------------- Definition for BREATHE_LED ------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.io_leds.pwm_led;

entity breathe_led is
    generic (
        RATE     : positive := 10000000;
        PREDIV   : positive := 1;
        LED_LIT  : std_logic := '0');
    port (
        LED   : out std_logic;
        Clk   : in  std_logic);
end breathe_led;

architecture behav of breathe_led is
    -- Lookup table for the brightness over time is a simple sinusoid.
    -- This has 64 entries in order to appear adequately smooth at the
    -- target period of 1-2 seconds.
    constant LOOKUP_LEN   : integer := 64;
    constant LOOKUP_TABLE : unsigned(LOOKUP_LEN*8-1 downto 0) :=
        x"0102050A0F151D252F39434F5A6773808C98A5B0BCC6D0DAE2EAF0F5FAFDFEFF" &
        x"FEFDFAF5F0EAE2DAD0C6BCB0A5988C8073675A4F43392F251D150F0A05020100";

    signal brt : unsigned(7 downto 0) := (others => '0');
begin

    assert(RATE /= 0)
        report "LED breathe duration cannot be zero.";
    assert(PREDIV /= 0)
        report "LED breathe pre-divider cannot be zero.";

    -- Use a PWM driver
    led_driver : pwm_led
        generic map(LED_LIT => LED_LIT)
        port map(
            LED   => LED,
            Clk   => Clk,
            Brt   => brt);

    -- Update the PWM setting every RATE*PREDIV clock cycles.
    lookup_p : process(Clk)
        variable count    : integer range 0 to RATE-1       := RATE-1;
        variable precount : integer range 0 to PREDIV-1     := PREDIV-1;
        variable idx      : integer range 0 to LOOKUP_LEN-1 := LOOKUP_LEN-1;
    begin
        if rising_edge(Clk) then
            brt <= lookup_table(8*idx+7 downto 8*idx);

            if(precount /= 0) then
                precount := precount - 1;
            elsif(count /= 0) then
                precount := PREDIV - 1;
                count    := count - 1;
            else
                precount := PREDIV - 1;
                count    := RATE - 1;
                if(idx /= 0) then
                    idx := idx - 1;
                else
                    idx := LOOKUP_LEN-1;
                end if;
            end if;
        end if;
    end process;
end;




--------------------- Definition for SUSTAIN_EXP_LED ----------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.io_leds.pwm_led;

entity sustain_exp_led is
    generic (
        DIV      : positive := 10000000;
        PREDIV   : positive := 1;
        LED_LIT  : std_logic := '0');
    port (
        LED   : out std_logic;
        Clk   : in  std_logic;
        pulse : in  std_logic);
end sustain_exp_led;

architecture behav of sustain_exp_led is
    signal brt : unsigned(7 downto 0) := (others => '0');
begin

    assert(DIV /= 0)
        report "LED sustain divider cannot be zero.";
    assert(PREDIV /= 0)
        report "LED sustain pre-divider cannot be zero.";

    -- Use a PWM driver
    led_driver : pwm_led
        generic map(LED_LIT => LED_LIT)
        port map(
            LED   => LED,
            Clk   => Clk,
            Brt   => brt);

    -- Update the PWM setting every RATE*PREDIV clock cycles,
    -- or when we receive an input pulse.
    control_p : process(Clk)
        variable count    : integer range 0 to DIV-1        := DIV-1;
        variable precount : integer range 0 to PREDIV-1     := PREDIV-1;
    begin
        if rising_edge(Clk) then
            if(pulse = '1') then
                -- Each input pulse takes us to full brightness
                -- and resets the countdown timers.
                precount := PREDIV-1;
                count    := DIV-1;
                brt      <= (others => '1');
            elsif(precount /= 0) then
                precount := precount - 1;
            elsif(count /= 0) then
                precount := PREDIV - 1;
                count    := count - 1;
            else
                precount := PREDIV-1;
                count    := DIV-1;

                -- Multiply brightness by 15/16 each time, rounding down.
                -- Ignoring roundoff error, this gives a time constant
                -- of -1/ln(15/16) = 15.5 iterations.
                brt <= brt/2 + brt/4 + brt/8 + brt/16;
            end if;
        end if;
    end process;
end;
