--------------------------------------------------------------------------
-- Copyright 2019, 2020 The Aerospace Corporation
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
-- "Mailbox" port for use with AXI-Lite microcontrollers
--
-- This block acts as a virtual internal port, connecting an Ethernet
-- switch core to a memory-mapped interface suitable for integrating
-- a soft-core microcontroller. (e.g., LEON, Microblaze, etc.)
--
-- Ingress and egress buffers for frame data must be included separately.
-- Typically, this block is used in conjunction with switch_core or
-- switch_dual, which both provide such buffers on all ports.  As such,
-- redundant buffers are not provided inside this block.
--
-- For more information on AXI-Lite, refer to the "AMBA AXI and ACE
-- Protocol Specification" (ARM IHI 0022E), version 4, Section B.
--
-- To reduce CPU burden, any or all of the following features can
-- be enabled at build-time:
--  * Append FCS to the end of each sent packet.
--  * Remove FCS from the end of each received packet.
--  * Zero-pad short packets to the specified minimum length.
--
-- Status, control, and frame data are transferred using an AXI-Lite
-- memory-mapped interface with a single 32-bit register.  Note that
-- register access must be word-atomic, and that reads and writes both
-- have side-effects.  For simplicity, data is transferred a byte at
-- a time, with upper bits reserved for status flags.
--
-- To reduce the need for blind polling, the block also provides an
-- interrupt that is suitable for use with level-sensitive interrupt
-- controllers.  The interrupt flag is raised whenever new data is
-- received, and cleared automatically when the last byte is read.
-- Use of this interrupt signal is completely optional.
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
use     work.switch_types.all;
use     work.synchronization.all;

entity port_axi_mailbox is
    generic (
    ADDR_WIDTH  : integer := 32;        -- AXI-Lite address width
    REG_ADDR    : integer := -1;        -- Control register address (-1 = any)
    MIN_FRAME   : integer := 0;         -- Minimum output frame size
    APPEND_FCS  : boolean := true;      -- Append FCS to each sent frame??
    STRIP_FCS   : boolean := true);     -- Remove FCS from received frames?
    port (
    -- Internal Ethernet port.
    rx_data     : out port_rx_m2s;
    tx_data     : in  port_tx_m2s;
    tx_ctrl     : out port_tx_s2m;

    -- Interrupt signal (optional)
    irq_out     : out std_logic;

    -- AXI-Lite interface
    axi_clk     : in  std_logic;
    axi_aresetn : in  std_logic;
    axi_awaddr  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    axi_awvalid : in  std_logic;
    axi_awready : out std_logic;
    axi_wdata   : in  std_logic_vector(31 downto 0);
    axi_wstrb   : in  std_logic_vector(3 downto 0) := "1111";
    axi_wvalid  : in  std_logic;
    axi_wready  : out std_logic;
    axi_bresp   : out std_logic_vector(1 downto 0);
    axi_bvalid  : out std_logic;
    axi_bready  : in  std_logic;
    axi_araddr  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    axi_arvalid : in  std_logic;
    axi_arready : out std_logic;
    axi_rdata   : out std_logic_vector(31 downto 0);
    axi_rresp   : out std_logic_vector(1 downto 0);
    axi_rvalid  : out std_logic;
    axi_rready  : in  std_logic);
end port_axi_mailbox;

architecture rtl of port_axi_mailbox is

-- Compare AXI address against configured address, with wildcard option.
function address_match(addr : std_logic_vector) return std_logic is
begin
    if (REG_ADDR < 0) then
        return '1';     -- Match any address
    elsif (addr = i2s(REG_ADDR, ADDR_WIDTH)) then
        return '1';     -- Match specific address
    else
        return '0';     -- No match
    end if;
end function;

-- Internal reset signal
signal port_areset  : std_logic;
signal port_reset_p : std_logic;

-- Ethernet frame adjustments (e.g., removing FCS)
signal rd_adj_data  : std_logic_vector(7 downto 0);
signal rd_adj_last  : std_logic;
signal rd_adj_valid : std_logic;
signal rd_adj_ready : std_logic;

-- Buffer one AXI-write transaction.
signal prewr_valid  : std_logic := '0';
signal prewr_ready  : std_logic := '0';
signal wr_gotaddr   : std_logic := '0';
signal wr_gotdata   : std_logic := '0';
signal wr_exec      : std_logic := '0';
signal wr_valid     : std_logic := '0';
signal wr_rpend     : std_logic := '0';
signal wr_valid2    : std_logic := '0';
signal wr_addr      : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
signal wr_data      : std_logic_vector(31 downto 0) := (others => '0');
signal wr_opcode    : integer range 0 to 255 := 0;

-- Buffer one read transaction.
signal rd_buffer    : std_logic_vector(31 downto 0) := (others => '0');
signal rd_pending   : std_logic := '0';
signal rd_avail     : std_logic := '0';

-- Parse and execute commands from CPU.
signal cmd_reset_p  : std_logic := '1';
signal cmd_data     : std_logic_vector(7 downto 0) := (others => '0');
signal cmd_last     : std_logic := '0';
signal cmd_valid    : std_logic := '0';
signal cmd_ready    : std_logic := '0';

begin

-- Drive simple port outputs.
rx_data.clk     <= axi_clk;
rx_data.rxerr   <= '0';
rx_data.rate    <= get_rate_word(1);
rx_data.reset_p <= port_reset_p;

