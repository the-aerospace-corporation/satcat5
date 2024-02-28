--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Asynchronous input conditioning for Xilinx FPGAs
--
-- This file implements the components defined in "common_primitives", using
-- explicit components and inference templates for Xilinx Ultrascale+ FPGAs.
--
-- NOTE: Designs should only include ONE such implementation!  If your
-- project includes "xilinx/ultrascale_sync.vhd", don't also include similar
-- files from the "lattice" or "microsemi" folder.
--

library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use     UNISIM.Vcomponents.all;

entity sync_toggle2pulse is
    generic(
    RISING_ONLY  : boolean := false;
    FALLING_ONLY : boolean := false;
    OUT_BUFFER   : boolean := false);
    port(
    in_toggle   : in  std_logic;
    out_strobe  : out std_logic;
    out_clk     : in  std_logic;
    reset_p     : in  std_logic := '0');
end sync_toggle2pulse;

architecture sync_toggle2pulse of sync_toggle2pulse is

signal in_toggle_d1  : std_logic;
signal in_toggle_d2  : std_logic;
signal in_toggle_d3  : std_logic;
signal out_combo     : std_logic;

-- Vivado ASYNC_REG flag forces nearby placement to ensure routing
-- delays don't eat into time needed for resolving metastability.
-- Note: No impact on timing analysis; refer to UG912.
attribute ASYNC_REG : string;
attribute ASYNC_REG of in_toggle_d1, in_toggle_d2 : signal is "TRUE";

-- Custom attribute makes it easy to "set_false_path" on cross-clock signals.
-- (Vivado explicitly DOES NOT allow such constraints to be set in the HDL.)
attribute satcat5_cross_clock_dst : boolean;
attribute satcat5_cross_clock_dst of in_toggle, in_toggle_d1 : signal is true;

begin

-- Sample the async toggle signal.
-- Two flip-flops in a row to allow metastable inputs to settle.
-- in_toggle_d1 is NOT safe to use in any logic.
-- Manually instantiate each flop, to prevent changes during optimization.
D0_reg : FDC
    port map (
    D   =>  in_toggle,
    Q   =>  in_toggle_d1,
    C   =>  out_clk,
    CLR =>  Reset_p);

D1_reg : FDC
    port map (
    D   =>  in_toggle_d1,
    Q   =>  in_toggle_d2,
    C   =>  out_clk,
    CLR =>  Reset_p);

D2_reg : FDC
    port map (
    D   =>  in_toggle_d2,
    Q   =>  in_toggle_d3,
    C   =>  out_clk,
    CLR =>  Reset_p);

-- Synchronization complete.  Output a pulse for every change
-- in the input signal, or for rising/falling edges only.
out_gen : process(in_toggle_d2, in_toggle_d3)
begin
    if(RISING_ONLY and not FALLING_ONLY) then
        out_combo <= in_toggle_d2 and not in_toggle_d3;
    elsif(FALLING_ONLY and not RISING_ONLY) then
        out_combo <= in_toggle_d3 and not in_toggle_d2;
    else
        out_combo <= in_toggle_d2 xor in_toggle_d3;
    end if;
end process;

-- Generate either the buffered or unbuffered output.
out_enbuf : if OUT_BUFFER generate
    out_reg : FDC
        port map (
        D   =>  out_combo,
        Q   =>  out_strobe,
        C   =>  out_clk,
        CLR =>  Reset_p);
end generate;

out_nobuf : if not OUT_BUFFER generate
    out_strobe <= out_combo;
end generate;

end;

---------------------------------------------------------------------

library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use     UNISIM.Vcomponents.all;

entity sync_buffer is
    port(
    in_flag     : in  std_logic;
    out_flag    : out std_logic;
    out_clk     : in  std_logic;
    reset_p     : in  std_logic := '0');
end sync_buffer;

architecture sync_buffer of sync_buffer is

signal in_flag_d1   : std_logic;
signal in_flag_d2   : std_logic;

-- Vivado ASYNC_REG flag forces nearby placement to ensure routing
-- delays don't eat into time needed for resolving metastability.
-- Note: No impact on timing analysis; refer to UG912.
attribute ASYNC_REG : string;
attribute ASYNC_REG of in_flag_d1, in_flag_d2 : signal is "TRUE";

