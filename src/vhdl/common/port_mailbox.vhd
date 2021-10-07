--------------------------------------------------------------------------
-- Copyright 2020, 2021 The Aerospace Corporation
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
-- "Mailbox" port for use with ConfigBus
--
-- This block acts as a virtual internal port, connecting an Ethernet
-- switch core to a memory-mapped interface suitable for integrating
-- a soft-core microcontroller. (e.g., LEON, Microblaze, etc.) or
-- any other ConfigBus host.
--
-- Ingress and egress buffers for frame data must be included separately.
-- Typically, this block is used in conjunction with switch_core or
-- switch_dual, which both provide such buffers on all ports.  As such,
-- redundant buffers are not provided inside this block.
--
-- To reduce CPU burden, any or all of the following features can
-- be enabled at build-time:
--  * Append FCS to the end of each sent packet.
--  * Remove FCS from the end of each received packet.
--  * Zero-pad short packets to the specified minimum length.
--
-- Status, control, and frame data are transferred using a ConfigBus
-- memory-mapped interface with a single 32-bit register.  Note that
-- register access must be word-atomic, and that reads and writes both
-- have side-effects.  For simplicity, data is transferred a byte at
-- a time, with upper bits reserved for status flags.
--
-- To reduce the need for blind polling, the block also provides an
-- ConfigBus interrupt that is raised whenever new data is received,
-- and cleared automatically when the last byte is read.  Use of this
-- interrupt signal is completely optional.
--
-- Writes to the control register take the following format:
--   Bit 31-24: Opcode
--              0x00 = No-op
--              0x02 = Write next byte
--              0x03 = Write final byte (end-of-frame)
--              0xFF = Reset
--              All other opcodes reserved.
--   Bit 23-08: Reserved (all zeros)
--   Bit 07-00: Next data byte, if applicable
--
-- Reads from the control register take the following format:
--   Bit 31:    Data-valid flag ('1' = next byte, '0' = no data)
--   Bit 30:    End-of-frame flag ('1' = end-of-frame)
--   Bit 29-08: Reserved
--   Bit 07-00: Next data byte, if applicable
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.common_primitives.sync_reset;
use     work.cfgbus_common.all;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity port_mailbox is
    generic (
    DEV_ADDR    : integer;              -- Peripheral address (-1 = any)
    REG_ADDR    : integer := -1;        -- Register address (-1 = any)
    IRQ_ENABLE  : boolean := true;      -- Enable ConfigBus interrupt?
    MIN_FRAME   : natural := 64;        -- Minimum output frame size
    APPEND_FCS  : boolean := true;      -- Append FCS to each sent frame??
    STRIP_FCS   : boolean := true);     -- Remove FCS from received frames?
    port (
    -- Internal Ethernet port.
    rx_data     : out port_rx_m2s;
    tx_data     : in  port_tx_s2m;
    tx_ctrl     : out port_tx_m2s;

    -- ConfigBus interface.
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack);
end port_mailbox;

architecture port_mailbox of port_mailbox is

constant OPCODE_WRBYTE  : byte_t := x"02";
constant OPCODE_WRFINAL : byte_t := x"03";
constant OPCODE_RESET   : byte_t := x"FF";

-- Internal reset signal
signal port_areset  : std_logic;
signal port_reset_p : std_logic;

-- Parse and execute commands from CPU.
signal cfg_status   : cfgbus_word;
signal cfg_irq      : std_logic := '0';
signal cmd_opcode   : byte_t := (others => '0');
signal cmd_data     : byte_t := (others => '0');
signal cmd_exec     : std_logic := '0';
signal cmd_last     : std_logic := '0';
signal cmd_write    : std_logic := '0';
signal cmd_reset    : std_logic := '1';

-- FIFO for transmit data.
signal wr_buf_data  : byte_t := (others => '0');
signal wr_buf_last  : std_logic;
signal wr_buf_valid : std_logic;
signal wr_buf_ready : std_logic;

-- Ethernet frame adjustments (e.g., removing FCS)
signal rd_adj_data  : byte_t;
signal rd_adj_last  : std_logic;
signal rd_adj_valid : std_logic;
signal rd_adj_ready : std_logic;

