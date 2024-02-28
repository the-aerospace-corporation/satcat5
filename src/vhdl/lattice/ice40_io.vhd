--------------------------------------------------------------------------
-- Copyright 2021-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- I/O structures for Lattice iCE40 FPGAs.
--
-- For cross-platform support, other blocks in this design use generic
-- wrappers for vendor-specific I/O structures.  This file contains
-- implementations of these structures for Lattice iCE40 FPGAs.
--
-- NOTE: Designs should only include ONE such implementation!  If your
-- project includes "xilinx/7series_io.vhd", don't also include similar
-- files from the "lattice" or "microsemi" folder.
--

library ieee;
use     ieee.std_logic_1164.all;

package ice40_sbtice is
    -- "PIN TYPE" constant concatenates output mode, then an input mode.
    -- For more information refer to the SBTICE Technology Library.
    -- http://www.latticesemi.com/~/media/LatticeSemi/Documents/TechnicalBriefs/SBTICETechnologyLibrary201504.pdf
    subtype pin_mode_t is std_logic_vector(5 downto 0);

    subtype pin_mode_out is std_logic_vector(3 downto 0);
    constant PIN_OUTNONE    : pin_mode_out := "0000";   -- Output disabled
    constant PIN_OUTPUT     : pin_mode_out := "0110";   -- Simple output
    constant PIN_OUTPUT_EN  : pin_mode_out := "1010";   -- ...with enable/tristate
    constant PIN_OUTPUT_ENR : pin_mode_out := "1110";   -- ...with enable register
    constant PIN_OUTREG     : pin_mode_out := "0101";   -- SDR registered output
    constant PIN_OUTREG_EN  : pin_mode_out := "1001";
    constant PIN_OUTREG_ENR : pin_mode_out := "1101";
    constant PIN_OUTDDR     : pin_mode_out := "0100";   -- DDR registered output
    constant PIN_OUTDDR_EN  : pin_mode_out := "1000";
    constant PIN_OUTDDR_ENR : pin_mode_out := "1100";
    constant PIN_OUTINV     : pin_mode_out := "0111";   -- SDR inverted output
    constant PIN_OUTINV_EN  : pin_mode_out := "1011";
    constant PIN_OUTINV_ENR : pin_mode_out := "1111";

    subtype pin_mode_in is std_logic_vector(1 downto 0);
    constant PIN_INSIMPLE  : pin_mode_in := "01";      -- Simple input
    constant PIN_INLATCH   : pin_mode_in := "11";      -- Input with latch
    constant PIN_INREG     : pin_mode_in := "00";      -- Registered input
    constant PIN_INRLATCH  : pin_mode_in := "10";      -- Registered with latch
    constant PIN_INDDR     : pin_mode_in := "00";      -- DDR registered input

    -- Define various primitives from the SBTICE Technlogy Library:
    -- http://www.latticesemi.com/~/media/LatticeSemi/Documents/TechnicalBriefs/SBTICETechnologyLibrary201504.pdf
    component SB_DFFR
        port(
        D : in  std_logic;
        Q : out std_logic;
        C : in  std_logic;
        R : in  std_logic);
    end component;

    component SB_GB_IO
        generic(
        PIN_TYPE            : pin_mode_t);
        port(
        PACKAGE_PIN         : in  std_logic;
        LATCH_INPUT_VALUE   : in  std_logic := '0';
        CLOCK_ENABLE        : in  std_logic := '1';
        INPUT_CLK           : in  std_logic := '0';
        OUTPUT_CLK          : in  std_logic := '0';
        OUTPUT_ENABLE       : in  std_logic := '0';
        D_OUT_0             : in  std_logic := '0';
        D_OUT_1             : in  std_logic := '0';
        D_IN_0              : out std_logic;
        D_IN_1              : out std_logic;
        GLOBAL_BUFFER_OUTPUT: out std_logic);
    end component;

    component SB_IO
        generic(
        PIN_TYPE            : pin_mode_t;
        PULLUP              : std_logic;
        NEG_TRIGGER         : std_logic);
        port(
        PACKAGE_PIN         : inout std_logic;
        LATCH_INPUT_VALUE   : in    std_logic := '0';
        CLOCK_ENABLE        : in    std_logic := '1';
        INPUT_CLK           : in    std_logic := '0';
        OUTPUT_CLK          : in    std_logic := '0';
        OUTPUT_ENABLE       : in    std_logic := '0';
        D_OUT_0             : in    std_logic := '0';
        D_OUT_1             : in    std_logic := '0';
        D_IN_0              : out   std_logic;
        D_IN_1              : out   std_logic);
    end component;
