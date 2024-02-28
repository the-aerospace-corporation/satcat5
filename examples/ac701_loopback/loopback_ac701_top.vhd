--------------------------------------------------------------------------
-- Copyright 2021-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Top-level design: Loopback SGMII testing for Xilinx AC701
--
-- This module is used for signal-integrity testing of the SGMII outputs,
-- or in a loopback mode to measure packet error statistics.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library unisim;
use     unisim.vcomponents.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.io_leds.all;
use     work.switch_types.all;

entity loopback_ac701_top is
    generic (
    BUILD_DATE  : string := "BD_UNKNOWN");
    port (
    -- SGMII test interface.
    sgmii_rxp   : in    std_logic;
    sgmii_rxn   : in    std_logic;
    sgmii_txp   : out   std_logic;
    sgmii_txn   : out   std_logic;

    -- Status indicators and other control.
    stat_led_g  : out   std_logic;  -- Green LED (breathing pattern)
    stat_led_y  : out   std_logic;  -- Yellow LED (SGMII not locked)
    stat_led_r  : out   std_logic;  -- Red LED (SGMII decode error)
    lcd_db      : out   std_logic_vector(3 downto 0);
    lcd_e       : out   std_logic;  -- LCD Chip enable
    lcd_rw      : out   std_logic;  -- LCD Read / write-bar
    lcd_rs      : out   std_logic;  -- LCD Data / command-bar
    uart_txd    : out   std_logic;  -- UART to host: SLIP-encoded test results
    ext_clk200p : in    std_logic;  -- External 200 MHz reference clock
    ext_clk200n : in    std_logic;  -- External 200 MHz reference clock
    ext_reset_p : in    std_logic); -- Global external reset
end loopback_ac701_top;

architecture loopback_ac701_top of loopback_ac701_top is

-- Switch provides 25 MHz, SGMII core generates all other clocks.
signal clk_ext      : std_logic;
signal clk_125      : std_logic;
signal clk_200      : std_logic;
signal clk_625_00   : std_logic;
signal clk_625_90   : std_logic;
signal clkgen_rst_p : std_logic;

signal rx_data      : port_rx_m2s;
signal tx_data      : port_tx_s2m;
signal tx_ctrl      : port_tx_m2s;

-- Error reporting for LCD.
signal aux_data     : byte_t;
signal aux_wr       : std_logic;
signal fifo_data    : byte_t;
signal fifo_valid   : std_logic;
signal fifo_rd      : std_logic;
signal txt_data     : byte_t := (others => '0');
signal txt_wr       : std_logic;

-- Prevent renaming of clocks and other key nets.
attribute KEEP : string;
attribute KEEP of clk_125, clk_625_00, clk_625_90 : signal is "true";

begin

-- Clock generation and global reset
u_clkbuf : IBUFDS
    generic map(
    DIFF_TERM       => false,
    IBUF_LOW_PWR    => false,
    IOSTANDARD      => "LVDS_25")
    port map(
    I               => ext_clk200p,
    IB              => ext_clk200n,
    O               => clk_ext);

u_clkgen : entity work.clkgen_sgmii_xilinx
    generic map(
    REFCLK_MHZ      => 200,
    SPEED_MULT      => 2)
    port map(
    shdn_p          => '0',
    rstin_p         => ext_reset_p,
    clkin_ref0      => clk_ext,
    clkin_ref1      => clk_ext,
    rstout_p        => clkgen_rst_p,
    clkout_125_00   => clk_125,
    clkout_125_90   => open,
    clkout_200      => clk_200,
    clkout_625_00   => clk_625_00,
    clkout_625_90   => clk_625_90);

-- Instantiate IDELAYCTRL.
-- (Vivado will automatically clone it to each needed location.)
u_idc : IDELAYCTRL
    port map(
    refclk  => clk_200,
    rst     => clkgen_rst_p,
    rdy     => open);

-- SGMII port under test.
-- Override default IOSTANDARD due to AC701 VCCO constraints:
--  Rx (VCCO = 1.5V): DIFF_SSTL15 with split termination (UG471 Fig 1-11)
--  Tx (VCCO = 2.5V): LVDS_25 (for representative eye-diagram performance)
u_sgmii : entity work.port_sgmii_gpio
    generic map(
    TX_INVERT   => false,
    TX_IOSTD    => "LVDS_25",
    RX_INVERT   => false,
    RX_IOSTD    => "DIFF_SSTL15",
    RX_BIAS_EN  => true,
    RX_TERM_EN  => false,
    SHAKE_WAIT  => false)
    port map(
    sgmii_rxp   => sgmii_rxp,
    sgmii_rxn   => sgmii_rxn,
    sgmii_txp   => sgmii_txp,
    sgmii_txn   => sgmii_txn,
    prx_data    => rx_data,
    ptx_data    => tx_data,
    ptx_ctrl    => tx_ctrl,
    port_shdn   => clkgen_rst_p,
    clk_125     => clk_125,
    clk_200     => clk_200,
    clk_625_00  => clk_625_00,
    clk_625_90  => clk_625_90);

