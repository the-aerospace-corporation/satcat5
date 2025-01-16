--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- I/O structures for Microsemi PolarFire FPGAs.
--
-- For cross-platform support, other blocks in this design use generic
-- wrappers for vendor-specific I/O structures.  This file contains
-- implementations of these structures for Microsemi PolarFire FPGAs.
--
-- Execute project/libero/gen_ip.tcl to generate necessary IP.
--
-- NOTE: Designs should only include ONE such implementation!  If your
-- project includes "xilinx/7series_io.vhd", don't also include similar
-- files from the "lattice" or "microsemi" folder.
--

library ieee;
use     ieee.std_logic_1164.all;

-- LIMITATION: PolarFire does not have pull-up/down macros, so custom
-- attributes "satcat5_res_pull_dn" and "satcat5_res_pull_up" are provided. The
-- programmable pull-up/down resistors are controlled using the I/O attribute
-- editor, or with a PDC command. See section 7.1.2 of the "PolarFire FPGA and
-- PolarFire SoC FPGA User I/O User Guide" document.
entity bidir_io is
    generic (
    EN_PULLDN   : boolean := false;  -- Include a weak pulldown?
    EN_PULLUP   : boolean := false); -- Include a weak pullup?
    port (
    io_pin  : inout std_logic;       -- The external pin
    d_in    : out   std_logic;       -- Input to FPGA, if T = 1
    d_out   : in    std_logic;       -- Output from FPGA, if T = 0
    t_en    : in    std_logic);      -- Tristate (1 = Input/Hi-Z, 0 = Output)
end bidir_io;

architecture polarfire of bidir_io is

    signal out_en : std_logic;

    -- Custom attribute makes it easy to "set_io" with pull-up/down resistors.
    attribute satcat5_res_pull_dn : boolean;
    attribute satcat5_res_pull_dn of io_pin : signal is EN_PULLDN;
    attribute satcat5_res_pull_up : boolean;
    attribute satcat5_res_pull_up of io_pin : signal is EN_PULLUP;

    component BIBUF
    port(
        D       : in std_logic;
        E       : in std_logic;
        Y       : out std_logic;
        PAD     : inout std_logic);
    end component;

begin

out_en <= not t_en;

gen_pd : if EN_PULLDN generate
    assert false report "Set pull-down manually with 'set_io' and the " &
        "'satcat5_res_pull_dn' attribute or in the I/O attribute editor"
    severity warning;
end generate;

gen_pu : if EN_PULLUP generate
    assert false report "Set pull-up manually with 'set_io' and the " &
    "'satcat5_res_pull_up' attribute or in the I/O attribute editor"
    severity warning;
end generate;

u_iobuf : BIBUF
port map (
    D => d_out,
    E => out_en,
    Y => d_in,
    PAD => io_pin);

end polarfire;

--------------------------------------------------------------------------

library ieee;
use     ieee.math_real.all; -- For round()
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;

-- LIMITATION: PolarFire PLL has a programmable delay line with a de-skew mode,
-- but "The CCC configurator must be instantiated into the design to use PLL",
-- and "Multiple CCC configurators must be instantiated to use multiple PLLs".
-- This is done from the Clock Contditioning Circuitry option in the catalog
-- tab. See the "PolarFire Family Clocking Resources" document.
entity clk_input is
    generic (
    CLKIN_MHZ   : real;             -- Input clock frequency
    GLOBAL_BUFF : boolean := false; -- Global or local output buffer
    DESKEW_EN   : boolean := false; -- Clock synth for deskew?
    DELAY_NSEC  : real    := -1.0); -- Optional delay (<0 to disable)
    port (
    reset_p : in  std_logic;        -- Reset (hold 1 msec after shdn_p if used)
    shdn_p  : in  std_logic := '0'; -- Shutdown (optional, DESKEW_EN only)
    clk_pin : in  std_logic;        -- External clock input
    clk_out : out std_logic);       -- Buffered clock output
end clk_input;

