--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation
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
-- "MailMap" port for use with ConfigBus
--
-- This block acts as a virtual internal port, connecting an Ethernet
-- switch core to a memory-mapped interface suitable for integrating
-- a soft-core microcontroller. (e.g., LEON, Microblaze, etc.) or
-- any other ConfigBus host.
--
-- It is similar to "port_mailbox" but makes the entire frame available
-- as a memory-mapped array, rather than reading and writing a byte at
-- at a time through a single register.  This requires additional BRAM
-- but offers substantially improved performance.
--
-- On the software side, the memory-mapped array can be treated as any
-- regular C/C++ data structure.  Byte-enable strobes are followed.
-- The array can be configured for big-endian or little-endian mode.
--
-- Jumbo frames are not supported.  If received, they are discarded.
--
-- After sending each frame, that buffer is "busy" as it is tranferred
-- to the underlying Ethernet port.  This occurs at a fixed rate of
-- 1 byte per clock cycle; for a 100 MHz clock, a max-length frame
-- is transferred in just 15 microseconds.  During this phase, any
-- writes to the transmit buffer are ignored.
--
-- The transmit buffer can be configured as read-write (default) or
-- write-only.  The latter may save resources on some FPGA platforms,
-- depending on whether dual-port block-RAM can simultaneously read
-- or write on a single port.
--
-- Memory is mapped as follows:
--  * Reg 0-399:    Received frame contents (read-only)
--  * Reg 400-509:  Reserved
--  * Reg 510:      Interrupt control (see cfgbus_common::cfgbus_interrupt)
--  * Reg 511:      Received frame control (read-write):
--                  Read = Current frame length, in bytes. (0 = Empty)
--                  Write = Discard buffer and begin reading next frame.
--  * Reg 512-911:  Transmit frame buffer (read-write or write-only)
--  * Reg 912-1022: Reserved
--  * Reg 1023:     Transmit frame control (read-write)
--                  Write = Set frame length to be sent, in bytes.
--                  Read = Busy (1) or idle (0).
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.cfgbus_common.all;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity port_mailmap is
    generic (
    DEV_ADDR    : integer;              -- Peripheral address (-1 = any)
    BIG_ENDIAN  : boolean := false;     -- Big-endian byte order?
    TX_READBACK : boolean := true;      -- Enable readback of Tx buffer?
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
end port_mailmap;

architecture port_mailmap of port_mailmap is

-- Each BRAM is 512 words x 32 bits = 2 kiB.
constant RAM_WORDS : integer := 512;
constant RAM_BYTES : integer := 4;
constant RAM_ADDRW : integer := log2_ceil(RAM_WORDS);
subtype ram_addr is unsigned(RAM_ADDRW-1 downto 0);
subtype ram_bidx is integer range 0 to RAM_BYTES-1;
subtype len_word is unsigned(10 downto 0);

-- Convert sequential byte-index to word-address and lane-index.
function get_addr(len : len_word) return ram_addr is
    constant idx : natural := to_integer(len) / RAM_BYTES;
begin
    return to_unsigned(idx mod RAM_WORDS, RAM_ADDRW);
end function;

function get_lane(len : len_word) return ram_bidx is
    constant idx : natural := to_integer(len);
begin
    if (BIG_ENDIAN) then
        return (RAM_BYTES-1) - (idx mod RAM_BYTES);
    else
        return (idx mod RAM_BYTES);
    end if;
end function;

-- Internal reset signal
signal port_areset  : std_logic;
signal port_reset_p : std_logic;

-- Receive datapath and control.
signal rx_raw_data  : byte_t;
signal rx_raw_last  : std_logic;
signal rx_raw_valid : std_logic;
signal rx_raw_ready : std_logic;
signal rx_adj_data  : byte_t;
signal rx_adj_last  : std_logic;
signal rx_adj_valid : std_logic;
signal rx_adj_ready : std_logic;
signal rx_ctrl_wren : cfgbus_wstrb := (others => '0');
signal rx_ctrl_len  : len_word := (others => '0');
signal rx_ctrl_rcvd : std_logic := '0';
signal rx_wr_addr   : ram_addr;

-- Transmit datapath and control.
signal tx_ctrl_len  : len_word := (others => '0');
signal tx_ctrl_busy : std_logic := '0';
signal tx_rd_data   : cfgbus_word := (others => '0');
signal tx_rd_addr   : ram_addr := (others => '0');
signal tx_rd_bidx   : ram_bidx := 0;
signal tx_rd_last   : std_logic := '0';
signal tx_rd_next   : std_logic := '0';
signal tx_fifo_data : byte_t := (others => '0');
signal tx_fifo_last : std_logic := '0';
signal tx_fifo_wr   : std_logic := '0';
signal tx_fifo_ok   : std_logic;
signal tx_raw_data  : byte_t := (others => '0');
signal tx_raw_last  : std_logic := '0';
signal tx_raw_valid : std_logic := '0';
signal tx_raw_ready : std_logic;
signal tx_adj_data  : byte_t;
signal tx_adj_last  : std_logic;
signal tx_adj_valid : std_logic;
signal tx_adj_ready : std_logic;

-- ConfigBus interface.
signal cfg_addr     : ram_addr;
signal cfg_wren     : std_logic;
signal cfg_wstrb    : cfgbus_wstrb;
signal cfg_txdata   : cfgbus_word := (others => '0');
signal cfg_rxdata   : cfgbus_word := (others => '0');
signal cfg_status   : cfgbus_word := (others => '0');
signal cfg_txread   : std_logic := '0';
signal cfg_rxread   : std_logic := '0';
signal cfg_regread  : std_logic := '0';
signal cfg_clr_rx   : std_logic := '0';
signal cfg_send_tx  : std_logic := '0';
signal cfg_send_len : len_word := (others => '0');
signal irq_toggle   : std_logic := '0';
signal irq_ack      : cfgbus_ack;
signal reg_ack      : cfgbus_ack;

begin

-- Data coming from the Ethernet switch. (Note Tx/Rx swap)
rx_raw_data     <= tx_data.data;
rx_raw_last     <= tx_data.last;
rx_raw_valid    <= tx_data.valid;
tx_ctrl.ready   <= rx_raw_ready;
tx_ctrl.clk     <= cfg_cmd.clk;
tx_ctrl.txerr   <= '0';
tx_ctrl.reset_p <= port_reset_p;

-- Hold port reset at least N clock cycles.
u_rst : sync_reset
    port map(
    in_reset_p  => cfg_cmd.reset_p,
    out_reset_p => port_reset_p,
    out_clk     => cfg_cmd.clk);

-- Optionally strip FCS from incoming packets.
u_rx_adj : entity work.eth_frame_adjust
    generic map(
    MIN_FRAME   => 0,
    APPEND_FCS  => false,
    STRIP_FCS   => STRIP_FCS)
    port map(
    in_data     => rx_raw_data,
    in_last     => rx_raw_last,
    in_valid    => rx_raw_valid,
    in_ready    => rx_raw_ready,
    out_data    => rx_adj_data,
    out_last    => rx_adj_last,
    out_valid   => rx_adj_valid,
    out_ready   => rx_adj_ready,
    clk         => cfg_cmd.clk,
    reset_p     => port_reset_p);

-- Accept data whenever we're between packets.
rx_adj_ready <= not rx_ctrl_rcvd;

-- Controller for writing received data to the working buffer.
p_rx_ctrl : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        if (port_reset_p = '1' or cfg_clr_rx = '1') then
            -- Reset buffer contents and begin storing new data.
            rx_ctrl_len  <= (others => '0');
            rx_ctrl_rcvd <= '0';
        elsif (rx_adj_valid = '1' and rx_adj_ready = '1') then
            -- Accept new data and update state.
            if (rx_adj_last = '0') then
                -- Receive next byte.
                rx_ctrl_len  <= rx_ctrl_len + 1;
                rx_ctrl_rcvd <= '0';
            elsif (rx_ctrl_len < MAX_FRAME_BYTES) then
                -- Receive final byte.
                rx_ctrl_len  <= rx_ctrl_len + 1;
                rx_ctrl_rcvd <= '1';
                irq_toggle   <= not irq_toggle;
            else
                -- Packet too long; discard.
                rx_ctrl_len  <= (others => '0');
                rx_ctrl_rcvd <= '0';
            end if;
        end if;
    end if;
end process;

-- Convert Tx/Rx/ConfigBus state to RAM addresses and write-enables.
cfg_addr    <= to_unsigned(cfg_cmd.regaddr mod RAM_WORDS, RAM_ADDRW);
cfg_wren    <= bool2bit(cfgbus_wrcmd(cfg_cmd, DEV_ADDR)) and not tx_ctrl_busy;
rx_wr_addr  <= get_addr(rx_ctrl_len);
tx_rd_addr  <= get_addr(tx_ctrl_len);
gen_lane : for n in 0 to RAM_BYTES-1 generate
    cfg_wstrb(n)    <= cfg_wren and cfg_cmd.wstrb(n);
    rx_ctrl_wren(n) <= rx_adj_valid and rx_adj_ready and bool2bit(n = get_lane(rx_ctrl_len));
end generate;

-- Platform-specific dual-port block RAM.
gen_dpram : for n in 0 to 3 generate
    u_rxbuff : dpram
        generic map(
        AWIDTH  => RAM_ADDRW,
        DWIDTH  => 8,
        TRIPORT => false)
        port map(
        wr_clk  => cfg_cmd.clk,
        wr_addr => rx_wr_addr,
        wr_en   => rx_ctrl_wren(n),
        wr_val  => rx_adj_data,
        wr_rval => open,
        rd_clk  => cfg_cmd.clk,
        rd_addr => cfg_addr,
        rd_val  => cfg_rxdata(8*n+7 downto 8*n));

    u_txbuff : dpram
        generic map(
        AWIDTH  => RAM_ADDRW,
        DWIDTH  => 8,
        TRIPORT => TX_READBACK)
        port map(
        wr_clk  => cfg_cmd.clk,
        wr_addr => cfg_addr,
        wr_en   => cfg_wstrb(n),
        wr_val  => cfg_cmd.wdata(8*n+7 downto 8*n),
        wr_rval => cfg_txdata(8*n+7 downto 8*n),
        rd_clk  => cfg_cmd.clk,
        rd_addr => tx_rd_addr,
        rd_val  => tx_rd_data(8*n+7 downto 8*n));
end generate;

-- Transmit controller reads buffer on demand.
p_tx_ctrl : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- On demand, scan read address from 0 to N-1.
        if (port_reset_p = '1') then
            -- Global reset.
            tx_ctrl_len  <= (others => '0');
            tx_ctrl_busy <= '0';
        elsif (cfg_send_tx = '1' and cfg_send_len > 0) then
            -- Begin readout.
            tx_ctrl_len  <= (others => '0');
            tx_ctrl_busy <= '1';
        elsif (tx_ctrl_busy = '1' and tx_fifo_ok = '1') then
            -- Continue readout.
            tx_ctrl_len  <= tx_ctrl_len + 1;
            tx_ctrl_busy <= bool2bit(tx_ctrl_len + 1 < cfg_send_len);
        end if;

        -- One-cycle delay for reading the BRAM.
        tx_rd_next <= tx_ctrl_busy and tx_fifo_ok;
        tx_rd_bidx <= get_lane(tx_ctrl_len);
        tx_rd_last <= bool2bit(tx_ctrl_len + 1 = cfg_send_len);

        -- Extract the appropriate byte from the readout.
        tx_fifo_data  <= tx_rd_data(8*tx_rd_bidx+7 downto 8*tx_rd_bidx);
        tx_fifo_last  <= tx_rd_last;
        tx_fifo_wr    <= tx_rd_next;
    end if;
end process;

-- Small FIFO for flow-control.
u_tx_fifo : entity work.fifo_smol_sync
    generic map(IO_WIDTH => 8)
    port map(
    in_data     => tx_fifo_data,
    in_last     => tx_fifo_last,
    in_write    => tx_fifo_wr,
    out_data    => tx_raw_data,
    out_last    => tx_raw_last,
    out_valid   => tx_raw_valid,
    out_read    => tx_raw_ready,
    fifo_hempty => tx_fifo_ok,
    clk         => cfg_cmd.clk,
    reset_p     => port_reset_p);

-- Optionally append and zero-pad data before sending.
u_tx_adj : entity work.eth_frame_adjust
    generic map(
    MIN_FRAME   => MIN_FRAME,
    APPEND_FCS  => APPEND_FCS,
    STRIP_FCS   => false)
    port map(
    in_data     => tx_raw_data,
    in_last     => tx_raw_last,
    in_valid    => tx_raw_valid,
    in_ready    => tx_raw_ready,
    out_data    => tx_adj_data,
    out_last    => tx_adj_last,
    out_valid   => tx_adj_valid,
    out_ready   => tx_adj_ready,
    clk         => cfg_cmd.clk,
    reset_p     => port_reset_p);

-- Data going to the Ethernet switch. (Note Tx/Rx swap)
rx_data.clk     <= cfg_cmd.clk;
rx_data.data    <= tx_adj_data;
rx_data.last    <= tx_adj_last;
rx_data.write   <= tx_adj_valid;
tx_adj_ready    <= '1';
rx_data.rxerr   <= '0';
rx_data.rate    <= get_rate_word(1);
rx_data.status  <= (0 => port_reset_p, others => '0');
rx_data.reset_p <= port_reset_p;

-- Interrupt control uses the standard ConfigBus primitive.
u_irq : cfgbus_interrupt
    generic map(
    DEVADDR     => DEV_ADDR,
    REGADDR     => 510)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => irq_ack,
    ext_toggle  => irq_toggle);

