--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for Ethernet-over-Serial I2C port
--
-- This is a self-checking unit test for the Ethernet-over-Serial I2C port.
-- It connects a the controller and peripheral variants back-to-back to
-- confirm correct operation.
--
-- The complete test takes just under 400 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;         -- for UNIFORM
use     work.common_functions.all;
use     work.i2c_constants.all;     -- io_i2c_controller.vhd
use     work.switch_types.all;

entity port_serial_i2c_tb is
    generic (
    I2C_ADDR    : i2c_addr_t := "1010101";  -- I2C device address
    BAUD_HZ     : positive := 2_500_000);   -- I2C baud rate
end port_serial_i2c_tb;

architecture tb of port_serial_i2c_tb is

-- Clock and reset generation.
constant CLKREF_HZ  : positive := 100_000_000;
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Number of packets before declaring "done".
constant RX_PACKETS : integer := 50;

-- Flow control for the clock-source block.
signal ext_pause    : std_logic := '1';

-- Streaming source and sink for each link:
signal txdata_a, txdata_b   : port_tx_s2m;
signal txctrl_a, txctrl_b   : port_tx_m2s;
signal rxdata_a, rxdata_b   : port_rx_m2s;
signal rxdone_a, rxdone_b   : std_logic;

-- Two units under test, connected back-to-back.
signal i2c_sclk_o           : std_logic_vector(0 to 0);
signal i2c_sdata_o          : std_logic_vector(0 to 1);
signal i2c_sclk_i           : std_logic;
signal i2c_sdata_i          : std_logic;

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Pause the clock source at psuedorandom intervals.
p_flow : process
    variable seed1  : positive := 1234;
    variable seed2  : positive := 5678;
    variable rand   : real := 0.0;
    variable ctr    : integer := 0;
begin
    -- Brief idle period.
    ext_pause <= '1';
    wait for 100 us;

    -- Allow traffic for up to N intervals.
    uniform(seed1, seed2, rand);
    ctr := 1 + integer(floor(10.0 * rand));

    ext_pause <= '0';
    while (ctr > 0) loop
        wait for 100 us;
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
uut_a : entity work.port_serial_i2c_controller
    generic map(
    I2C_ADDR    => I2C_ADDR,
    CLKREF_HZ   => CLKREF_HZ,
    BAUD_HZ     => BAUD_HZ)
    port map(
    sclk_o      => i2c_sclk_o(0),
    sclk_i      => i2c_sclk_i,
    sdata_o     => i2c_sdata_o(0),
    sdata_i     => i2c_sdata_i,
    rx_data     => rxdata_a,
    tx_data     => txdata_a,
    tx_ctrl     => txctrl_a,
    ext_pause   => ext_pause,
    ref_clk     => clk_100,
    reset_p     => reset_p);

uut_b : entity work.port_serial_i2c_peripheral
    generic map(
    I2C_ADDR    => I2C_ADDR,
    CLKREF_HZ   => CLKREF_HZ)
    port map(
    sclk_i      => i2c_sclk_i,
    sdata_o     => i2c_sdata_o(1),
    sdata_i     => i2c_sdata_i,
    rts_out     => open,
    rx_data     => rxdata_b,
    tx_data     => txdata_b,
    tx_ctrl     => txctrl_b,
    ref_clk     => clk_100,
    reset_p     => reset_p);

-- Emulate the I2C bus: Any device can pull the shared line low.
i2c_sclk_i  <= and_reduce(i2c_sclk_o);
i2c_sdata_i <= and_reduce(i2c_sdata_o);

-- Print "done" message when both links have received N packets.
p_done : process
begin
    wait until (rxdone_a = '1' and rxdone_b = '1');
    report "All tests completed!";
    wait;
end process;

end tb;
