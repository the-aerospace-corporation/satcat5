--------------------------------------------------------------------------
-- Copyright 2023 The Aerospace Corporation
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
-- Top-level file for the ZCU208 "Clock-Synthesizer" demo
--
-- This design demonstrates the capabilities of the cross-clock counter
-- synchronizer, by synthesizing a synchronized 125 MHz sine wave using
-- the ZCU208's RF Data Converter as a 6.4 GHz DAC.  In theory, this
-- allows jitter and accuracy measurements on picosecond time-scales.
--
-- Control is provided over the USB-UART (UART2).
--
-- The design requires two external reference clocks:
--  * 125 MHz reference for VPLL, routed through MGT (J6, J7)
--  * 400 MHz reference for DAC (J99, J100)
--    (This can be sourced from the CLK104.)
--  * TODO: Is SYSREF input required? If so, what parameters?
--
-- It synthesizes four sine-waves, each nominally 125 MHz:
--  * DAC230 T2.0: 125 MHz locked cosine   (derived from VPLL counter)
--  * DAC230 T2.2: 125 MHz locked sine     (derived from VPLL counter)
--  * DAC231 T3.0: 125 MHz unlocked cosine (free-running)
--  * DAC231 T3.2: 125 MHz unlocked sine   (free-running)
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.round;
library unisim;
use     unisim.vcomponents.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.io_leds.all;
use     work.ptp_types.all;

entity zcu208_clksynth is
    port (
    -- FPGA I/O
    ext_rst_p   : in  std_logic;    -- "CPU_RESET" button
    clk_100_p   : in  std_logic;    -- Built-in 100 MHz
    clk_100_n   : in  std_logic;
    clk_125_p   : in  std_logic;    -- User MGT clock (125 MHz)
    clk_125_n   : in  std_logic;
    status_led  : out std_logic_vector(7 downto 0);
    i2c1_scl    : inout std_logic;  -- CLK104 configuration (I2C1)
    i2c1_sda    : inout std_logic;
    spi_mux     : out std_logic_vector(1 downto 0);
    uart_rx     : in  std_logic;    -- UART2-Tx / FPGA-Rx
    uart_tx     : out std_logic;    -- UART2-Rx / FPGA-Tx
    uart_ctsb   : out std_logic;    -- UART2-CTS
    -- DAC I/O
    refclk_in_p : in  std_logic;    -- Reference clock (400 MHz)
    refclk_in_n : in  std_logic;
    sysref_in_p : in  std_logic;    -- Data alignment
    sysref_in_n : in  std_logic;
    dac_out_p   : out std_logic_vector(3 downto 0);
    dac_out_n   : out std_logic_vector(3 downto 0));
end zcu208_clksynth;

architecture zcu208_clksynth of zcu208_clksynth is

-- VPLL configuration is tuned for the ZCU208.
constant PLL_TAU_MS : real := 50.0;     -- VPLL time-constant (msec)
constant PLL_SC_PHA : natural := 28;    -- VPLL phase precision
constant PLL_SC_TAU : natural := 40;    -- VPLL frequency precision
constant PLL_FILTER : boolean := true;  -- Enable auxiliary filter?

-- Configuration constants.
constant REF_CLK_HZ : integer := 125_000_000;
constant DAC_CLK_HZ : integer := 200_000_000;
constant DAC_MSW1ST : boolean := false; -- Input data order
constant DAC_COUNT  : integer := 16;    -- Samples per clock
constant DAC_WIDTH  : integer := 16;    -- Bits per sample
constant OUT_LOG2N  : integer := 3;     -- Period = 2^N nsec

-- ConfigBus addresses.
constant DEV_RFDAC  : integer := 1;     -- AXI map for Xilinx IP
constant DEV_I2C    : integer := 2;     -- I2C interface to CLK104
constant DEV_OTHER  : integer := 3;     -- Individual registers