architecture polarfire of clk_input is

    constant DELAY_TAPS_INT : integer := integer(round(DELAY_NSEC / 0.025));

    -- Declare intermediate clock signals
    signal clk_dly, clk_mmcm, clk_buf : std_logic;

    component CLKINT
    port (
        A   : in  std_logic;
        Y   : out std_logic);
    end component;


    component RCLKINT
    port (
        A   : in  std_logic;
        Y   : out std_logic);
    end component;

begin

-- DELAY GEN
gen_dly_en : if (DELAY_TAPS_INT >= 0) generate
    assert false report "cannot be implemented; set manually with the CCC " &
    "configurator"
    severity error;
end generate;

gen_dly_no : if (DELAY_TAPS_INT < 0) generate
    clk_dly <= clk_pin;
end generate;

-- DESKEW GEN
gen_deskew : if DESKEW_EN generate
    assert false report "cannot be implemented; set manually with the CCC " &
    "configurator"
    severity error;
end generate;

gen_direct : if not DESKEW_EN generate
    clk_mmcm <= clk_dly;
end generate;

-- Regional or global clock buffer.
gen_global : if GLOBAL_BUFF generate
    u_bufh : CLKINT
        port map(
            A  => clk_mmcm,
            Y => clk_buf
        );
end generate;

gen_region : if not GLOBAL_BUFF generate
    u_bufh : RCLKINT
        port map(
            A   => clk_mmcm,
            Y   => clk_buf
        );
end generate;

clk_out <= clk_buf;

end polarfire;

--------------------------------------------------------------------------

library ieee;
use     ieee.math_real.all; -- For round()
use     ieee.std_logic_1164.all;

-- LIMITATION: This includes all pin hardware including output pad. Cannot
-- independently select other pad options. Delay is controlled using the I/O
-- attribute editor, or with a PDC command, so custom attribute
-- "satcat5_in_delay" is provided. See section 8.2.1 of the "PolarFire FPGA and
-- PolarFire SoC FPGA User I/O User Guide" document.
entity ddr_input is
    generic (
    DELAY_NSEC  : real := -1.0);    -- Optional delay (<0 to disable)
    port (
    d_pin   : in  std_logic;
    clk     : in  std_logic;
    q_re    : out std_logic;
    q_fe    : out std_logic);
end ddr_input;

architecture polarfire of ddr_input is

--25 ps per tap
constant DELAY_TAPS : integer := integer(round(DELAY_NSEC / 0.025));

component IDDR_IOD
port (
    PADI    : in  std_logic;
    RX_CLK  : in  std_logic;
    QF      : out std_logic;
    QR      : out std_logic);
end component;

-- Custom attribute makes it easy to "set_io" with input delay.
attribute satcat5_in_delay : integer;
attribute satcat5_in_delay of d_pin : signal is DELAY_TAPS;

begin

gen_dly_en : if (DELAY_TAPS >= 0) generate
    assert false report "Set delay manually with 'set_io' and the " &
    "'satcat5_in_delay' attribute or in the I/O attribute editor"
    severity warning;
end generate;

-- Microsemi UG0686 seems to suggest that QR is from the rising edge before QF
-- This matches Xilinx SAME_EDGE_PIPELINED mode
u_iddr : IDDR_IOD
    port map(
    PADI    => d_pin,
    RX_CLK  => clk,
    QF      => q_fe,
    QR      => q_re);

end polarfire;

--------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

-- LIMITATION: This includes all pin hardware including output pad. Cannot
-- independently select other pad options. Delay is controlled using the I/O
-- attribute editor, or with a PDC command. See section 8.2.1 of the "PolarFire
-- FPGA and PolarFire SoC FPGA User I/O User Guide" document.
entity ddr_output is
    port (
    d_re    : in  std_logic;
    d_fe    : in  std_logic;
    clk     : in  std_logic;
    q_pin   : out std_logic);
end ddr_output;

architecture polarfire of ddr_output is

component ODDR_IOD
port (
    DF      : in  std_logic;
    DR      : in  std_logic;
    TX_CLK  : in std_logic;
    PADO    : out std_logic);
end component;

begin

-- Microsemi IOD is equivalent to Xilinx SAME_EDGE mode
u_oddr : ODDR_IOD
    port map (
    DF     => d_fe,
    DR     => d_re,
    TX_CLK => clk,
    PADO   => q_pin);

end polarfire;