begin

-- Drive simple port outputs.
rx_data.clk     <= cfg_cmd.clk;
rx_data.rxerr   <= '0';
rx_data.rate    <= get_rate_word(1);
rx_data.status  <= (0 => port_reset_p, others => '0');
rx_data.reset_p <= port_reset_p;

tx_ctrl.clk     <= cfg_cmd.clk;
tx_ctrl.txerr   <= '0';
tx_ctrl.reset_p <= port_reset_p;

-- Hold port reset at least N clock cycles.
port_areset <= cmd_reset or cfg_cmd.reset_p;

u_rst : sync_reset
    port map(
    in_reset_p  => port_areset,
    out_reset_p => port_reset_p,
    out_clk     => cfg_cmd.clk);

-- Decode command word + small FIFO for flow-control.
cmd_last    <= cmd_exec and bool2bit(cmd_opcode = OPCODE_WRFINAL);
cmd_write   <= cmd_exec and bool2bit(cmd_opcode = OPCODE_WRFINAL
                                  or cmd_opcode = OPCODE_WRBYTE);
cmd_reset   <= cmd_exec and bool2bit(cmd_opcode = OPCODE_RESET);

u_wr_fifo : entity work.fifo_smol_sync
    generic map(IO_WIDTH => 8)
    port map(
    in_data     => cmd_data,
    in_last     => cmd_last,
    in_write    => cmd_write,
    out_data    => wr_buf_data,
    out_last    => wr_buf_last,
    out_valid   => wr_buf_valid,
    out_read    => wr_buf_ready,
    clk         => cfg_cmd.clk,
    reset_p     => port_reset_p);

-- Optionally append and zero-pad data before sending.
u_wr_adj : entity work.eth_frame_adjust
    generic map(
    MIN_FRAME   => MIN_FRAME,
    APPEND_FCS  => APPEND_FCS,
    STRIP_FCS   => false)
    port map(
    in_data     => wr_buf_data,
    in_last     => wr_buf_last,
    in_valid    => wr_buf_valid,
    in_ready    => wr_buf_ready,
    out_data    => rx_data.data,
    out_last    => rx_data.last,
    out_valid   => rx_data.write,
    out_ready   => '1',
    clk         => cfg_cmd.clk,
    reset_p     => port_reset_p);

-- Optionally strip FCS from received data.
rd_adj_ready <= bool2bit(cfgbus_rdcmd(cfg_cmd, DEV_ADDR, REG_ADDR));

u_rd_adj : entity work.eth_frame_adjust
    generic map(
    MIN_FRAME   => 0,
    APPEND_FCS  => false,
    STRIP_FCS   => STRIP_FCS)
    port map(
    in_data     => tx_data.data,
    in_last     => tx_data.last,
    in_valid    => tx_data.valid,
    in_ready    => tx_ctrl.ready,
    out_data    => rd_adj_data,
    out_last    => rd_adj_last,
    out_valid   => rd_adj_valid,
    out_ready   => rd_adj_ready,
    clk         => cfg_cmd.clk,
    reset_p     => port_reset_p);

-- ConfigBus interface.
cfg_status <= rd_adj_valid & rd_adj_last & "0000000000000000000000" & rd_adj_data;

p_cfgbus : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- Latch write commands for decoding
        if (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, REG_ADDR)) then
            cmd_opcode  <= cfg_cmd.wdata(31 downto 24);
            cmd_data    <= cfg_cmd.wdata(7 downto 0);
            cmd_exec    <= '1';
        else
            cmd_exec    <= '0';
        end if;

        -- Service read requests.
        if (cfgbus_rdcmd(cfg_cmd, DEV_ADDR, REG_ADDR)) then
            cfg_ack <= cfgbus_reply(cfg_status, cfg_irq);
        else
            cfg_ack <= cfgbus_idle(cfg_irq);
        end if;

        -- Interrupt is asserted whenever there's data to be read.
        -- (Buffer helps with routing and timing.)
        cfg_irq <= rd_adj_valid and bool2bit(IRQ_ENABLE);
    end if;
end process;

end port_mailbox;