-- Loopback test-pattern generator and error counting.
u_ptest : entity work.config_port_test
    generic map(
    BAUD_HZ     => 115_200,
    CLKREF_HZ   => 125_000_000,
    ETYPE_TEST  => x"5C09",
    PORT_COUNT  => 1,
    SLIP_UART   => true)
    port map(
    rx_data(0)  => rx_data,
    tx_data(0)  => tx_data,
    tx_ctrl(0)  => tx_ctrl,
    uart_txd    => uart_txd,
    aux_data    => aux_data,
    aux_wr      => aux_wr,
    refclk      => clk_125,
    reset_p     => clkgen_rst_p);

-- FIFO for each block of data.
u_fifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => 8,
    DEPTH_LOG2  => 4)
    port map(
    in_data     => aux_data,
    in_write    => aux_wr,
    out_data    => fifo_data,
    out_valid   => fifo_valid,
    out_read    => fifo_rd,
    clk         => clk_125,
    reset_p     => clkgen_rst_p);

-- Convert each uint32 into an eight-digit hexadecimal number plus newline.
p_txt : process(clk_125)
    subtype nybble is std_logic_vector(3 downto 0);
    function get_hex(x : nybble) return byte_t is
    begin
        case x is
            when x"0" =>    return x"30";   -- "0"
            when x"1" =>    return x"31";   -- "1"
            when x"2" =>    return x"32";   -- "2"
            when x"3" =>    return x"33";   -- "3"
            when x"4" =>    return x"34";   -- "4"
            when x"5" =>    return x"35";   -- "5"
            when x"6" =>    return x"36";   -- "6"
            when x"7" =>    return x"37";   -- "7"
            when x"8" =>    return x"38";   -- "8"
            when x"9" =>    return x"39";   -- "9"
            when x"A" =>    return x"41";   -- "A"
            when x"B" =>    return x"42";   -- "B"
            when x"C" =>    return x"43";   -- "C"
            when x"D" =>    return x"44";   -- "D"
            when x"E" =>    return x"45";   -- "E"
            when others =>  return x"46";   -- "F"
        end case;
    end function;

    variable ctr : integer range 0 to 8 := 0;
begin
    if rising_edge(clk_125) then
        if (clkgen_rst_p = '1') then
            -- Global reset
            txt_data <= (others => '0');
            txt_wr   <= '0';
            fifo_rd  <= '0';
            ctr      := 0;
        elsif (ctr = 0 or ctr = 2 or ctr = 4 or ctr = 6) then
            -- First half: Wait for input, then rapidly emit both half-digits.
            -- (Note one-cycle lag; FIFO word remains stable for next half-digit.
            txt_data <= get_hex(fifo_data(7 downto 4));
            txt_wr   <= fifo_valid;
            fifo_rd  <= fifo_valid;
            ctr      := ctr + u2i(fifo_valid);
        elsif (ctr = 1 or ctr = 3 or ctr = 5 or ctr = 7) then
            -- Second half: Immediately emit second half-digit.
            txt_data <= get_hex(fifo_data(3 downto 0));
            txt_wr   <= '1';
            fifo_rd  <= '0';
            ctr      := ctr + 1;
        else
            -- Final step is to emit a newline.
            txt_data <= x"0A";  -- LF character (\n)
            txt_wr   <= '1';
            fifo_rd  <= '0';
            ctr      := 0;      -- Restart cycle
        end if;
    end if;
end process;

-- LCD controller emits ASCII counter values.
u_lcd : entity work.io_text_lcd
    generic map(REFCLK_HZ => 125_000_000)
    port map(
    lcd_db      => lcd_db,
    lcd_e       => lcd_e,
    lcd_rw      => lcd_rw,
    lcd_rs      => lcd_rs,
    strm_clk    => clk_125,
    strm_data   => txt_data,
    strm_wr     => txt_wr,
    reset_p     => clkgen_rst_p);

-- Drive the three status LEDs.
u_led_g : breathe_led
    generic map(
    RATE    => breathe_led_rate(125_000_000),
    LED_LIT => '1')
    port map(
    led     => stat_led_g,
    clk     => clk_125);

u_led_y : sustain_exp_led
    generic map(
    DIV     => 1_000_000,
    LED_LIT => '1')
    port map(
    led     => stat_led_y,
    clk     => rx_data.clk,
    pulse   => rx_data.reset_p);

u_led_r : sustain_exp_led
    generic map(
    DIV     => 1_000_000,
    LED_LIT => '1')
    port map(
    led     => stat_led_r,
    clk     => rx_data.clk,
    pulse   => rx_data.rxerr);

end loopback_ac701_top;
