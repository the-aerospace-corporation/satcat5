--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- I/O structures for Xilinx FPGAs.
--
-- For cross-platform support, other blocks in this design use generic
-- wrappers for vendor-specific I/O structures.  This file contains
-- implementations of these structures for Xilinx 7-Series FPGAs.
--
-- NOTE: Designs should only include ONE such implementation!  If your
-- project includes "xilinx/7series_io.vhd", don't also include similar
-- files from the "lattice" or "microsemi" folder.
--

library ieee;
use     ieee.std_logic_1164.all;
library unisim;
use     unisim.vcomponents.all;

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

architecture xilinx of bidir_io is

begin

gen_pd : if EN_PULLDN generate
    u_pd : PULLDOWN port map(io_pin);
end generate;

gen_pu : if EN_PULLUP generate
    u_pu : PULLUP port map(io_pin);
end generate;

u_iobuf : IOBUF
    port map(
    IO  => io_pin,
    O   => d_in,
    I   => d_out,
    T   => t_en);

end xilinx;



library ieee;
use     ieee.math_real.all; -- For round()
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
library unisim;
use     unisim.vcomponents.all;

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

architecture xilinx of clk_input is

-- Assuming IDELAYCTRL clock is 200 MHz, each step is about 78 ps.
constant DELAY_TAPS_INT : integer :=
    integer(round(DELAY_NSEC / 0.078125));

-- Choose multiplier ratio to put VCO ~1000 MHz (max range 600-1400 MHz).
constant MMCM_RATIO : integer :=
    integer(round(1000.0 / CLKIN_MHZ));

-- Declare intermediate clock signals.
signal clk_dly, clk_mmcm, clk_buf : std_logic;

begin

-- Optional input delay.
gen_dly_en : if (DELAY_TAPS_INT >= 0) generate
    u_dly : IDELAYE2
        generic map (
        IDELAY_TYPE             => "FIXED",
        IDELAY_VALUE            => DELAY_TAPS_INT,
        HIGH_PERFORMANCE_MODE   => "FALSE",
        REFCLK_FREQUENCY        => 200.0)
        port map (
        C           => '0',
        LD          => '0',
        LDPIPEEN    => '0',
        REGRST      => '0',
        CE          => '0',
        INC         => '0',
        CINVCTRL    => '0',
        CNTVALUEIN  => (others => '0'),
        IDATAIN     => clk_pin,
        DATAIN      => '0',
        DATAOUT     => clk_dly,
        CNTVALUEOUT => open);
end generate;

gen_dly_no : if (DELAY_TAPS_INT < 0) generate
    clk_dly <= clk_pin;
end generate;

-- Optional clock-deskew using MMCM.
gen_deskew : if DESKEW_EN generate
    -- Note: Use "BUF_IN" compensation mode, or Vivado will attempt to null
    --       the IDELAYE2 propagation delay, which we don't want.
    u_mmcm : MMCME2_ADV
        generic map (
        CLKFBOUT_MULT_F => real(MMCM_RATIO),
        CLKIN1_PERIOD   => 1000.0 / CLKIN_MHZ,
        COMPENSATION    => "BUF_IN")    -- ZHOLD, BUF_IN, EXTERNAL, INTERNAL
        port map (
        -- Clock feedback:
        RST             => reset_p,
        PWRDWN          => shdn_p,
        CLKINSEL        => '1', -- Select CLKIN1
        CLKIN1          => clk_dly,
        CLKFBOUT        => clk_mmcm,
        CLKFBIN         => clk_buf,
        -- Unused outputs:
        CLKOUT0         => open,
        CLKOUT0B        => open,
        CLKOUT1         => open,
        CLKOUT1B        => open,
        CLKOUT2         => open,
        CLKOUT2B        => open,
        CLKOUT3         => open,
        CLKOUT3B        => open,
        CLKOUT4         => open,
        CLKOUT5         => open,
        CLKOUT6         => open,
        DO              => open,
        DRDY            => open,
        PSDONE          => open,
        CLKFBOUTB       => open,
        CLKFBSTOPPED    => open,
        CLKINSTOPPED    => open,
        LOCKED          => open,
        -- Unused inputs:
        CLKIN2          => '0',
        DCLK            => '0',
        DEN             => '0',
        DWE             => '0',
        DADDR           => (others => '0'),
        DI              => (others => '0'),
        PSCLK           => '0',
        PSEN            => '0',
        PSINCDEC        => '0');
