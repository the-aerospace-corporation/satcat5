--------------------------------------------------------------------------
-- Copyright 2021-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Block diagram wrapper for "sync_reset"
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_primitives.sync_reset;

entity wrap_reset_hold is
    generic (
    RESET_HIGH  : boolean;          -- Choose input polarity
    RESET_HOLD  : natural);         -- Minimum reset duration, in clocks
    port (
    aresetp     : in  std_logic;    -- Async reset, active high
    aresetn     : in  std_logic;    -- Async reset, active low
    clk         : in  std_logic;    -- Reference clock
    reset_p     : out std_logic;    -- Output reset, active high
    reset_n     : out std_logic);   -- Output reset, active low
end wrap_reset_hold;

architecture wrap_reset_hold of wrap_reset_hold is

signal in_reset_p   : std_logic;
signal out_reset_p  : std_logic;

begin

-- Polarity conversion
in_reset_p  <= (aresetp) when RESET_HIGH else (not aresetn);
reset_n     <= not out_reset_p;
reset_p     <= out_reset_p;

-- Instantiate the platform-specific primitive.
u_rst : sync_reset
    generic map(HOLD_MIN => RESET_HOLD)
    port map(
    in_reset_p  => in_reset_p,
    out_reset_p => out_reset_p,
    out_clk     => clk);

end wrap_reset_hold;