-- Combine ConfigBus replies from each source.
reg_ack <= cfgbus_reply(cfg_status) when (cfg_regread = '1')
      else cfgbus_reply(cfg_txdata) when (cfg_txread = '1')
      else cfgbus_reply(cfg_rxdata) when (cfg_rxread = '1')
      else cfgbus_idle;

cfg_ack <= cfgbus_merge(irq_ack, reg_ack);

-- ConfigBus interface.
p_cfgbus : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- Set defaults for various strobes.
        cfg_txread  <= '0';
        cfg_rxread  <= '0';
        cfg_regread <= '0';
        cfg_status  <= (others => '0');
        cfg_clr_rx  <= '0';
        cfg_send_tx <= '0';

        -- Handle writes to the conrol registers.
        if (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, 511)) then
            cfg_clr_rx   <= '1';
        elsif (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, 1023) and tx_ctrl_busy = '0') then
            cfg_send_tx  <= '1';
            cfg_send_len <= unsigned(cfg_cmd.wdata(cfg_send_len'range));
        end if;

        -- Handle reads from any register.
        if (cfgbus_rdcmd(cfg_cmd, DEV_ADDR, 511)) then
            if (rx_ctrl_rcvd = '1') then
                cfg_status <= std_logic_vector(resize(rx_ctrl_len, 32));
            else
                cfg_status <= (others => '0');
            end if;
            cfg_regread <= '1';
        elsif (cfgbus_rdcmd(cfg_cmd, DEV_ADDR, 1023)) then
            cfg_status  <= (0 => tx_ctrl_busy, others => '0');
            cfg_regread <= '1';
        elsif (cfgbus_rdcmd(cfg_cmd, DEV_ADDR)) then
            cfg_rxread <= bool2bit(cfg_cmd.regaddr <  510);
            cfg_txread <= bool2bit(cfg_cmd.regaddr >= 512);
        end if;
    end if;
end process;

end port_mailmap;
