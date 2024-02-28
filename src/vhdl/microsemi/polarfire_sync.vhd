--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Asynchronous input conditioning for Microsemi PolarFire FPGAs
--
-- This file implements the components defined in "common_sync", using
-- explicit components and inference templates for Microsemi PolarFire FPGAs.
--
-- NOTE: Designs should only include ONE such implementation!  If your
-- project includes "xilinx/7series_sync.vhd", don't also include similar
-- files from the "lattice" or "microsemi" folder.
--

library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;

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
-- Unable to find documentation for Polarfire
attribute ASYNC_REG : string;
attribute ASYNC_REG of in_toggle_d1, in_toggle_d2 : signal is "TRUE";

signal reset_n : std_logic;
component DFN1C0
    port(
    D   : in  std_logic;
    Q   : out std_logic;
    CLK : in  std_logic;
    CLR : in  std_logic);
end component;

begin

reset_n <= not reset_p;

-- Sample the async toggle signal.
-- Two flip-flops in a row to allow metastable inputs to settle.
-- in_toggle_d1 is NOT safe to use in any logic.
-- Manually instantiate each flop, to prevent changes during optimization.
D0_reg : DFN1C0
    port map (
    D   =>  in_toggle,
    Q   =>  in_toggle_d1,
    CLK =>  out_clk,
    CLR =>  reset_n);

D1_reg : DFN1C0
    port map (
    D   =>  in_toggle_d1,
    Q   =>  in_toggle_d2,
    CLK =>  out_clk,
    CLR =>  reset_n);

D2_reg : DFN1C0
    port map (
    D   =>  in_toggle_d2,
    Q   =>  in_toggle_d3,
    CLK =>  out_clk,
    CLR =>  reset_n);

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
    out_reg : DFN1C0
        port map (
        D   =>  out_combo,
        Q   =>  out_strobe,
        CLK =>  out_clk,
        CLR =>  reset_n);
end generate;

out_nobuf : if not OUT_BUFFER generate
    out_strobe <= out_combo;
end generate;

end;

--------------------------------------------------------------------------

library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;

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
-- Unable to find documentation for Polarfire
attribute ASYNC_REG : string;
attribute ASYNC_REG of in_flag_d1, in_flag_d2 : signal is "TRUE";

signal reset_n : std_logic;
component DFN1C0
    port(
    D   : in  std_logic;
    Q   : out std_logic;
    CLK : in  std_logic;
    CLR : in  std_logic);
end component;

begin

reset_n <= not reset_p;

-- Sample the async toggle signal.
-- Two flip-flops in a row to allow metastable inputs to settle.
-- in_flag_d1 is NOT safe to use in synchronous logic.
-- Manually instantiate each flop, to prevent changes during optimization.
D0_reg : DFN1C0
    port map (
    D   =>  in_flag,
    Q   =>  in_flag_d1,
    CLK =>  out_clk,
    CLR =>  reset_n);

D1_reg : DFN1C0
    port map (
    D   =>  in_flag_d1,
    Q   =>  in_flag_d2,
    CLK =>  out_clk,
    CLR =>  reset_n);

out_flag <= in_flag_d2;

end;

--------------------------------------------------------------------------

library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
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

signal reset_n : std_logic;
component DFN1C0
    port(
    D   : in  std_logic;
    Q   : out std_logic;
    CLK : in  std_logic;
    CLR : in  std_logic);
end component;

begin

reset_n <= not reset_p;

-- Toggle every time we get an input pulse.
toggle_next <= toggle when in_strobe = '0' else not toggle;

toggle_reg : DFN1C0
    port map (
    Q   =>  toggle,
    CLK =>  in_clk,
    CLR =>  reset_n,
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

--------------------------------------------------------------------------

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

attribute KEEP : string;
attribute KEEP of out_reset_i : signal is KEEP_ATTR;

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
    variable countdown : integer range 0 to HOLD_MIN := HOLD_MIN;
begin
    if (in_reset_p = '1') then
        out_reset_i <= '1';
        countdown   := HOLD_MIN;
    elsif rising_edge(out_clk) then
        if (sync_reset_p = '1') then
            out_reset_i <= '1';
            countdown   := HOLD_MIN;
        elsif (countdown /= 0) then
            out_reset_i <= '1';
            countdown   := countdown - 1;
        else
            out_reset_i <= '0';
        end if;
    end if;
end process;

out_reset_p <= out_reset_i;

end;
