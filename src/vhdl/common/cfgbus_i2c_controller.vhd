--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- ConfigBus-controlled I2C bus controller.
--
-- This block implements ConfigBus wrapper for an I2C bus controller.
-- Each bus operation (start-bit, stop-bit, byte transfer, etc.) is directly
-- commanded by the host, one byte at a time, with a small FIFO for queueing
-- sequential commands.
--
-- This block raises a ConfigBus interrupt after each STOP bit is sent.
--
-- Generally, the top-level should instantiate a bidirectional buffer, to
-- connect SCL and SDA to their respective I/O pads.  For more details,
-- refer to "io_i2c_controller.vhd".
--
-- Control is handled through four ConfigBus registers:
-- (All bits not explicitly mentioned are reserved; write zeros.)
--  * REGADDR = 0: Interrupt control
--      Refer to cfgbus_common::cfgbus_interrupt
--  * REGADDR = 1: Configuration
--      Any write to this register resets the bus and clears all FIFOs.
--      Bit 31-31: Clock-stretching override ('1' = Ignore, '0' = Normal)
--      Bit 11-00: Clock divider ratio = 4*(N+1)
--  * REGADDR = 2: Status (Read only)
--      Bit 03-03: Missing ACK (Cleared on next START token)
--      Bit 02-02: Running / busy
--      Bit 01-01: Command FIFO full
--      Bit 00-00: Read FIFO has data
--  * REGADDR = 3: Data
--      Write: Queue a single command
--          Bit 11-08: Command opcode
--              0x0 Delay (equivalent to a single bit interval)
--              0x1 Send start bit
--              0x2 Send restart bit
--              0x3 Send stop bit
--              0x4 Transmit address or data byte
--              0x5 Receive data byte (normal, host sends ACK)
--              0x6 Receive data byte (final, no ACK)
--              (All other codes reserved)
--          Bit 07-00: Transmit byte, if applicable
--      Read: Read next data byte from receive FIFO
--          Bit 08-08: Received byte valid
--          Bit 07-00: Received byte, if applicable
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.i2c_constants.all;     -- io_i2c_controller.vhd

entity cfgbus_i2c_controller is
    generic(
    DEVADDR     : integer;          -- Control register address
    FIFO_LOG2   : integer := 6);    -- Tx/Rx FIFO depth = 2^N
    port(
    -- External I2C signals (active-low, suitable for sharing)
    -- Note: Top level should instantiate tri-state buffer.
    -- Note: sclk_i is required for clock-stretching, otherwise optional.
    sclk_o      : out std_logic;
    sclk_i      : in  std_logic := '1';
    sdata_o     : out std_logic;
    sdata_i     : in  std_logic := '1';

    -- Command interface, including reference clock.
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack);
end cfgbus_i2c_controller;

architecture cfgbus_i2c_controller of cfgbus_i2c_controller is

-- Command and transmit stream
signal cmd_opcode   : i2c_cmd_t;
signal cmd_data     : i2c_data_t;
signal cmd_valid    : std_logic;
signal cmd_ready    : std_logic;

-- Received-data and status stream
signal rx_data      : i2c_data_t;
signal rx_write     : std_logic;
signal bus_noack    : std_logic;
signal bus_stop     : std_logic;

-- ConfigBus interface
signal cfg_word     : cfgbus_word;
signal cfg_clkdiv   : i2c_clkdiv_t;         -- Clock-divider setting
signal cfg_nowait   : std_logic;            -- Disable clock-stretching
signal cfg_reset    : std_logic;            -- Reset FIFOs and I2C state
signal cfg_irq_t    : std_logic := '0';     -- Toggle on STOP token

begin

-- I2C controller
u_i2c : entity work.io_i2c_controller
    port map(
    sclk_o      => sclk_o,
    sclk_i      => sclk_i,
    sdata_o     => sdata_o,
    sdata_i     => sdata_i,
    cfg_clkdiv  => cfg_clkdiv,
    cfg_nowait  => cfg_nowait,
    tx_opcode   => cmd_opcode,
    tx_data     => cmd_data,
    tx_valid    => cmd_valid,
    tx_ready    => cmd_ready,
    rx_data     => rx_data,
    rx_write    => rx_write,
    bus_noack   => bus_noack,
    bus_stop    => bus_stop,
    ref_clk     => cfg_cmd.clk,
    reset_p     => cfg_reset);

-- Trigger an interrupt event after each STOP token.
p_irq : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        if (bus_stop = '1') then
            cfg_irq_t <= not cfg_irq_t;
        end if;
    end if;
end process;

-- Extract configuration parameters:
cfg_clkdiv  <= unsigned(cfg_word(11 downto 0));
cfg_nowait  <= cfg_word(31);

-- ConfigBus interface
u_cfg : entity work.cfgbus_multiserial
    generic map(
    DEVADDR     => DEVADDR,
    CFG_MASK    => x"80000FFF",
    CFG_RSTVAL  => x"00000FFF",
    FIFO_LOG2   => FIFO_LOG2)
    port map(
    cmd_opcode  => cmd_opcode,
    cmd_data    => cmd_data,
    cmd_valid   => cmd_valid,
    cmd_ready   => cmd_ready,
    rx_data     => rx_data,
    rx_write    => rx_write,
    cfg_reset   => cfg_reset,
    cfg_word    => cfg_word,
    status_busy => cmd_valid,
    status_err  => bus_noack,
    event_tog   => cfg_irq_t,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack);

end cfgbus_i2c_controller;
