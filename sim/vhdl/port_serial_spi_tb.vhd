--------------------------------------------------------------------------
-- Copyright 2019-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for Ethernet-over-Serial SPI port
--
-- This is a self-checking unit test for the Ethernet-over-Serial SPI port.
-- It connects a the clock-in and clock-out variants back-to-back to confirm
-- correct operation.
--
-- The complete test takes about 81 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.switch_types.all;

entity port_serial_spi_tb_helper is
    generic(
    SPI_MODE    : integer;
    SPI_BAUD    : integer := 10_000_000;
    REFCLK_HZ   : integer := 125_000_000);
    port(
    refclk      : in  std_logic;
    reset_p     : in  std_logic;
    rxdone      : out std_logic);
end port_serial_spi_tb_helper;

architecture helper of port_serial_spi_tb_helper is

-- SPI Mode (Bit 1 = CPOL)
constant SPI_CPHA   : std_logic := bool2bit(SPI_MODE = 1 or SPI_MODE = 3);
constant SPI_CPOL   : std_logic := bool2bit(SPI_MODE >= 2);

-- Number of packets before declaring "done".
constant RX_PACKETS : integer := 100;

-- Flow control for the clock-source block.
signal ext_pause    : std_logic := '1';

-- Streaming source and sink for each link:
signal txdata_a, txdata_b   : port_tx_s2m;
signal txctrl_a, txctrl_b   : port_tx_m2s;
signal rxdata_a, rxdata_b   : port_rx_m2s;
signal rxdone_a, rxdone_b   : std_logic;

-- Two units under test, connected back-to-back.
signal spi_csb,  spi_sclk   : std_logic := '1';
signal spi_sdia, spi_sdib   : std_logic;
signal spi_sdoa, spi_sdob   : std_logic;
signal spi_tria, spi_trib   : std_logic;

begin

-- Pause the clock source at psuedorandom intervals.
p_flow : process
    variable seed1  : positive := 1234;
    variable seed2  : positive := 5678;
    variable rand   : real := 0.0;
    variable ctr    : integer := 0;
begin
    -- Brief idle period.
    ext_pause <= '1';
    wait for 10 us;

    -- Allow traffic for up to N chunks.
    uniform(seed1, seed2, rand);
    ctr := 1 + integer(floor(10.0 * rand));

    ext_pause <= '0';
    while (ctr > 0) loop
        wait until falling_edge(spi_csb);
        ctr := ctr - 1;
    end loop;
end process;

-- Streaming source and sink for each link:
u_src_a2b : entity work.port_test_common
    generic map(
    DSEED1  => 1234,
    DSEED2  => 5678)
    port map(
    txdata  => txdata_a,
    txctrl  => txctrl_a,
    rxdata  => rxdata_b,
    rxdone  => rxdone_b,
    rxcount => RX_PACKETS);

u_src_b2a : entity work.port_test_common
    generic map(
    DSEED1  => 67890,
    DSEED2  => 12345)
    port map(
    txdata  => txdata_b,
    txctrl  => txctrl_b,
    rxdata  => rxdata_a,
    rxdone  => rxdone_a,
    rxcount => RX_PACKETS);

-- Two units under test, connected back-to-back.
uut_a : entity work.port_serial_spi_controller
    generic map(
    CLKREF_HZ   => REFCLK_HZ,
    SPI_BAUD    => SPI_BAUD,
    SPI_MODE    => SPI_MODE)
    port map(
    spi_csb     => spi_csb,
    spi_sclk    => spi_sclk,
    spi_sdi     => spi_sdia,
    spi_sdo     => spi_sdoa,
    rx_data     => rxdata_a,
    tx_data     => txdata_a,
    tx_ctrl     => txctrl_a,
    ext_pause   => ext_pause,
    refclk      => refclk,
    reset_p     => reset_p);

spi_tria <= '0';    -- Not used

uut_b : entity work.port_serial_spi_peripheral
    generic map(
    CLKREF_HZ   => REFCLK_HZ,
    SPI_MODE    => SPI_MODE)
    port map(
    spi_csb     => spi_csb,
    spi_sclk    => spi_sclk,
    spi_sdi     => spi_sdib,
    spi_sdo     => spi_sdob,
    spi_sdt     => spi_trib,
    rx_data     => rxdata_b,
    tx_data     => txdata_b,
    tx_ctrl     => txctrl_b,
    refclk      => refclk,
    reset_p     => reset_p);

-- Emulate external tri-state gates.
spi_sdia <= spi_sdob and not spi_trib;
spi_sdib <= spi_sdoa and not spi_tria;

-- Print "done" message when both links have received N packets.
rxdone <= rxdone_a and rxdone_b;

p_done : process
begin
    wait until (rxdone_a = '1' and rxdone_b = '1');
    report "Test completed, SPI-mode " & integer'image(SPI_MODE);
    wait;
end process;

end helper;




library ieee;
use     ieee.std_logic_1164.all;

entity port_serial_spi_tb is
    -- Unit testbench top level, no I/O ports
end port_serial_spi_tb;

architecture tb of port_serial_spi_tb is

-- Clock and reset generation.
signal clk_125      : std_logic := '0';
signal reset_p      : std_logic := '1';

begin

-- Clock and reset generation.
clk_125 <= not clk_125 after 4 ns;
reset_p <= '0' after 1 us;

-- Instantiate one test unit for each SPI mode.
uut0 : entity work.port_serial_spi_tb_helper
    generic map(SPI_MODE => 0)
    port map(
    refclk      => clk_125,
    reset_p     => reset_p,
    rxdone      => open);

uut1 : entity work.port_serial_spi_tb_helper
    generic map(SPI_MODE => 1)
    port map(
    refclk      => clk_125,
    reset_p     => reset_p,
    rxdone      => open);

uut2 : entity work.port_serial_spi_tb_helper
    generic map(SPI_MODE => 2)
    port map(
    refclk      => clk_125,
    reset_p     => reset_p,
    rxdone      => open);

uut3 : entity work.port_serial_spi_tb_helper
    generic map(SPI_MODE => 3)
    port map(
    refclk      => clk_125,
    reset_p     => reset_p,
    rxdone      => open);

end tb;
