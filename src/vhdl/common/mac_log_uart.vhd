--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- UART wrapper for "mac_log_core"
--
-- This block is a thin wrapper for "mac_log_core" that SLIP-encodes each
-- packet descriptor and streams the result over a UART.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.byte_t;
use     work.switch_types.all;

entity mac_log_uart is
    generic (
    UART_BAUD   : positive;         -- UART baud rate (Hz)
    CORE_CLK_HZ : positive;         -- Core clock frequency (Hz)
    PORT_COUNT  : positive);        -- Number of ingress ports
    port (
    -- Packet logs from the shared pipeline.
    mac_data    : in  log_meta_t;
    mac_psrc    : in  integer range 0 to PORT_COUNT-1;
    mac_dmask   : in  std_logic_vector(PORT_COUNT-1 downto 0);
    mac_write   : in  std_logic;

    -- Packet logs from each ingress port.
    port_data   : in  log_meta_array(PORT_COUNT-1 downto 0);
    port_write  : in  std_logic_vector(PORT_COUNT-1 downto 0);

    -- SLIP-encoded UART.
    uart_txd    : out std_logic;

    -- Clock and synchronous reset.
    core_clk    : in  std_logic;
    reset_p     : in  std_logic);
end mac_log_uart;

architecture mac_log_uart of mac_log_uart is

-- UART clock-divider is fixed at build-time.
constant UART_CLKDIV : unsigned(15 downto 0) :=
    to_unsigned(clocks_per_baud_uart(CORE_CLK_HZ, UART_BAUD), 16);

signal log_data     : byte_t;
signal log_last     : std_logic;
signal log_valid    : std_logic;
signal log_ready    : std_logic;
signal slip_data    : byte_t;
signal slip_valid   : std_logic;
signal slip_ready   : std_logic;

begin

-- Generate log-data stream as 24-bit words.
u_log : entity work.mac_log_core
    generic map(
    CORE_CLK_HZ => CORE_CLK_HZ,
    OUT_BYTES   => 1,
    PORT_COUNT  => PORT_COUNT)
    port map(
    mac_data    => mac_data,
    mac_psrc    => mac_psrc,
    mac_dmask   => mac_dmask,
    mac_write   => mac_write,
    port_data   => port_data,
    port_write  => port_write,
    out_clk     => core_clk,
    out_data    => log_data,
    out_last    => log_last,
    out_valid   => log_valid,
    out_ready   => log_ready,
    core_clk    => core_clk,
    reset_p     => reset_p);

-- SLIP encoder marks packet boundaries.
u_slip : entity work.slip_encoder
    port map(
    in_data     => log_data,
    in_last     => log_last,
    in_valid    => log_valid,
    in_ready    => log_ready,
    out_data    => slip_data,
    out_last    => open,
    out_valid   => slip_valid,
    out_ready   => slip_ready,
    refclk      => core_clk,
    reset_p     => reset_p);

-- Transmit UART.
u_uart : entity work.io_uart_tx
    port map(
    uart_txd    => uart_txd,
    tx_data     => slip_data,
    tx_valid    => slip_valid,
    tx_ready    => slip_ready,
    rate_div    => UART_CLKDIV,
    refclk      => core_clk,
    reset_p     => reset_p);

end mac_log_uart;