constant REG_IDENT  : integer := 0;     -- Read-only identifier
constant REG_SPIMUX : integer := 1;     -- Control CLK104 SPI MUX
constant REG_VPLL   : integer := 2;     -- VPLL offset
constant REG_LED    : integer := 3;     -- Status LED mode
constant REG_RESET  : integer := 4;     -- Software reset
constant REG_VLOCK  : integer := 5;     -- VPLL lock/unlock counter
constant REG_VREF   : integer := 6;     -- VREF fine adjustment
constant REG_VCMP   : integer := 7;     -- VREF phase reporting

-- Buffered clocks and system reset.
signal clk_100_i    : std_logic;
signal clk_100      : std_logic;
signal clk_125_i    : std_logic;
signal clk_125      : std_logic;
signal reset_p      : std_logic;

-- Various options for the status LEDs.
signal status_clk   : std_logic_vector(7 downto 0);
signal status_vpll  : std_logic_vector(7 downto 0);
signal status_time2 : std_logic_vector(7 downto 0);
signal status_time3 : std_logic_vector(7 downto 0);
signal status_vaux  : std_logic_vector(7 downto 0);
signal cfg_ledmux   : cfgbus_word;
signal cfg_reset    : cfgbus_word;

-- Vernier clock and reference counter.
constant VCONFIG : vernier_config := create_vernier_config(REF_CLK_HZ);
signal vclka        : std_logic;
signal vclkb        : std_logic;
signal vreset_p     : std_logic;
signal ref_time     : port_timeref;

-- Phase discipline for the reference counter.
signal cmp_free     : tstamp_t;
signal cmp_vpll     : tstamp_t;
signal cmp_word     : cfgbus_word := (others => '0');

-- Sine synthesis and DAC interfaces.
subtype dac_word_t is signed(DAC_COUNT*DAC_WIDTH-1 downto 0);
signal dreset_p     : std_logic;
signal dac2_clk     : std_logic;    -- Locked stream (Tile 2)
signal dac2_rst_p   : std_logic;
signal dac2_lock    : std_logic;
signal dac2_time    : tstamp_t;
signal dac2_cos     : dac_word_t;
signal dac2_sin     : dac_word_t;
signal dac3_clk     : std_logic;    -- Unlocked stream (Tile 3)
signal dac3_rst_p   : std_logic;
signal dac3_time    : tstamp_t;
signal dac3_cos     : dac_word_t;
signal dac3_sin     : dac_word_t;

-- I2C interface to the CLK104.
signal i2c1_scl_i   : std_logic;
signal i2c1_scl_o   : std_logic;
signal i2c1_sda_i   : std_logic;
signal i2c1_sda_o   : std_logic;
signal cfg_spimux   : cfgbus_word;

-- Count VPLL lock and unlock events.
signal vlock_rise   : std_logic;
signal vlock_fall   : std_logic;
signal vcount_rise  : unsigned(15 downto 0) := (others => '0');
signal vcount_fall  : unsigned(15 downto 0) := (others => '0');
signal vcount_read  : std_logic;
signal cfg_vlock    : cfgbus_word;

-- UART-controlled ConfigBus interface.
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;
signal cfg_acks     : cfgbus_ack_array(0 to 9);

-- KEEP specific signals for Chipscope.
attribute keep : boolean;
attribute keep of clk_100, clk_125, vclka, vclkb : signal is true;
attribute keep of dac2_clk, dac2_time, dac2_cos, dac2_sin : signal is true;
attribute keep of dac3_clk, dac3_time, dac3_cos, dac3_sin : signal is true;

begin

-- Buffered clocks and system reset.
u_clk_100i : ibufds
    generic map(IOSTANDARD => "LVDS")
    port map(
    I       => clk_100_p,
    IB      => clk_100_n,
    O       => clk_100_i);

u_clk_100 : bufg
    port map(
    I       => clk_100_i,
    O       => clk_100);

u_clk_125i : ibufds_gte4
    port map(
    I       => clk_125_p,
    IB      => clk_125_n,
    CEB     => '0',
    O       => open,
    ODIV2   => clk_125_i);

u_clk_125 : bufg_gt
    port map(
    CE      => '1',
    CEMASK  => '0',
    CLR     => '0',
    CLRMASK => '0',
    DIV     => "000",
    I       => clk_125_i,
    O       => clk_125);

