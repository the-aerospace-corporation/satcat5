--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Shared definitions for platform-specific primitives
--
-- This file contains the package definition for "common_primitives", a
-- collection of generic low-level primitives that must be implemented
-- differently on each supported FPGA family / platform.
--
-- The definitions here are common to all platforms, but implementations
-- are platform-specific.  Designs should only include ONE such platform!
-- i.e., If your project includes "xilinx/7series_sync.vhd" it should not
-- include "lattice/ice40_sync.vhd".
--
-- The definitions are designed to be generic enough to be supported
-- on all platforms.  Where necessary, they deliver the lowest common
-- denominator of available features by default; advanced features are
-- enabled by build-time generics, but should be used sparingly for
-- improved compatibility.
--
-- A single package is divided into three main sections:
--  * I/O primitives
--      General-purpose external I/O primitives including bidirectional
--      buffers, clock input buffers, and differential signal buffers.
--  * Memory primitives
--      Dual-port and three-port RAM primitives.  May implement automatic
--      selection of different primitives depending on size parameters.
--  * Synchronization primitives
--      Primitives for handling asynchronous signals and clock-crossing.
--      Special handling is required to avoid metastability faults.
--  * Vernier clock generation
--      Primitives for configuring and generating closely-spaced "Vernier"
--      clocks, suitable for use with the "ptp_counter_gen" block.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;

