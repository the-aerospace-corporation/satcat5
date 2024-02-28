--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- I/O structures for Microsemi PolarFire FPGAs.
--
-- For cross-platform support, other blocks in this design use generic
-- wrappers for vendor-specific I/O structures.  This file contains
-- implementations of these structures for Microsemi PolarFire FPGAs.
--
-- NOTE: Designs should only include ONE such implementation!  If your
-- project includes "xilinx/7series_io.vhd", don't also include similar
-- files from the "lattice" or "microsemi" folder.
--

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_primitives.all;

entity bidir_io is
    generic (
    EN_PULLDN   : boolean := false;     -- Include a weak pulldown?
    EN_PULLUP   : boolean := false);    -- Include a weak pullup?
    port (
    io_pin  : inout std_logic;          -- The external pin
    d_in    : out   std_logic;          -- Input to FPGA, if T = 1
    d_out   : in    std_logic;          -- Output from FPGA, if T = 0
    t_en    : in    std_logic);         -- Tristate enable (1 = Input/Hi-Z, 0 = Output)
end bidir_io;

architecture polarfire of bidir_io is

    signal out_en : std_logic;

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
    assert false report "not implemented" severity error;
end generate;

gen_pu : if EN_PULLUP generate
    assert false report "not implemented" severity error;
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
use     work.common_primitives.all;

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

    -- Constant delay taps value - not used in microsemi design
    constant DELAY_TAPS_INT : integer := integer(round(DELAY_NSEC / 0.078125));

    -- Declare intermediate clock signals
    signal clk_dly, clk_mmcm, clk_buf : std_logic;

    component GCLKINT
    port (
        A   : in  std_logic;
        EN  : in  std_logic;
        Y   : out std_logic);
    end component;


    component RGCLKINT
    port (
        A   : in  std_logic;
        EN  : in  std_logic;
        Y   : out std_logic);
    end component;

begin

-- DELAY GEN
gen_dly_en : if (DELAY_TAPS_INT >= 0) generate
    assert false report "not implemented" severity error;
end generate;

gen_dly_no : if (DELAY_TAPS_INT < 0) generate
    clk_dly <= clk_pin;
end generate;

-- DESKEW GEN
gen_deskew : if DESKEW_EN generate
    assert false report "not implemented" severity error;
end generate;

gen_direct : if not DESKEW_EN generate
    clk_mmcm <= clk_dly;
end generate;

-- Regional or global clock buffer.
gen_global : if GLOBAL_BUFF generate
    u_bufh : GCLKINT
        port map(
            A  => clk_mmcm,
            EN => '1',
            Y => clk_buf
        );
end generate;

gen_region : if not GLOBAL_BUFF generate
    u_bufh : RGCLKINT
        port map(
            A   => clk_mmcm,
            EN  => '1',
            Y   => clk_buf
        );
end generate;

clk_out <= clk_buf;

end polarfire;

--------------------------------------------------------------------------

library ieee;
use     ieee.math_real.all; -- For round()
use     ieee.std_logic_1164.all;
use     work.common_primitives.all;

-- LIMITATION: This includes all pin hardware including output pad.
--  Cannot independently select other pad options
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

-- 25 ps per tap
constant DELAY_TAPS_INT : integer :=
    integer(round(DELAY_NSEC / 0.025));

component IDDR_IOD
port (
    PADI    : in  std_logic;
    RX_CLK  : in  std_logic;
    QF      : out std_logic;
    QR      : out std_logic);
end component;

begin

-- TODO delay. IOD has RX_DELAY_VAL, but not exposed to wrappers. Only settable in constraints?
gen_dly_en : if (DELAY_TAPS_INT >= 0) generate
    assert false report "not implemented" severity error;
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
use     work.common_primitives.all;

-- LIMITATION: This includes all pin hardware including output pad.
--  Cannot independently select other pad options (such as bidir pad needed in port_serial_auto)
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