u_reset_100 : sync_reset
    port map(
    in_reset_p  => ext_rst_p,
    out_reset_p => reset_p,
    out_clk     => clk_100);

u_reset_dac2 : sync_reset
    port map(
    in_reset_p  => dreset_p,
    out_reset_p => dac2_rst_p,
    out_clk     => dac2_clk);

u_reset_dac3 : sync_reset
    port map(
    in_reset_p  => dreset_p,
    out_reset_p => dac3_rst_p,
    out_clk     => dac3_clk);

-- Status LEDs for various clocks.
u_led_clk100 : breathe_led
    generic map(RATE => breathe_led_rate(100_000_000))
    port map(led => status_clk(0), clk => clk_100);

u_led_clk125 : breathe_led
    generic map(RATE => breathe_led_rate(125_000_000))
    port map(led => status_clk(1), clk => clk_125);

u_led_vclka : breathe_led
    generic map(RATE => breathe_led_rate(VCONFIG.vclka_hz))
    port map(led => status_clk(2), clk => vclka);

u_led_vclkb : breathe_led
    generic map(RATE => breathe_led_rate(VCONFIG.vclkb_hz))
    port map(led => status_clk(3), clk => vclkb);

u_led_dac2clk : breathe_led
    generic map(RATE => breathe_led_rate(DAC_CLK_HZ))
    port map(led => status_clk(4), clk => dac2_clk);

u_led_dac3clk : breathe_led
    generic map(RATE => breathe_led_rate(DAC_CLK_HZ))
    port map(led => status_clk(5), clk => dac3_clk);

status_clk(6) <= reset_p;
status_clk(7) <= vreset_p;

-- Vernier clock synthesizer.
u_vsynth : clkgen_vernier
    generic map(VCONFIG => VCONFIG)
    port map(
    rstin_p     => reset_p,
    refclk      => clk_125,
    vclka       => vclka,
    vclkb       => vclkb,
    vreset_p    => vreset_p);

u_vref : entity work.ptp_counter_gen
    generic map(
    VCONFIG     => VCONFIG,
    DEVADDR     => DEV_OTHER,
    REGADDR     => REG_VREF)
    port map(
    vclka       => vclka,
    vclkb       => vclkb,
    vreset_p    => vreset_p,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(0),
    ref_time    => ref_time);

u_vpll_dac : entity work.ptp_counter_sync
    generic map(
    VCONFIG     => VCONFIG,
    USER_CLK_HZ => DAC_CLK_HZ,
    AUX_FILTER  => PLL_FILTER,
    LOOP_TAU_MS => PLL_TAU_MS,
    PHA_SCALE   => PLL_SC_PHA,
    TAU_SCALE   => PLL_SC_TAU,
    WAIT_LOCKED => false,
    DEVADDR     => DEV_OTHER,
    REGADDR     => REG_VPLL)
    port map(
    ref_time    => ref_time,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(1),
    diagnostics => status_vpll,
    user_clk    => dac2_clk,
    user_ctr    => dac2_time,
    user_lock   => dac2_lock,
    user_rst_p  => dac2_rst_p);

-- Software-controlled PLL disciplines the reference counter to clk_125.
-- (Otherwise it drifts at about 1 picosecond per second.)
u_ref125 : entity work.ptp_counter_free
    generic map(
    REF_CLK_HZ  => real(REF_CLK_HZ))
    port map(
    ref_clk     => clk_125,
    ref_ctr     => cmp_free);

u_vpll_aux : entity work.ptp_counter_sync
    generic map(
    VCONFIG     => VCONFIG,
    USER_CLK_HZ => REF_CLK_HZ,
    AUX_FILTER  => PLL_FILTER,
    LOOP_TAU_MS => PLL_TAU_MS,
    PHA_SCALE   => PLL_SC_PHA,
    TAU_SCALE   => PLL_SC_TAU,
    WAIT_LOCKED => false)
    port map(
    ref_time    => ref_time,
    diagnostics => status_vaux,
    user_clk    => clk_125,
    user_ctr    => cmp_vpll,
    user_lock   => open,
    user_rst_p  => open);