package common_primitives is
    ---------------------------------------------------------------------
    -- I/O Primitives
    ---------------------------------------------------------------------

    -- Bidirectional I/O driver with tri-state.
    -- All inputs and outputs are asynchronous.
    component bidir_io is
        generic (
        EN_PULLDN : boolean := false;   -- Include a weak pulldown?
        EN_PULLUP : boolean := false);  -- Include a weak pullup?
        port (
        io_pin  : inout std_logic;      -- The external pin
        d_in    : out   std_logic;      -- Input to FPGA, if T = 1
        d_out   : in    std_logic;      -- Output from FPGA, if T = 0
        t_en    : in    std_logic);     -- Tristate enable (1 = Input/Hi-Z)
    end component;

    -- General-purpose clock input buffer.
    -- Optionally includes deskew and delay, if platform supports it.
    component clk_input is
        generic (
        CLKIN_MHZ   : real;             -- Input clock frequency
        GLOBAL_BUFF : boolean := false; -- Global or local output buffer?
        DESKEW_EN   : boolean := false; -- Clock synth for deskew?
        DELAY_NSEC  : real := -1.0);    -- Optional delay (<0 to disable)
        port (
        reset_p : in  std_logic;        -- Reset (hold 1 msec after shdn_p if used)
        shdn_p  : in  std_logic := '0'; -- Shutdown (optional, DESKEW_EN only)
        clk_pin : in  std_logic;        -- External clock input
        clk_out : out std_logic);       -- Buffered clock output
    end component;

    -- Double-data-rate (DDR) input buffer.
    -- Optionally includes fixed delay, if platform supports it.
    component ddr_input is
        generic (
        DELAY_NSEC  : real := -1.0);    -- Optional delay (<0 to disable)
        port (
        d_pin   : in  std_logic;
        clk     : in  std_logic;
        q_re    : out std_logic;
        q_fe    : out std_logic);
    end component;

    -- Double-data-rate (DDR) output driver.
    component ddr_output is
        port (
        d_re    : in  std_logic;
        d_fe    : in  std_logic;
        clk     : in  std_logic;
        q_pin   : out std_logic);
    end component;

    ---------------------------------------------------------------------
    -- Memory primitives
    ---------------------------------------------------------------------

    -- Parameterizable dual-port or tri-port RAM block.
    --
    -- All ports are synchronous to their respective clocks; read-data is always
    -- available exactly one cycle after read-address.
    --
    -- The "write" port has its own clock, address, and write-enable strobe.
    -- It also has an optional readback port (wr_rval). If enabled, this port
    -- reads the value at the write-address.  Behavior of this readback port
    -- is undefined on the cycle after write-enable is asserted.  (i.e., It
    -- may read the previous value or the new value.)
    --
    -- The "read" port has its own clock, address, and optional read-enable.
    -- It is strictly read-only.  Some platforms follow the read-enable
    -- strictly; others apply it only during formal verification mode.
    --
    -- Parameters:
    --  AWIDTH  = Address width (2^M words)
    --  DWIDTH  = Data width (each word = N bits)
    --  SIMTEST = Formal verification mode? (Simulation only)
    --            Forces WR_RVAL and RD_VAL to "XXXX" during undefined states.
    --  TRIPORT = Enable the WR_RVAL port. (Otherwise constant zero.)
    --            On some platforms, this feature requires a second BRAM block.
    component dpram is
        generic (
        AWIDTH  : positive;             -- Address width (bits)
        DWIDTH  : positive;             -- Data width (bits)
        SIMTEST : boolean := false;     -- Formal verification mode?
        TRIPORT : boolean := false);    -- Enable "wr_rval" port?
        port (
        wr_clk  : in  std_logic;
        wr_addr : in  unsigned(AWIDTH-1 downto 0);
        wr_en   : in  std_logic;
        wr_val  : in  std_logic_vector(DWIDTH-1 downto 0);
        wr_rval : out std_logic_vector(DWIDTH-1 downto 0);
        rd_clk  : in  std_logic;
        rd_addr : in  unsigned(AWIDTH-1 downto 0);
        rd_en   : in  std_logic := '1';
        rd_val  : out std_logic_vector(DWIDTH-1 downto 0));
    end component;

    -- Platform-specific preferred width for small memories, such as those
    -- used in TCAM, small FIFOs, etc., where block-size is flexible.
    -- Each platform defines this deferred constant in a separate package body.
    constant PREFER_DPRAM_AWIDTH : positive;

    ---------------------------------------------------------------------
    -- Synchronization primitives
    ---------------------------------------------------------------------

    -- The sync_toggle2pulse block generates an output strobe every time the
    -- asynchronous input toggles.  By default, it detects both low-to-high
    -- and high-to-low transitions.
    --  RISING_ONLY:    If true, detect only low-to-high transitions.
    --  FALLING_ONLY:   If true, detect only high-to-low transitions.
    --  OUT_BUFFER:     If true, buffer output.  This increases delay by
    --                  one clock cycle but may prevent output glitches.
    component sync_toggle2pulse is
        generic(
        RISING_ONLY  : boolean := false;
        FALLING_ONLY : boolean := false;
        OUT_BUFFER   : boolean := false);
        port(
        in_toggle   : in  std_logic;
        out_strobe  : out std_logic;
        out_clk     : in  std_logic;
        reset_p     : in  std_logic := '0');
    end component;

    -- Vector variant of "sync_toggle2pulse".
    component sync_toggle2pulse_slv is
        generic(
        IO_WIDTH     : positive;
        RISING_ONLY  : boolean := false;
        FALLING_ONLY : boolean := false;
        OUT_BUFFER   : boolean := false);
        port(
        in_toggle   : in  std_logic_vector(IO_WIDTH-1 downto 0);
        out_strobe  : out std_logic_vector(IO_WIDTH-1 downto 0);
        out_clk     : in  std_logic;
        reset_p     : in  std_logic := '0');
    end component;

    -- The sync_buffer is the classic two-register asynchronous buffer.  It
    -- will accurately represent slow-varying signals but is not guaranteed
    -- to capture short pulses, etc.
    component sync_buffer is
        port(
        in_flag     : in  std_logic;
        out_flag    : out std_logic;
        out_clk     : in  std_logic;
        reset_p     : in  std_logic := '0');
    end component;

    -- Vector variant of "sync_buffer".
    component sync_buffer_slv is
        generic(
        IO_WIDTH    : positive);
        port(
        in_flag     : in  std_logic_vector(IO_WIDTH-1 downto 0);
        out_flag    : out std_logic_vector(IO_WIDTH-1 downto 0);
        out_clk     : in  std_logic;
        reset_p     : in  std_logic := '0');
    end component;

    -- The sync_pulse2pulse block generates an output strobe for every input
    -- strobe.  Note that it requires an input clock as well as an output clock.
    -- As with sync_toggle2pulse, set OUT_BUFFER = true for glitch-free
    -- operation.  Not recommended if input strobes arrive close together.
    component sync_pulse2pulse is
        port(
        in_strobe   : in  std_logic;
        in_clk      : in  std_logic;
        out_strobe  : out std_logic;
        out_clk     : in  std_logic;
        reset_p     : in  std_logic := '0');
    end component;

    -- Reset buffer with asynchronous set, synchronous clear.
    -- Resets are held for at least the designated number of output clocks.
    -- Ensures that reset is propagated even without an output clock.
    component sync_reset is
        generic(
        HOLD_MIN    : integer := 7;
        KEEP_ATTR   : string := "true");
        port(
        in_reset_p  : in  std_logic;
        out_reset_p : out std_logic;
        out_clk     : in  std_logic := '0');
    end component;

    ---------------------------------------------------------------------
    -- Vernier clocks
    ---------------------------------------------------------------------

    -- Array of build-time clock-generator parameters.
    -- Interpretation is entirely reserved for platform implementation.
    -- Array size may increase in future versions, but will never decrease.
    type vernier_params is array(0 to 8) of real;

    -- Structure containing Vernier parameters for a given configuration.
    -- Users should access "input_hz", "vclka_hz", and "vclkb_hz" only.
    type vernier_config is record
        input_hz    : natural;          -- Original reference frequency
        vclka_hz    : real;             -- Frequency of the slow output (0 = invalid)
        vclkb_hz    : real;             -- Frequency of the fast output (0 = invalid)
        sync_tau_ms : real;             -- Synchronization-filter time constant
        sync_aux_en : boolean;          -- Synchronization enable auxiliary filter?
        params      : vernier_params;   -- Reserved parameters (varies by platform)
    end record;

    constant VERNIER_DEFAULT_TAU_MS : real := 50.0;
    constant VERNIER_DEFAULT_AUX_EN : boolean := true;

    -- Use this configuration to indicate PTP is disabled.
    constant VERNIER_DISABLED : vernier_config :=
        (0, 0.0, 0.0, 0.0, false, (others => 0.0));

    -- Given reference frequency, determine the "best" Vernier configuration.
    -- (An unsupported or zero input frequency returns "VERNIER_DISABLED".)
    function create_vernier_config(
        input_hz    : natural;
        sync_tau_ms : real := VERNIER_DEFAULT_TAU_MS;
        sync_aux_en : boolean := VERNIER_DEFAULT_AUX_EN)
        return vernier_config;

    -- Standardized clock generator for a Vernier clock-pair.
    component clkgen_vernier is
        generic (VCONFIG : vernier_config);
        port (
        rstin_p     : in  std_logic;        -- Active high reset
        refclk      : in  std_logic;        -- Input clock
        vclka       : out std_logic;        -- Slow output clock
        vclkb       : out std_logic;        -- Fast output clock
        vreset_p    : out std_logic);       -- Output reset
    end component;

    ---------------------------------------------------------------------
    -- Other primitives
    ---------------------------------------------------------------------

    -- The "scrubber" block scans for radiation-induced errors (e.g., SEU)
    -- and may attempt to correct them.  The platform-specific implementation
    -- typically wraps IP provided by the FPGA vendor for this purpose.  That
    -- wrapper should assert the error strobe whenever an error is detected.
    --
    -- Some platforms require that the input clock must be a "raw" clock
    -- with no intervening clock-gating or clock-synthesis logic.
    --
    -- For an example, refer to "src/xilinx/scrub_xilinx.vhd".
    component scrub_generic is
        port (
        clk_raw : in  std_logic;        -- System clock (always-on)
        err_out : out std_logic);       -- Strobe on scrub error
    end component;