end generate;

gen_direct : if not DESKEW_EN generate
    clk_mmcm <= clk_dly;
end generate;

-- Regional or global clock buffer.
gen_global : if GLOBAL_BUFF generate
    u_bufh : BUFG
        port map(
        I   => clk_mmcm,
        O   => clk_buf);
end generate;

gen_region : if not GLOBAL_BUFF generate
    u_bufh : BUFR
        port map(
        I   => clk_mmcm,
        CE  => '1',
        CLR => '0',
        O   => clk_buf);
end generate;

clk_out <= clk_buf;

end xilinx;



library ieee;
use     ieee.math_real.all; -- For round()
use     ieee.std_logic_1164.all;
library unisim;
use     unisim.vcomponents.all;

entity ddr_input is
    generic (
    DELAY_NSEC  : real := -1.0);    -- Optional delay (<0 to disable)
    port (
    d_pin   : in  std_logic;
    clk     : in  std_logic;
    q_re    : out std_logic;
    q_fe    : out std_logic);
end ddr_input;

architecture xilinx of ddr_input is

-- Assuming IDELAYCTRL clock is 200 MHz, each step is about 78 ps.
constant DELAY_TAPS_INT : integer :=
    integer(round(DELAY_NSEC / 0.078125));

signal d_dly : std_logic;

begin

-- Optional input delay.
gen_dly_en : if (DELAY_TAPS_INT >= 0) generate
    u_dly : IDELAYE2
        generic map (
        IDELAY_TYPE             => "FIXED",
        IDELAY_VALUE            => DELAY_TAPS_INT,
        HIGH_PERFORMANCE_MODE   => "FALSE",
        REFCLK_FREQUENCY        => 200.0)
        port map (
        C           => '0',
        LD          => '0',
        LDPIPEEN    => '0',
        REGRST      => '0',
        CE          => '0',
        INC         => '0',
        CINVCTRL    => '0',
        CNTVALUEIN  => (others => '0'),
        IDATAIN     => d_pin,
        DATAIN      => '0',
        DATAOUT     => d_dly,
        CNTVALUEOUT => open);
end generate;

gen_dly_no : if (DELAY_TAPS_INT < 0) generate
    d_dly <= d_pin;
end generate;

-- Instantiate the DDR input flop.
u_iddr : IDDR
    generic map(
    DDR_CLK_EDGE => "SAME_EDGE_PIPELINED")
    port map(
    Q1  => q_re,    -- 1-bit output for positive edge of clock
    Q2  => q_fe,    -- 1-bit output for negative edge of clock
    C   => clk,     -- 1-bit clock input
    CE  => '1',     -- 1-bit clock enable input
    D   => d_dly,   -- 1-bit DDR data input
    R   => '0',     -- 1-bit reset
    S   => '0');    -- 1-bit set

end xilinx;



library ieee;
use     ieee.std_logic_1164.all;
library unisim;
use     unisim.vcomponents.all;

entity ddr_output is
    port (
    d_re    : in  std_logic;
    d_fe    : in  std_logic;
    clk     : in  std_logic;
    q_pin   : out std_logic);
end ddr_output;

architecture xilinx of ddr_output is begin

u_oddr : ODDR
    generic map(
    DDR_CLK_EDGE => "SAME_EDGE")
    port map (
    Q   => q_pin,   -- 1-bit DDR output
    C   => clk,     -- 1-bit clock input
    CE  => '1',     -- 1-bit clock enable input
    D1  => d_re,    -- 1-bit data input (positive edge)
    D2  => d_fe,    -- 1-bit data input (negative edge)
    R   => '0',     -- 1-bit reset input
    S   => '0');    -- 1-bit set input

end xilinx;
