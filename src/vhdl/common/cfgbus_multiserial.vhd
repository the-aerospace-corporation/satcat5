--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- ConfigBus-controlled generic serial peripheral
--
-- This block implements a flexible, software-controlled control module
-- for byte-by-byte transfers, which can be attached to a variety of I/O
-- controllers to form a complete I2C, SPI, or UART peripheral.
--
-- By using a common control system, we hope to improve reusability of
-- the associated driver software.
--
-- The child interface should trigger an interrupt when service may be
-- required, such as completion of a bus transaction.  Any change on
-- the asynchronous "event_tog" signal will raise an interrupt.
-- Alternately, set IRQ_RXDATA to raise an interrupt whenever there
-- is new received data.
--
-- Control is handled through four ConfigBus registers:
-- (All bits not explicitly mentioned are reserved; write zeros.)
--  * REGADDR = 0: Interrupt control
--      Refer to cfgbus_common::cfgbus_interrupt
--  * REGADDR = 1: Configuration
--      Any write to this register resets the interface and clears all FIFOs.
--      Contents of this register are specific to the child interface.
--  * REGADDR = 2: Status (Read only)
--      Bit 03-03: Error flag (e.g., I2C missing ACK)
--      Bit 02-02: Running / busy
--      Bit 01-01: Command FIFO full
--      Bit 00-00: Read FIFO has data
--  * REGADDR = 3: Data
--      Write: Queue a single command
--          Bit 11-08: Command opcode (if applicable)
--          Bit 07-00: Transmit byte or special argument
--      Read: Read next data byte from receive FIFO
--          Bit 08-08: Received byte valid
--          Bit 07-00: Received byte, if applicable
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.eth_frame_common.byte_t;

entity cfgbus_multiserial is
    generic (
    DEVADDR     : integer;          -- Control register address
    CFG_MASK    : cfgbus_word;      -- Writeable-bit mask for Reg1
    CFG_RSTVAL  : cfgbus_word;      -- Default value for Reg1
    IRQ_RXDATA  : boolean := false; -- Raise interrupt for Rx-data?
    FIFO_LOG2   : integer := 6);    -- Tx/Rx FIFO depth = 2^N
    port (
    -- Transmit and receive command streams.
    cmd_opcode  : out std_logic_vector(3 downto 0);
    cmd_data    : out byte_t;
    cmd_valid   : out std_logic;
    cmd_ready   : in  std_logic;
    rx_data     : in  byte_t;
    rx_write    : in  std_logic;

    -- Configuration and status interface.
    cfg_reset   : out std_logic;
    cfg_word    : out cfgbus_word;
    status_busy : in  std_logic := '0';
    status_err  : in  std_logic := '0';
    event_tog   : in  std_logic := '0';

    -- Command interface, including reference clock.
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack);
end cfgbus_multiserial;

architecture cfgbus_multiserial of cfgbus_multiserial is

signal cfg_acks     : cfgbus_ack_array(0 to 3);
signal cfg_status   : cfgbus_word;
signal cfg_change   : std_logic;
signal cfg_wr_full  : std_logic;
signal cfg_rd_rdy   : std_logic;
signal event_flag   : std_logic;

begin

-- Combine all read responses.
cfg_ack <= cfgbus_merge(cfg_acks);

-- Strobes for child interface:
cfg_reset <= cfg_cmd.reset_p or cfg_change;

-- Generate interrupt for received data?
event_flag <= cfg_rd_rdy and bool2bit(IRQ_RXDATA);

-- Construct the status word:
cfg_status  <= (
    0 => cfg_rd_rdy,
    1 => cfg_wr_full,
    2 => status_busy,
    3 => status_err,
    others => '0');

-- Define each register:
u_reg0 : cfgbus_interrupt
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => 0)   -- Reg0 = Interrupt control
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(0),
    ext_flag    => event_flag,
    ext_toggle  => event_tog);

u_reg1 : cfgbus_register
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => 1,   -- Reg1 = Configuration
    WR_ATOMIC   => true,
    WR_MASK     => CFG_MASK,
    RSTVAL      => CFG_RSTVAL)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(1),
    reg_val     => cfg_word,
    evt_wr_str  => cfg_change);

u_reg2 : cfgbus_readonly
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => 2)   -- Reg2 = Status
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(2),
    reg_val     => cfg_status);

u_reg3 : entity work.cfgbus_fifo
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => 3,   -- Reg3 = Data
    WR_DEPTH    => FIFO_LOG2,
    WR_DWIDTH   => 8,   -- Command data
    WR_MWIDTH   => 4,   -- Command opcode
    RD_DEPTH    => FIFO_LOG2,
    RD_DWIDTH   => 8,   -- Response data
    RD_MWIDTH   => 1,   -- Response valid
    RD_FLAGS    => false)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(3),
    cfg_clear   => cfg_change,
    cfg_wr_full => cfg_wr_full,
    cfg_rd_rdy  => cfg_rd_rdy,
    wr_clk      => cfg_cmd.clk,
    wr_data     => cmd_data,
    wr_meta     => cmd_opcode,
    wr_valid    => cmd_valid,
    wr_ready    => cmd_ready,
    rd_clk      => cfg_cmd.clk,
    rd_data     => rx_data,
    rd_meta(0)  => '1',
    rd_valid    => rx_write,
    rd_ready    => open);

end cfgbus_multiserial;