p_cmp : process(clk_125)
begin
    if rising_edge(clk_125) then
        cmp_word <= std_logic_vector(resize(cmp_free - cmp_vpll, 32));
    end if;
end process;

u_drift : cfgbus_readonly_sync
    generic map(
    DEVADDR     => DEV_OTHER,
    REGADDR     => REG_VCMP)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(2),
    sync_clk    => clk_125,
    sync_val    => cmp_word);

-- Count VPLL lock and unlock events in the ConfigBus clock domain.
-- (Reading clears the counters -> Report events since last read.)
u_vlock_rise : sync_toggle2pulse
    generic map(RISING_ONLY => true)
    port map(
    in_toggle   => dac2_lock,
    out_strobe  => vlock_rise,
    out_clk     => cfg_cmd.clk);
u_vlock_fall : sync_toggle2pulse
    generic map(FALLING_ONLY => true)
    port map(
    in_toggle   => dac2_lock,
    out_strobe  => vlock_fall,
    out_clk     => cfg_cmd.clk);

p_vcount : process(cfg_cmd.clk)
    constant COUNT_ZERO : unsigned(15 downto 0) := (others => '0');
begin
    if rising_edge(cfg_cmd.clk) then
        if (cfg_cmd.reset_p = '1' or vcount_read = '1') then
            vcount_rise <= COUNT_ZERO + u2i(vlock_rise);
            vcount_fall <= COUNT_ZERO + u2i(vlock_fall);
        else
            vcount_rise <= vcount_rise + u2i(vlock_rise);
            vcount_fall <= vcount_fall + u2i(vlock_fall);
        end if;
    end if;
end process;

-- Free-running counter for the "fake" unlocked outputs.
p_fake : entity work.ptp_counter_free
    generic map(
    REF_CLK_HZ  => real(DAC_CLK_HZ))
    port map(
    ref_clk     => dac3_clk,
    ref_ctr     => dac3_time);

-- Status LED patterns from each timer.
p_led_time2 : process(dac2_clk)
begin
    if rising_edge(dac2_clk) then
        status_time2 <= std_logic_vector(dac2_time(47 downto 40));
    end if;
end process;

p_led_time3 : process(dac3_clk)
begin
    if rising_edge(dac3_clk) then
        status_time3 <= std_logic_vector(dac3_time(47 downto 40));
    end if;
end process;

-- Sine wave synthesis.
u_sine_dac2 : entity work.ptp_wavesynth
    generic map(
    LOG_NSEC    => OUT_LOG2N,
    DAC_WIDTH   => DAC_WIDTH,
    PAR_CLK_HZ  => DAC_CLK_HZ,
    PAR_COUNT   => DAC_COUNT,
    MSW_FIRST   => DAC_MSW1ST)
    port map(
    par_clk     => dac2_clk,
    par_tstamp  => dac2_time,
    par_out_cos => dac2_cos,
    par_out_sin => dac2_sin);

u_sine_dac3 : entity work.ptp_wavesynth
    generic map(
    LOG_NSEC    => OUT_LOG2N,
    DAC_WIDTH   => DAC_WIDTH,
    PAR_CLK_HZ  => DAC_CLK_HZ,
    PAR_COUNT   => DAC_COUNT,
    MSW_FIRST   => DAC_MSW1ST)
    port map(
    par_clk     => dac3_clk,
    par_tstamp  => dac3_time,
    par_out_cos => dac3_cos,
    par_out_sin => dac3_sin);

-- DAC interface.
u_rfdac : entity work.rfdac_wrapper
    generic map(DEVADDR => DEV_RFDAC)
    port map(
    refclk_in_p => refclk_in_p,
    refclk_in_n => refclk_in_n,
    sysref_in_p => sysref_in_p,
    sysref_in_n => sysref_in_n,
    dac_out_p   => dac_out_p,
    dac_out_n   => dac_out_n,
    tile2_clk   => dac2_clk,
    tile2_strm0 => dac2_cos,
    tile2_strm1 => dac2_sin,
    tile3_clk   => dac3_clk,
    tile3_strm2 => dac3_cos,
    tile3_strm3 => dac3_sin,
    clk_100     => clk_100,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(3));