tx_ctrl.clk     <= axi_clk;
tx_ctrl.txerr   <= '0';
tx_ctrl.reset_p <= port_reset_p;

-- AXI command responses are always "OK" ('00').
axi_rresp   <= "00";
axi_bresp   <= "00";

-- Hold port reset at least N clock cycles.
port_areset <= cmd_reset_p or not axi_aresetn;

u_rst : sync_reset
    port map(
    in_reset_p  => port_areset,
    out_reset_p => port_reset_p,
    out_clk     => axi_clk);

-- Optionally append and zero-pad data before sending.
u_wr_adj : entity work.eth_frame_adjust
    generic map(
    MIN_FRAME   => MIN_FRAME,
    APPEND_FCS  => APPEND_FCS,
    STRIP_FCS   => false)
    port map(
    in_data     => cmd_data,
    in_last     => cmd_last,
    in_valid    => cmd_valid,
    in_ready    => cmd_ready,
    out_data    => rx_data.data,
    out_last    => rx_data.last,
    out_valid   => rx_data.write,
    out_ready   => '1',
    clk         => axi_clk,
    reset_p     => port_reset_p);

-- Optionally strip FCS from received data.
u_rd_adj : entity work.eth_frame_adjust
    generic map(
    MIN_FRAME   => MIN_FRAME,
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
    clk         => axi_clk,
    reset_p     => port_reset_p);

-- Buffer one AXI-write transaction.
-- Some complexity here, since we must be able to accept either
-- data-before-address or address-before-data without blocking.
axi_awready <= not wr_gotaddr;
axi_wready  <= not wr_gotdata;
axi_bvalid  <= wr_rpend and axi_aresetn;
prewr_valid <= (wr_gotaddr or axi_awvalid)
           and (wr_gotdata or axi_wvalid);
prewr_ready <= (cmd_ready or not wr_valid)
           and (axi_bready or not wr_rpend);
wr_exec     <= prewr_valid and prewr_ready;

p_axi_wr : process(axi_clk)
begin
    if rising_edge(axi_clk) then
        if (axi_awvalid = '1' and wr_gotaddr = '0') then
            -- Latch new address when ready.
            wr_addr <= axi_awaddr;
        end if;

        if (axi_wvalid = '1' and wr_gotdata = '0') then
            -- Latch new data when ready.
            wr_data <= axi_wdata;
            -- Note: Ignore WSTRB, except for warnings in simulation.
            assert (axi_wstrb = "1111")
                report "Register writes must be atomic." severity warning;
        end if;

        -- Update the pending / hold flags for address and data.
        if (axi_aresetn = '0' or wr_exec = '1') then
            -- Clear pending flags on execution or reset.
            wr_gotaddr <= '0';
            wr_gotdata <= '0';
        else
            -- Otherwise, set and hold flags as we receive each item.
            wr_gotaddr <= wr_gotaddr or axi_awvalid;
            wr_gotdata <= wr_gotdata or axi_wvalid;
        end if;

        -- Update the write-valid flag.
        if (axi_aresetn = '0') then
            wr_valid <= '0';    -- Global reset
        elsif (wr_exec = '1') then
            wr_valid <= '1';    -- New data received
        elsif (cmd_valid = '0' or cmd_ready = '1') then
            wr_valid <= '0';    -- Command executed
        end if;

        -- Update the response-pending flag.
        if (axi_aresetn = '0') then
            wr_rpend <= '0';    -- Global reset
        elsif (wr_exec = '1') then
            wr_rpend <= '1';    -- New data received
        elsif (axi_bready = '1') then
            wr_rpend <= '0';    -- Response accepted
        end if;
    end if;
end process;

-- Parse and execute the buffered write command.
-- (Combinational logic, so we don't need a FIFO.)
wr_valid2   <= wr_valid and address_match(wr_addr);
wr_opcode   <= U2I(wr_data(31 downto 24));
cmd_data    <= wr_data(7 downto 0);
cmd_last    <= bool2bit(wr_opcode = 3);
cmd_valid   <= wr_valid2 and bool2bit(wr_opcode = 2 or wr_opcode = 3);
cmd_reset_p <= wr_valid2 and bool2bit(wr_opcode = 255);

-- Buffer one read transaction, and assert interrupt flag
-- whenever received data is available to be read.
-- (Note: Read value for CPU is valid even if FIFO is empty.)
axi_arready  <= axi_rready or not rd_pending;
axi_rdata    <= rd_buffer;
axi_rvalid   <= rd_pending and axi_aresetn;
rd_adj_ready <= (axi_arvalid and address_match(axi_araddr))
            and (axi_rready or not rd_pending);
irq_out      <= rd_avail;

p_axi_rd : process(axi_clk)
begin
    if rising_edge(axi_clk) then
        -- Update the read-pending flag.
        if (axi_aresetn = '0') then
            rd_pending <= '0';  -- Interface reset
        elsif (rd_adj_ready = '1') then
            rd_pending <= '1';  -- Start of new read transaction
        elsif (axi_rready = '1') then
            rd_pending <= '0';  -- Reply consumed
        end if;

        -- Latch output word to ensure it remains stable.
        if (rd_adj_ready = '1') then
            rd_buffer <= rd_adj_valid & rd_adj_last & "0000000000000000000000" & rd_adj_data;
        end if;

        -- Buffer helps with routing and timing.
        rd_avail <= rd_adj_valid;
    end if;
end process;

end rtl;
