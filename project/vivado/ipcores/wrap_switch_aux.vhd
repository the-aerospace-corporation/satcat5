--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Port-type wrapper for "switch_aux"
--
-- Xilinx IP-cores can only use simple std_logic and std_logic_vector types.
-- This shim provides that conversion.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.switch_types.all;

entity wrap_switch_aux is
    generic (
    SCRUB_CLK_HZ    : integer := 100_000_000;
    SCRUB_ENABLE    : boolean := false;
    STARTUP_MSG     : string := "SatCat5 READY!";
    UART_BAUD       : integer := 921600;
    CORE_COUNT      : integer := 1);
    port (
    -- Up to a dozen error vector ports, enabled/hidden based on CORE_COUNT.
    -- (Each is a "toggle" indicator in any clock domain.)
    errvec_00       : in  std_logic_vector(7 downto 0);
    errvec_01       : in  std_logic_vector(7 downto 0);
    errvec_02       : in  std_logic_vector(7 downto 0);
    errvec_03       : in  std_logic_vector(7 downto 0);
    errvec_04       : in  std_logic_vector(7 downto 0);
    errvec_05       : in  std_logic_vector(7 downto 0);
    errvec_06       : in  std_logic_vector(7 downto 0);
    errvec_07       : in  std_logic_vector(7 downto 0);
    errvec_08       : in  std_logic_vector(7 downto 0);
    errvec_09       : in  std_logic_vector(7 downto 0);
    errvec_10       : in  std_logic_vector(7 downto 0);
    errvec_11       : in  std_logic_vector(7 downto 0);

    -- Status UART.
    status_uart     : out std_logic;    -- Plaintext error messages

    -- Text LCD (optional)
    text_lcd_db     : out std_logic_vector(3 downto 0);  -- Data (4-bit mode)
    text_lcd_e      : out std_logic;    -- Chip enable
    text_lcd_rw     : out std_logic;    -- Read / write-bar
    text_lcd_rs     : out std_logic;    -- Data / command-bar

    -- System interface.
    scrub_clk       : in  std_logic;    -- Scrubbing clock (always-on!)
    scrub_req_t     : out std_logic;    -- MAC-table scrub request (toggle)
    reset_p         : in  std_logic);   -- Global system reset
end wrap_switch_aux;

architecture wrap_switch_aux of wrap_switch_aux is

signal swerr_vec_t  : std_logic_vector(12*SWITCH_ERR_WIDTH-1 downto 0);
signal msg_data     : std_logic_vector(7 downto 0);
signal msg_write    : std_logic;

begin

-- Concatenate the error vectors. (Word order doesn't matter.)
swerr_vec_t <= errvec_00 & errvec_01
             & errvec_02 & errvec_03
             & errvec_04 & errvec_05
             & errvec_06 & errvec_07
             & errvec_08 & errvec_09
             & errvec_10 & errvec_11;

-- Unit being wrapped.
u_wrap : entity work.switch_aux
    generic map(
    SCRUB_CLK_HZ    => SCRUB_CLK_HZ,
    SCRUB_ENABLE    => SCRUB_ENABLE,
    STARTUP_MSG     => STARTUP_MSG,
    STATUS_LED_LIT  => '1',     -- Unused / don't-care
    UART_BAUD       => UART_BAUD,
    CORE_COUNT      => CORE_COUNT)
    port map(
    swerr_vec_t     => swerr_vec_t(CORE_COUNT*SWITCH_ERR_WIDTH-1 downto 0),
    status_led_grn  => open,
    status_led_ylw  => open,
    status_led_red  => open,
    status_uart     => status_uart,
    status_aux_dat  => msg_data,
    status_aux_wr   => msg_write,
    scrub_clk       => scrub_clk,
    scrub_req_t     => scrub_req_t,
    reset_p         => reset_p);

-- LCD controller
u_lcd : entity work.io_text_lcd
    generic map(
    REFCLK_HZ   => SCRUB_CLK_HZ)
    port map(
    lcd_db      => text_lcd_db,
    lcd_e       => text_lcd_e,
    lcd_rw      => text_lcd_rw,
    lcd_rs      => text_lcd_rs,
    strm_clk    => scrub_clk,
    strm_data   => msg_data,
    strm_wr     => msg_write,
    reset_p     => reset_p);

end wrap_switch_aux;