-- I2C interface for configuring the CLK104 daughtercard.
u_i2c1_ctrl : entity work.cfgbus_i2c_controller
    generic map(DEVADDR => DEV_I2C)
    port map(
    sclk_o      => i2c1_scl_o,
    sclk_i      => i2c1_scl_i,
    sdata_o     => i2c1_sda_o,
    sdata_i     => i2c1_sda_i,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(4));

u_i2c1_scl : bidir_io
    generic map(EN_PULLUP => true)
    port map(
    io_pin  => i2c1_scl,
    d_in    => i2c1_scl_i,
    d_out   => i2c1_scl_o,
    t_en    => i2c1_scl_o);

u_i2c1_sda : bidir_io
    generic map(EN_PULLUP => true)
    port map(
    io_pin  => i2c1_sda,
    d_in    => i2c1_sda_i,
    d_out   => i2c1_sda_o,
    t_en    => i2c1_sda_o);

-- Discrete signals to control SPI MUX on the CLK104.
-- (Dear Xilinx: Why is this not controlled by the chip select signals?)
u_clk104_mux : cfgbus_register
    generic map(
    DEVADDR     => DEV_OTHER,
    REGADDR     => REG_SPIMUX,
    WR_ATOMIC   => true,
    WR_MASK     => x"00000003")
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(5),
    reg_val     => cfg_spimux);

spi_mux <= cfg_spimux(1 downto 0);

-- Read only register acting as a board identifier.
u_ident : cfgbus_readonly
    generic map(
    DEVADDR => DEV_OTHER,
    REGADDR => REG_IDENT)
    port map(
    reg_val => x"5A323038", -- "Z208"
    cfg_cmd => cfg_cmd,
    cfg_ack => cfg_acks(6));

-- Select the LED mode.
u_led_mode : cfgbus_register
    generic map(
    DEVADDR     => DEV_OTHER,
    REGADDR     => REG_LED,
    WR_ATOMIC   => true,
    WR_MASK     => x"0000000F")
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(7),
    reg_val     => cfg_ledmux);

status_led <= status_clk when u2i(cfg_ledmux) = 0
        else status_vpll when u2i(cfg_ledmux) = 1
        else status_time2 when u2i(cfg_ledmux) = 2
        else status_time3 when u2i(cfg_ledmux) = 3
        else status_vaux when u2i(cfg_ledmux) = 4
        else (others => '0');

-- CPU-controlled reset flags.
u_reset_reg : cfgbus_register
    generic map(
    DEVADDR     => DEV_OTHER,
    REGADDR     => REG_RESET,
    WR_ATOMIC   => true,
    WR_MASK     => x"00000001")
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(8),
    reg_val     => cfg_reset);

dreset_p <= vreset_p or cfg_reset(0);

-- ConfigBus register for reporting VPLL lock and unlock events.
u_vlock_reg : cfgbus_readonly
    generic map(
    DEVADDR => DEV_OTHER,
    REGADDR => REG_VLOCK)
    port map(
    evt_rd_str => vcount_read,
    reg_val => cfg_vlock,
    cfg_cmd => cfg_cmd,
    cfg_ack => cfg_acks(9));

cfg_vlock <= std_logic_vector(vcount_rise & vcount_fall);

-- UART-controlled ConfigBus interface.
cfg_ack <= cfgbus_merge(cfg_acks);

u_cfgbus : entity work.cfgbus_host_uart
    generic map(
    CFG_ETYPE   => x"5C01",
    CFG_MACADDR => x"5A5ADEADBEEF",
    CLKREF_HZ   => 100_000_000,
    UART_BAUD   => 921_600,
    UART_REPLY  => true,
    CHECK_FCS   => true)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    uart_rxd    => uart_rx,
    uart_txd    => uart_tx,
    sys_clk     => clk_100,
    reset_p     => reset_p);

uart_ctsb <= '0';

end zcu208_clksynth;
