--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation
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
-- I/O structures for Lattice iCE40 FPGAs.
--
-- For cross-platform support, other blocks in this design use generic
-- wrappers for vendor-specific I/O structures.  This file contains
-- implementations of these structures for Lattice iCE40 FPGAs.
--
-- NOTE: Most designs should only include ONE such implementation.  If
-- you include io_xilinx.vhd in your project, don't include io_ice40.
--

library ieee;
use     ieee.std_logic_1164.all;

entity bidir_io is
    generic (
    EN_PULLDN   : boolean := false;     -- Include a weak pulldown?
    EN_PULLUP   : boolean := false);    -- Include a weak pullup?
    port (
    io_pin  : inout std_logic;      -- The external pin
    d_in    : out   std_logic;      -- Input to FPGA, if T = 1
    d_out   : in    std_logic;      -- Output from FPGA, if T = 0
    t_en    : in    std_logic);     -- Tristate enable (1 = Input/Hi-Z, 0 = Output)
end bidir_io;

architecture ice40 of bidir_io is

    signal use_pullup : std_logic;
    signal out_en     : std_logic;

    component SB_IO
    generic(
        PIN_TYPE    : std_logic_vector;
        PULLUP      : std_logic;
        NEG_TRIGGER : std_logic);
    port(
        PACKAGE_PIN       : inout std_logic;
        LATCH_INPUT_VALUE : in  std_logic;
        CLOCK_ENABLE      : in  std_logic;
        INPUT_CLK         : in  std_logic;
        OUTPUT_CLK        : in  std_logic;
        OUTPUT_ENABLE     : in  std_logic;
        D_OUT_0           : in std_logic;
        D_OUT_1           : in std_logic;
        D_IN_0            : out std_logic;
        D_IN_1            : out std_logic);
end component;

begin

out_en <= not t_en;

gen_pd : if EN_PULLDN generate
    assert false report "not implemented" severity error;
end generate;

use_pullup <= '1' when EN_PULLUP else '0';

u_iobuf : SB_IO
    generic map(
        PIN_TYPE => b"101001",
        PULLUP => use_pullup,
        NEG_TRIGGER => '0')
    port map(
        PACKAGE_PIN => io_pin,
        LATCH_INPUT_VALUE => '0',
        CLOCK_ENABLE => '0',
        INPUT_CLK => '0',
        OUTPUT_CLK => '0',
        OUTPUT_ENABLE => out_en,
        D_OUT_0 => d_out,
        D_OUT_1 => '0',
        D_IN_0 => d_in,
        D_IN_1 => open);

end ice40;



library ieee;
use     ieee.math_real.all; -- For round()
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;

entity clk_input is
    generic (
    CLKIN_MHZ   : real;             -- Input clock frequency
    GLOBAL_BUFF : boolean := false; -- Global or local output buffer
    DESKEW_EN   : boolean := false; -- Clock synth for deskew?
    DELAY_NSEC  : real := -1.0);    -- Optional delay (<0 to disable)
    port (
    reset_p : in  std_logic;        -- Reset (hold 1 msec after shdn_p if used)
    shdn_p  : in  std_logic := '0'; -- Shutdown (optional, DESKEW_EN only)
    clk_pin : in  std_logic;        -- External clock input
    clk_out : out std_logic);       -- Buffered clock output
end clk_input;

architecture ice40 of clk_input is

constant DELAY_TAPS_INT : integer :=
    integer(round(DELAY_NSEC / 0.078125));

-- Choose multiplier ratio to put VCO ~1000 MHz (max range 600-1400 MHz).
constant MMCM_RATIO : integer :=
    integer(round(1000.0 / CLKIN_MHZ));

-- Declare intermediate clock signals.
signal clk_dly, clk_mmcm, clk_buf : std_logic;

component SB_GB
    port(
    USER_SIGNAL_TO_GLOBAL_BUFFER : in  std_logic;
    GLOBAL_BUFFER_OUTPUT : out std_logic);
end component;

begin

-- Optional input delay.
gen_dly_en : if (DELAY_TAPS_INT >= 0) generate
    assert false report "not implemented" severity error;
end generate;

gen_dly_no : if (DELAY_TAPS_INT < 0) generate
    clk_dly <= clk_pin;
end generate;

-- Optional clock-deskew using MMCM.
gen_deskew : if DESKEW_EN generate
    assert false report "not implemented" severity error;
end generate;

gen_direct : if not DESKEW_EN generate
    clk_mmcm <= clk_dly;
end generate;

-- Regional or global clock buffer.
gen_global : if GLOBAL_BUFF generate
    -- TODO: May want to use SB_GB_IO?
    u_bufh : SB_GB
        port map(
        USER_SIGNAL_TO_GLOBAL_BUFFER => clk_mmcm,
        GLOBAL_BUFFER_OUTPUT => clk_buf);
end generate;

gen_region : if not GLOBAL_BUFF generate
    clk_buf <= clk_mmcm;
end generate;

clk_out <= clk_buf;

end ice40;