end package;

---------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     work.ice40_sbtice.all;
use     work.common_functions.all;

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

signal out_en     : std_logic;

begin

out_en <= not t_en;

gen_pd : if EN_PULLDN generate
    assert false report "not implemented" severity error;
end generate;

u_iobuf : SB_IO
    generic map(
        PIN_TYPE => PIN_OUTPUT_EN & PIN_INSIMPLE,
        PULLUP => bool2bit(EN_PULLUP),
        NEG_TRIGGER => '0')
    port map(
        PACKAGE_PIN => io_pin,
        OUTPUT_ENABLE => out_en,
        D_OUT_0 => d_out,
        D_OUT_1 => '0',
        D_IN_0 => d_in,
        D_IN_1 => open);

end ice40;

---------------------------------------------------------------------

library ieee;
use     ieee.math_real.all; -- For round()
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.ice40_sbtice.all;

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
signal clk_i, clk_buf : std_logic;

begin

-- Optional input delay.
gen_dly_en : if (DELAY_TAPS_INT >= 0) generate
    assert false report "not implemented" severity error;
end generate;

-- Optional clock-deskew using MMCM.
gen_deskew : if DESKEW_EN generate
    assert false report "not implemented" severity error;
end generate;

-- only global clock buffers on ice40.
u_clkbuf : SB_GB_IO
    generic map(
        PIN_TYPE => PIN_OUTNONE & PIN_INSIMPLE)
    port map(
        PACKAGE_PIN => clk_pin,
        GLOBAL_BUFFER_OUTPUT => clk_buf);

clk_out <= clk_buf;

end ice40;

---------------------------------------------------------------------

library ieee;
use     ieee.math_real.all; -- For round()
use     ieee.std_logic_1164.all;
use     work.ice40_sbtice.all;

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

signal d_tmp    : std_logic;
signal q_re_raw : std_logic;
signal q_fe_raw : std_logic;

begin

-- Optional input delay is not supported.
gen_dly_en : if (DELAY_TAPS_INT >= 0) generate
    assert false report "not implemented" severity error;
end generate;

-- Compatibility fix for "INOUT" port on SB_IO primitive.
-- TODO: This allows compilation, bug GHDL throws a "multiple assignments"
--       error if the block is ever instantiated.  Need a better workaround.
d_tmp <= d_pin;

-- The Lattice input DDR is equivalent to Xilinx IDDR in OPPOSITE_EDGE mode
-- We add pipeline registers on each output to make a SAME_EDGE_PIPELINED equivalent
u_iddr : SB_IO
    generic map(
        PIN_TYPE => PIN_OUTNONE & PIN_INDDR,
        PULLUP => '0',
        NEG_TRIGGER => '0')
    port map(
        PACKAGE_PIN => d_tmp,
        INPUT_CLK => clk,
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

---------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     work.ice40_sbtice.all;

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
        PIN_TYPE => PIN_OUTDDR & PIN_INDDR,
        PULLUP => '0',
        NEG_TRIGGER => '0')
    port map(
        PACKAGE_PIN => q_fix,
        OUTPUT_CLK => clk,
        OUTPUT_ENABLE => '1', -- actually ignored by PIN_TYPE setting
        D_OUT_0 => d_re,
        D_OUT_1 => d_fe_pipe,
        D_IN_0 => open,
        D_IN_1 => open);

-- Compatibility fix for "INOUT" port on SB_IO primitive.
q_pin <= q_fix;

end ice40;