-- Custom attribute makes it easy to "set_false_path" on cross-clock signals.
-- (Vivado explicitly DOES NOT allow such constraints to be set in the HDL.)
attribute satcat5_cross_clock_dst : boolean;
attribute satcat5_cross_clock_dst of in_flag, in_flag_d1 : signal is true;

begin

-- Sample the async toggle signal.
-- Two flip-flops in a row to allow metastable inputs to settle.
-- in_flag_d1 is NOT safe to use in synchronous logic.
-- Manually instantiate each flop, to prevent changes during optimization.
D0_reg : FDC
    port map (
    D   =>  in_flag,
    Q   =>  in_flag_d1,
    C   =>  out_clk,
    CLR =>  Reset_p);

D1_reg : FDC
    port map (
    D   =>  in_flag_d1,
    Q   =>  in_flag_d2,
    C   =>  out_clk,
    CLR =>  Reset_p);

out_flag <= in_flag_d2;

end;

---------------------------------------------------------------------

library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use     UNISIM.Vcomponents.all;
use     work.common_primitives.sync_toggle2pulse;

entity sync_pulse2pulse is
    generic(
    OUT_BUFFER  : boolean := false);
    port(
    in_strobe   : in  std_logic;
    in_clk      : in  std_logic;
    out_strobe  : out std_logic;
    out_clk     : in  std_logic;
    reset_p     : in  std_logic := '0');
end sync_pulse2pulse;

architecture sync_pulse2pulse of sync_pulse2pulse is

signal toggle_next  : std_logic;
signal toggle       : std_logic;

begin

-- Toggle every time we get an input pulse.
toggle_next <= toggle when in_strobe = '0' else not toggle;

toggle_reg : FDC
    port map (
    Q   =>  toggle,
    C   =>  in_clk,
    CLR =>  reset_p,
    D   =>  toggle_next);

-- Instantiate a sync_toggle2pulse.
sync_t2p : sync_toggle2pulse
    generic map(
    OUT_BUFFER  => OUT_BUFFER)
    port map(
    in_toggle   => toggle,
    out_strobe  => out_strobe,
    out_clk     => out_clk,
    reset_p     => reset_p);

end;

---------------------------------------------------------------------

library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
use     work.common_primitives.sync_buffer;

entity sync_reset is
    generic(
    HOLD_MIN    : integer := 7;
    KEEP_ATTR   : string := "true");
    port(
    in_reset_p  : in  std_logic;
    out_reset_p : out std_logic;
    out_clk     : in  std_logic);
end sync_reset;

architecture sync_reset of sync_reset is

signal sync_reset_p : std_logic := '0';
signal out_reset_i  : std_logic := '1';
signal countdown    : integer range 0 to HOLD_MIN := HOLD_MIN;

-- Force retention of the reset signal?
attribute DONT_TOUCH : string;
attribute DONT_TOUCH of out_reset_i : signal is KEEP_ATTR;
attribute KEEP : string;
attribute KEEP of out_reset_i : signal is KEEP_ATTR;

-- Custom attribute makes it easy to "set_false_path" on cross-clock signals.
-- (Vivado explicitly DOES NOT allow such constraints to be set in the HDL.)
attribute satcat5_cross_clock_dst : boolean;
attribute satcat5_cross_clock_dst of countdown, in_reset_p, out_reset_i : signal is true;

begin

-- Synchronize the reset signal.
u_sync : sync_buffer
    port map(
    in_flag     => in_reset_p,
    out_flag    => sync_reset_p,
    out_clk     => out_clk,
    reset_p     => '0');

-- Asynchronous set, synchronous clear after N cycles.
p_count : process(out_clk, in_reset_p)
begin
    if (in_reset_p = '1') then
        out_reset_i <= '1';
        countdown   <= HOLD_MIN;
    elsif rising_edge(out_clk) then
        if (sync_reset_p = '1') then
            out_reset_i <= '1';
            countdown   <= HOLD_MIN;
        elsif (countdown /= 0) then
            out_reset_i <= '1';
            countdown   <= countdown - 1;
        else
            out_reset_i <= '0';
        end if;
    end if;
end process;

out_reset_p <= out_reset_i;

end;