library ieee;
use     ieee.math_real.all; -- For round()
use     ieee.std_logic_1164.all;

entity ddr_input is
    generic (
    DELAY_NSEC  : real := -1.0);    -- Optional delay (<0 to disable)
    port (
    d_pin   : in  std_logic;
    clk     : in  std_logic;
    q_re    : out std_logic;
    q_fe    : out std_logic);
end ddr_input;

architecture ice40 of ddr_input is

constant DELAY_TAPS_INT : integer :=
    integer(round(DELAY_NSEC / 0.078125));

signal d_dly : std_logic;
signal q_re_raw : std_logic;
signal q_fe_raw : std_logic;

component SB_IO
    generic(
        PIN_TYPE    : std_logic_vector;
        PULLUP      : std_logic;
        NEG_TRIGGER : std_logic);
    port(
        PACKAGE_PIN       : inout std_logic;
        LATCH_INPUT_VALUE : in  std_logic;
        CLOCK_ENABLE      : in  std_logic;
        INPUT_CLK         : in  std_logic;
        OUTPUT_CLK        : in  std_logic;
        OUTPUT_ENABLE     : in  std_logic;
        D_OUT_0           : in std_logic;
        D_OUT_1           : in std_logic;
        D_IN_0            : out std_logic;
        D_IN_1            : out std_logic);
end component;

component SB_DFFR
    port(
    D : in  std_logic;
    Q : out std_logic;
    C : in  std_logic;
    R : in  std_logic);
end component;

begin

-- Optional input delay.
gen_dly_en : if (DELAY_TAPS_INT >= 0) generate
    assert false report "not implemented" severity error;
end generate;

gen_dly_no : if (DELAY_TAPS_INT < 0) generate
    d_dly <= d_pin;
end generate;

-- The Lattice input DDR is equivalent to Xilinx IDDR in OPPOSITE_EDGE mode
-- We add pipeline registers on each output to make a SAME_EDGE_PIPELINED equivalent
u_iddr : SB_IO
    generic map(
        PIN_TYPE => b"000000",
        PULLUP => '0',
        NEG_TRIGGER => '0')
    port map(
        PACKAGE_PIN => d_dly,
        LATCH_INPUT_VALUE => '0',
        CLOCK_ENABLE => '1',
        INPUT_CLK => clk,
        OUTPUT_CLK => '0',
        OUTPUT_ENABLE => '0',
        D_OUT_0 => '0',
        D_OUT_1 => '0',
        D_IN_0 => q_re_raw,
        D_IN_1 => q_fe_raw);

re_reg : SB_DFFR
    port map(
    D => q_re_raw,
    Q => q_re,
    C => clk,
    R => '0');

fe_reg : SB_DFFR
    port map(
    D => q_fe_raw,
    Q => q_fe,
    C => clk,
    R => '0');

end ice40;



library ieee;
use     ieee.std_logic_1164.all;

entity ddr_output is
    port (
    d_re    : in  std_logic;
    d_fe    : in  std_logic;
    clk     : in  std_logic;
    q_pin   : out std_logic);
end ddr_output;

architecture ice40 of ddr_output is

signal d_fe_pipe : std_logic;
signal q_fix     : std_logic;

component SB_IO
    generic(
        PIN_TYPE    : std_logic_vector;
        PULLUP      : std_logic;
        NEG_TRIGGER : std_logic);
    port(
        PACKAGE_PIN       : inout std_logic;
        LATCH_INPUT_VALUE : in  std_logic;
        CLOCK_ENABLE      : in  std_logic;
        INPUT_CLK         : in  std_logic;
        OUTPUT_CLK        : in  std_logic;
        OUTPUT_ENABLE     : in  std_logic;
        D_OUT_0           : in std_logic;
        D_OUT_1           : in std_logic;
        D_IN_0            : out std_logic;
        D_IN_1            : out std_logic);
end component;

component SB_DFFR
    port(
    D : in  std_logic;
    Q : out std_logic;
    C : in  std_logic;
    R : in  std_logic);
end component;

begin

fe_reg : SB_DFFR
    port map(
    D => d_fe,
    Q => d_fe_pipe,
    C => clk,
    R => '0');

-- The Lattice output DDR is equivalent to Xilinx ODDR in OPPOSITE_EDGE mode
-- We add a pipeline register to capture d_fe on the rising edge to present to
-- the DDR on the falling edge. This mimics Xilinx SAME_EDGE mode.
u_oddr : SB_IO
    generic map(
        PIN_TYPE => b"010000",
        PULLUP => '0',
        NEG_TRIGGER => '0')
    port map(
        PACKAGE_PIN => q_fix,
        LATCH_INPUT_VALUE => '0',
        CLOCK_ENABLE => '1',
        INPUT_CLK => '0',
        OUTPUT_CLK => clk,
        OUTPUT_ENABLE => '1', -- actually ignored by PIN_TYPE setting
        D_OUT_0 => d_re,
        D_OUT_1 => d_fe_pipe,
        D_IN_0 => open,
        D_IN_1 => open);

q_pin <= q_fix;

end ice40;
