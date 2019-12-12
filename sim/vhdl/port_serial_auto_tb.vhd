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
-- Testbench for auto-sensing Ethernet-over-Serial port (SPI/UART)
--
-- This is a self-checking unit test for the auto-sensing Ethernet-over-Serial
-- port.  It connects an auto-sensing port to each of the supported port types,
-- then exchanges traffic back and forth to verify correct operation.
--
-- The complete test takes less than 200 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_types.all;
use     work.switch_types.all;

entity port_serial_auto_tb_helper is
    generic(
    PORT_TYPE   : string;       -- SPI, UART1, UART2
    RX_PACKETS  : integer;      -- Declare "done" after N packets
    REFCLK_HZ   : integer := 125000000);
    port(
    refclk      : in  std_logic;
    reset_p     : in  std_logic;
    rxdone      : out std_logic);
end port_serial_auto_tb_helper;

architecture helper of port_serial_auto_tb_helper is

-- Certain parameters are not auto-detected.
constant SPI_MODE   : integer := 3;         -- SPI clock phase & polarity
constant UART_BAUD  : integer := 921600;    -- UART baud rate
constant SPI_CPOL   : std_logic := bool2bit(SPI_MODE >= 2);

-- Interface-specific support signals.
signal spi_clk10    : std_logic := SPI_CPOL;
signal spi_csb      : std_logic := '1';
signal spi_sdo      : std_logic := '0';
signal spi_sdt      : std_logic := '0';
signal uart_ctsb    : std_logic := '1';

-- Streaming source and sink for each link:
signal txdata_a, txdata_b   : port_tx_m2s;
signal txctrl_a, txctrl_b   : port_tx_s2m;
signal rxdata_a, rxdata_b   : port_rx_m2s;
signal rxdone_a, rxdone_b   : std_logic;

-- All possible interfaces use 4 pins.
signal ext_pads : std_logic_vector(3 downto 0);

begin

-- Interface-specific support signals.
spi_clk10 <= not spi_clk10 after 50 ns; -- 1 / (2*50ns) = 10 MHz
spi_csb   <= reset_p after 1 us;        -- SPI permanently enabled after reset
uart_ctsb <= reset_p after 1 us;        -- UART permanently ready to receive

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

-- The auto-sensing unit under test.
uut_a : entity work.port_serial_auto
    generic map (
    CLKREF_HZ   => REFCLK_HZ,
    SPI_MODE    => SPI_MODE,
    UART_BAUD   => UART_BAUD)
    port map (
    ext_pads    => ext_pads,
    rx_data     => rxdata_a,
    tx_data     => txdata_a,
    tx_ctrl     => txctrl_a,
    refclk      => refclk,
    reset_p     => reset_p);

-- Instantiate the appropriate counterpart.
-- (And any other required support signals.)
gen_spi : if (PORT_TYPE = "SPI") generate
    uut_b : entity work.port_serial_spi
        generic map(
        CLKREF_HZ   => REFCLK_HZ,
        SPI_MODE    => SPI_MODE)
        port map(
        spi_csb     => ext_pads(0),
        spi_sclk    => ext_pads(3),
        spi_sdi     => ext_pads(2),
        spi_sdo     => spi_sdo,
        spi_sdt     => spi_sdt,
        rx_data     => rxdata_b,
        tx_data     => txdata_b,
        tx_ctrl     => txctrl_b,
        refclk      => refclk,
        reset_p     => reset_p);

    -- Connecting two SPI slaves -> inject CSb and CLK.
    ext_pads(0) <= spi_csb;
    ext_pads(3) <= spi_clk10 or spi_csb;
    ext_pads(1) <= 'Z' when (spi_sdt = '1') else spi_sdo;
end generate;

--                      Pin 0       Pin 1       Pin 2       Pin 3
--     (0) Auto         Pullup      Pullup      Pullup      Pullup
--     (1) SPI          CSb (In)    MOSI (In)   MISO (Out)  SCK (In)
--     (2) UART (norm)  CTSb (In)   TxD (Out)   RxD (In)    RTSb (Out)
--     (3) UART (swap)  RTSb (Out)  RxD (In)    TxD (Out)   CTSb (In)

gen_uart1 : if (PORT_TYPE = "UART1") generate
    uut_b : entity work.port_serial_uart_4wire
        generic map (
        CLKREF_HZ   => REFCLK_HZ,
        BAUD_HZ     => UART_BAUD)
        port map (
        uart_txd    => ext_pads(2),
        uart_rxd    => ext_pads(1),
        uart_rts_n  => open,
        uart_cts_n  => uart_ctsb,
        rx_data     => rxdata_b,
        tx_data     => txdata_b,
        tx_ctrl     => txctrl_b,
        refclk      => refclk,
        reset_p     => reset_p);

    ext_pads(0) <= uart_ctsb;
end generate;

gen_uart2 : if (PORT_TYPE = "UART2") generate
    uut_b : entity work.port_serial_uart_4wire
        generic map (
        CLKREF_HZ   => REFCLK_HZ,
        BAUD_HZ     => UART_BAUD)
        port map (
        uart_txd    => ext_pads(1),
        uart_rxd    => ext_pads(2),
        uart_rts_n  => open,
        uart_cts_n  => uart_ctsb,
        rx_data     => rxdata_b,
        tx_data     => txdata_b,
        tx_ctrl     => txctrl_b,
        refclk      => refclk,
        reset_p     => reset_p);

    ext_pads(3) <= uart_ctsb;
end generate;

-- Print "done" message when both links have received N packets.
rxdone <= rxdone_a and rxdone_b;

p_done : process
begin
    wait until (rxdone_a = '1' and rxdone_b = '1');
    report "Test completed: " & PORT_TYPE;
    wait;
end process;

end helper;




library ieee;
use     ieee.std_logic_1164.all;

entity port_serial_auto_tb is
    -- Unit testbench top level, no I/O ports
end port_serial_auto_tb;

architecture tb of port_serial_auto_tb is

-- Clock and reset generation.
signal clk_125      : std_logic := '0';
signal reset_p      : std_logic := '1';

begin

-- Clock and reset generation.
clk_125 <= not clk_125 after 4 ns;
reset_p <= '0' after 1 us;

-- Instantiate one test unit for each supported port type.
uut_spi : entity work.port_serial_auto_tb_helper
    generic map(
    PORT_TYPE   => "SPI",
    RX_PACKETS  => 200)
    port map(
    refclk      => clk_125,
    reset_p     => reset_p,
    rxdone      => open);

uut_uart1 : entity work.port_serial_auto_tb_helper
    generic map(
    PORT_TYPE   => "UART1",
    RX_PACKETS  => 20)
    port map(
    refclk      => clk_125,
    reset_p     => reset_p,
    rxdone      => open);

uut_uart2 : entity work.port_serial_auto_tb_helper
    generic map(
    PORT_TYPE   => "UART2",
    RX_PACKETS  => 20)
    port map(
    refclk      => clk_125,
    reset_p     => reset_p,
    rxdone      => open);

end tb;