end common_primitives;

---------------------------------------------------------------------
-- Entity Definition: sync_toggle2pulse_slv

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_primitives.sync_toggle2pulse;

entity sync_toggle2pulse_slv is
    generic(
    IO_WIDTH     : positive;
    RISING_ONLY  : boolean := false;
    FALLING_ONLY : boolean := false;
    OUT_BUFFER   : boolean := false);
    port(
    in_toggle   : in  std_logic_vector(IO_WIDTH-1 downto 0);
    out_strobe  : out std_logic_vector(IO_WIDTH-1 downto 0);
    out_clk     : in  std_logic;
    reset_p     : in  std_logic := '0');
end sync_toggle2pulse_slv;

architecture rtl of sync_toggle2pulse_slv is

begin

gen_sync : for n in in_toggle'range generate
    u_sync : sync_toggle2pulse
        generic map(
        RISING_ONLY  => RISING_ONLY,
        FALLING_ONLY => FALLING_ONLY,
        OUT_BUFFER   => OUT_BUFFER)
        port map(
        in_toggle   => in_toggle(n),
        out_strobe  => out_strobe(n),
        out_clk     => out_clk,
        reset_p     => reset_p);
end generate;

end rtl;

---------------------------------------------------------------------
-- Entity Definition: sync_buffer_slv

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_primitives.sync_buffer;

entity sync_buffer_slv is
    generic(
    IO_WIDTH    : positive);
    port(
    in_flag     : in  std_logic_vector(IO_WIDTH-1 downto 0);
    out_flag    : out std_logic_vector(IO_WIDTH-1 downto 0);
    out_clk     : in  std_logic;
    reset_p     : in  std_logic := '0');
end sync_buffer_slv;

architecture rtl of sync_buffer_slv is

begin

gen_sync : for n in in_flag'range generate
    u_sync : sync_buffer
        port map(
        in_flag     => in_flag(n),
        out_flag    => out_flag(n),
        out_clk     => out_clk,
        reset_p     => reset_p);
end generate;

end rtl;
