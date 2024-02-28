--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- ConfigBus-controlled UART peripheral
--
-- This block implements a flexible, software-controlled UART peripheral.
-- Tx and Rx data are held in a small FIFO, for byte-by-byte polling by
-- the host controller.
--
-- This block raises a ConfigBus interrupt whenever there is received
-- data in the FIFO, waiting to be read.
--
-- Control is handled through four ConfigBus registers:
-- (All bits not explicitly mentioned are reserved; write zeros.)
--  * REGADDR = 0: Interrupt control
--      Refer to cfgbus_common::cfgbus_interrupt
--  * REGADDR = 1: Configuration
--      Any write to this register resets the UART and clears all FIFOs.
--      Bit 15-00: Clock divider ratio (BAUD_HZ = REF_CLK / N)
--  * REGADDR = 2: Status (Read only)
--      Bit 02-02: Running / busy
--      Bit 01-01: Command FIFO full
--      Bit 00-00: Read FIFO has data
--  * REGADDR = 3: Data
--      Write: Queue a byte for transmission
--          Bit 07-00: Transmit byte
--      Read: Read next byte from receive FIFO
--          Bit 08-08: Received byte valid
--          Bit 07-00: Received byte, if applicable
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity cfgbus_uart is
    generic(
    DEVADDR     : integer;          -- Control register address
    FIFO_LOG2   : integer := 6);    -- Tx/Rx FIFO depth = 2^N
    port(
    -- External UART signals.
    uart_txd    : out std_logic;
    uart_rxd    : in  std_logic;

    -- Command interface, including reference clock.
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack);
end cfgbus_uart;

architecture cfgbus_uart of cfgbus_uart is

-- Transmit data
signal tx_data      : byte_t;
signal tx_valid     : std_logic;
signal tx_ready     : std_logic;
signal tx_busy      : std_logic;

-- Received data
signal rx_data      : byte_t;
signal rx_write     : std_logic;

-- ConfigBus interface
signal cfg_word     : cfgbus_word;
signal cfg_rate     : unsigned(15 downto 0);
signal cfg_reset    : std_logic;            -- Reset FIFOs and SPI state

begin

-- Tx and Rx UARTs
u_tx : entity work.io_uart_tx
    port map(
    uart_txd    => uart_txd,
    tx_data     => tx_data,
    tx_valid    => tx_valid,
    tx_ready    => tx_ready,
    rate_div    => cfg_rate,
    refclk      => cfg_cmd.clk,
    reset_p     => cfg_reset);

u_rx : entity work.io_uart_rx
    port map(
    uart_rxd    => uart_rxd,
    rx_data     => rx_data,
    rx_write    => rx_write,
    rate_div    => cfg_rate,
    refclk      => cfg_cmd.clk,
    reset_p     => cfg_reset);

-- Transmit in progress?
tx_busy     <= tx_valid or not tx_ready;

-- Extract configuration parameters:
cfg_rate    <= unsigned(cfg_word(15 downto 0));

-- ConfigBus interface
u_cfg : entity work.cfgbus_multiserial
    generic map(
    DEVADDR     => DEVADDR,
    CFG_MASK    => x"0000FFFF",
    CFG_RSTVAL  => x"0000FFFF",
    IRQ_RXDATA  => true,
    FIFO_LOG2   => FIFO_LOG2)
    port map(
    cmd_data    => tx_data,
    cmd_valid   => tx_valid,
    cmd_ready   => tx_ready,
    rx_data     => rx_data,
    rx_write    => rx_write,
    cfg_reset   => cfg_reset,
    cfg_word    => cfg_word,
    status_busy => tx_busy,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack);

end cfgbus_uart;
