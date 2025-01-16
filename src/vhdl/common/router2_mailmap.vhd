--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Memory-mapped mailbox for the IPv4 router
--
-- The "router2" system uses a combination of gateware and software.
-- Routine forwarding is defined in VHDL to provide the throughput, but
-- more complex or time-delayed operations are offloaded to software.
-- This block provides the I/O for that offload function, using a
-- memory-mapped FIFO that can be read using ConfigBus.
--
-- This block is similar to the "port_mailmap", making the entire
-- incoming or outgoing frame available as a memory-mapped array.
-- This requires additional BRAM but offers much better performance
-- than approaches that read and write a single byte at a time.
--
-- Jumbo frames are not supported.  If received, they are discarded.
-- PTP timestamps are not currently supported.
--
-- After requesting frame transmission, the transmit buffer is busy
-- for up to 400 clock cycles as data is copied to the output queue.
-- During this phase, any writes to the transmit buffer are ignored.
--
-- The transmit buffer can be configured as read-write (default) or
-- write-only.  The latter may save resources on some FPGA platforms,
-- depending on whether dual-port block-RAM can simultaneously read
-- or write on a single port.
--
-- Register addresses are defined in "router2_common.vhd":
--  RT_ADDR_TXRX_DAT to RT_ADDR_TXRX_DAT + 399:
--      Read: Received frame contents as a memory-mapped array.
--      Write: Transmit frame contents as a memory-mapped array.
--  RT_ADDR_RX_IRQ (read-write): Receive interrupt control
--      Interrupt controller, see "cfgbus_common.vhd".
--      Triggers an interrupt when a new frame is ready to be read.
--  RT_ADDR_RX_CTRL (read-write): Receive buffer control
--      Read for status:
--          Bits 31-24: Reserved
--          Bits 23-16: Source port index
--          Bits 15-00: Current frame length, in bytes (0 = Empty)
--      Write any value to discard buffer and begin reading the next frame.
--  RT_ADDR_TX_MASK (read-write): Transmit port-mask
--      Sets the destination mask for the next transmit frame.
--      Update this register before writing to RT_ADDR_TX_CTRL.
--  RT_ADDR_TX_CTRL (read-write): Transmit buffer control
--      Read for status:
--          Bit 31:    Busy (1) or idle (0)
--          Bit 30-00: Reserved
--      Write to set frame length, in bytes.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.cfgbus_common.all;
use     work.eth_frame_common.all;
use     work.router2_common.all;

entity router2_mailmap is
    generic (
    DEVADDR     : integer;              -- ConfigBus address
    IO_BYTES    : positive;             -- I/O width in bytes
    PORT_COUNT  : positive;             -- Number of router ports
    IBUF_KBYTES : positive := 2;        -- Input buffer size in kilobytes
    OBUF_KBYTES : positive := 2;        -- Output buffer size in kilobytes
    BIG_ENDIAN  : boolean := false;     -- Byte order of ConfigBus host
    VLAN_ENABLE : boolean := false);    -- Enable VLAN support?
    port (
    -- Input stream and metadata using a simple write-strobe.
    rx_clk      : in  std_logic;
    rx_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    rx_nlast    : in  integer range 0 to IO_BYTES;
    rx_psrc     : in  integer range 0 to PORT_COUNT-1;
    rx_vtag     : in  vlan_hdr_t := VHDR_NONE;
    rx_write    : in  std_logic;
    rx_commit   : in  std_logic;
    rx_revert   : in  std_logic;

    -- Output stream and metadata using AXI-stream flow control.
    tx_clk      : in  std_logic;
    tx_data     : out std_logic_vector(8*IO_BYTES-1 downto 0);
    tx_nlast    : out integer range 0 to IO_BYTES;
    tx_valid    : out std_logic;
    tx_ready    : in  std_logic;
    tx_keep     : out std_logic_vector(PORT_COUNT-1 downto 0);
    tx_vtag     : out vlan_hdr_t;

    -- ConfigBus interface.
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack);
end router2_mailmap;

architecture router2_mailmap of router2_mailmap is

-- Each memory-mapped BRAM is 512 words x 32 bits = 2 kiB.
constant RAM_WORDS : integer := 512;
constant RAM_BYTES : integer := 4;
constant RAM_ADDRW : integer := log2_ceil(RAM_WORDS);
subtype ram_addr is unsigned(RAM_ADDRW-1 downto 0);
subtype ram_bidx is integer range 0 to RAM_BYTES-1;
subtype len_word is unsigned(10 downto 0);
subtype half_word is std_logic_vector(15 downto 0);

-- Test if a given read or write is in the given memory-map range.
function cfgbus_rdcmd_range(cmd: cfgbus_cmd; devaddr, regbase: integer) return boolean is
begin
    return cfgbus_rdcmd(cmd, devaddr)
        and (cmd.regaddr >= regbase)
        and (cmd.regaddr <  regbase + 400);
end function;

function cfgbus_wrcmd_range(cmd: cfgbus_cmd; devaddr, regbase: integer) return boolean is
begin
    return cfgbus_wrcmd(cmd, devaddr)
        and (cmd.regaddr >= regbase)
        and (cmd.regaddr <  regbase + 400);
end function;

-- Receive datapath.
signal rx_pkt_meta  : cfgbus_word;
signal rx_buf_meta  : cfgbus_word;
signal rx_vtg_meta  : half_word;
signal rx_cpu_meta  : half_word := (others => '0');
signal rx_cpu_len   : half_word := (others => '0');
signal rx_reset     : std_logic;

signal rx_buf_data  : cfgbus_word;
signal rx_buf_nlast : integer range 0 to 4;
signal rx_buf_valid : std_logic;
signal rx_buf_ready : std_logic := '1';

signal rx_vtg_data  : cfgbus_word;
signal rx_vtg_nlast : integer range 0 to 4;
signal rx_vtg_valid : std_logic;
signal rx_vtg_ready : std_logic := '1';

signal rx_cpy_data  : cfgbus_word;
signal rx_cpy_addr  : ram_addr := (others => '0');
signal rx_cpy_done  : std_logic := '0';
signal rx_cpy_wren  : std_logic;
signal rx_irq_tog   : std_logic := '0';

-- Transmit datapath.
signal tx_cpu_meta  : cfgbus_word := (others => '0');
signal tx_buf_meta  : std_logic_vector(47 downto 0);
signal tx_out_meta  : std_logic_vector(47 downto 0);
signal tx_reset     : std_logic;

signal tx_raw_data  : cfgbus_word;
signal tx_cpy_data  : cfgbus_word;
signal tx_cpy_addr  : ram_addr := (others => '0');
signal tx_cpy_write : std_logic := '0';
signal tx_cpy_nlast : integer range 0 to 4 := 0;
signal tx_cpy_last  : std_logic := '0';
signal tx_cpy_rem   : len_word := (others => '0');
signal tx_cpy_busy  : std_logic := '0';

signal tx_vtg_data  : cfgbus_word;
signal tx_vtg_write : std_logic;
signal tx_vtg_nlast : integer range 0 to 4;
signal tx_vtg_last  : std_logic;
signal tx_vtg_vtag  : vlan_hdr_t := (others => '0');

-- ConfigBus interface.
signal cfg_acks     : cfgbus_ack_array(0 to 2) := (others => cfgbus_idle);
signal cfg_addr     : ram_addr;
signal cfg_reg_read : std_logic := '0';
signal cfg_rx_data  : cfgbus_word;
signal cfg_rx_read  : std_logic := '0';
signal cfg_rx_start : std_logic := '0';
signal cfg_status   : cfgbus_word := (others => '0');
signal cfg_tx_len   : len_word := (others => '0');
signal cfg_tx_start : std_logic := '0';
signal cfg_tx_write : std_logic;
signal cfg_wstrb    : cfgbus_wstrb;

begin

-- Top-level I/O drivers.
rx_pkt_meta <= rx_vtag & i2s(rx_psrc, 16);
tx_keep     <= tx_out_meta(PORT_COUNT-1 downto 0);
tx_vtag     <= tx_out_meta(47 downto 32);

-- Raw input is written to a receive queue.  By design, this FIFO will
-- overflow if the CPU isn't keeping up.  Commit/revert allows upstream
-- to defer the forward-vs-offload decision until end-of-frame.
-- TODO: Do we need to strip FCS before writing to this FIFO?
u_rx_fifo : entity work.fifo_packet
    generic map(
    INPUT_BYTES     => IO_BYTES,
    OUTPUT_BYTES    => RAM_BYTES,
    BUFFER_KBYTES   => IBUF_KBYTES,
    META_WIDTH      => 32)
    port map(
    in_clk          => rx_clk,
    in_data         => rx_data,
    in_nlast        => rx_nlast,
    in_pkt_meta     => rx_pkt_meta,
    in_last_commit  => rx_commit,
    in_last_revert  => rx_revert,
    in_write        => rx_write,
    out_clk         => cfg_cmd.clk,
    out_data        => rx_buf_data,
    out_nlast       => rx_buf_nlast,
    out_pkt_meta    => rx_buf_meta,
    out_valid       => rx_buf_valid,
    out_ready       => rx_buf_ready,
    out_reset       => rx_reset,
    reset_p         => cfg_cmd.reset_p);

-- Optionally insert VLAN tags into the received stream.
-- (Software interface requires in-band signaling.)
gen_vrx1 : if VLAN_ENABLE generate
    u_vtag : entity work.eth_frame_vtag
        generic map(
        DEV_ADDR    => CFGBUS_ADDR_NONE,
        REG_ADDR    => CFGBUS_ADDR_NONE,
        IO_BYTES    => 4,
        VTAG_POLICY => VTAG_MANDATORY)
        port map(
        in_data     => rx_buf_data,
        in_vtag     => rx_buf_meta(31 downto 16),
        in_nlast    => rx_buf_nlast,
        in_valid    => rx_buf_valid,
        in_ready    => rx_buf_ready,
        out_data    => rx_vtg_data,
        out_error   => open,
        out_nlast   => rx_vtg_nlast,
        out_valid   => rx_vtg_valid,
        out_ready   => rx_vtg_ready,
        clk         => cfg_cmd.clk,
        reset_p     => cfg_cmd.reset_p);
end generate;

gen_vrx0 : if not VLAN_ENABLE generate
    rx_vtg_data  <= rx_buf_data;
    rx_vtg_nlast <= rx_buf_nlast;
    rx_vtg_valid <= rx_buf_valid;
    rx_buf_ready <= rx_vtg_ready;
end generate;

-- On request, copy one packet from the Rx-FIFO to the memory-map buffer.
-- Note: FIFO output is always big-endian, swap as needed for memory-map buffer.
tx_cpy_data <= tx_raw_data when BIG_ENDIAN else endian_swap(tx_raw_data);
rx_cpy_data <= rx_vtg_data when BIG_ENDIAN else endian_swap(rx_vtg_data);
rx_cpy_wren <= rx_vtg_valid and rx_vtg_ready;
rx_vtg_ready <= not (rx_cpy_done or rx_reset or cfg_rx_start);

p_rx_copy : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- Copy controller counts bytes and sets write address.
        if (rx_reset = '1' or cfg_rx_start = '1') then
            -- Reset address, ready to copy once FIFO has data.
            rx_cpy_done  <= '0';
            rx_cpy_addr  <= (others => '0');
        elsif (rx_cpy_wren = '1') then
            -- Continue copying data until end-of-frame.
            rx_cpy_done  <= bool2bit(rx_buf_nlast > 0);
            rx_cpy_addr  <= rx_cpy_addr + 1;
        end if;

        -- At start of frame, latch packet metadata directly from buffer.
        -- (There's no easy way to plumb metadata through eth_frame_vtag,
        --  and worst-case min/max delay are still packet-aligned.)
        if (rx_cpy_wren = '1' and rx_cpy_addr = 0) then
            rx_cpu_meta <= rx_buf_meta(15 downto 0);
        end if;

        -- At end of frame, note length and request interrupt.
        if (rx_cpy_wren = '1' and rx_vtg_nlast > 0) then
            rx_cpu_len  <= i2s(4*to_integer(rx_cpy_addr) + rx_vtg_nlast, 16);
            rx_irq_tog  <= not rx_irq_tog;
        end if;
    end if;
end process;

-- Instantiate each memory-map buffer.
u_rx_mmap : dpram
    generic map(
    AWIDTH  => RAM_ADDRW,
    DWIDTH  => RAM_BYTES*8,
    TRIPORT => false)
    port map(
    wr_clk  => cfg_cmd.clk,
    wr_addr => rx_cpy_addr,
    wr_en   => rx_cpy_wren,
    wr_val  => rx_cpy_data,
    wr_rval => open,
    rd_clk  => cfg_cmd.clk,
    rd_addr => cfg_addr,
    rd_val  => cfg_rx_data);

gen_tx_mmap : for n in 0 to RAM_BYTES-1 generate
    u_tx_mmap : dpram
        generic map(
        AWIDTH  => RAM_ADDRW,
        DWIDTH  => 8,
        TRIPORT => false)
        port map(
        wr_clk  => cfg_cmd.clk,
        wr_addr => cfg_addr,
        wr_en   => cfg_wstrb(n),
        wr_val  => cfg_cmd.wdata(8*n+7 downto 8*n),
        rd_clk  => cfg_cmd.clk,
        rd_addr => tx_cpy_addr,
        rd_val  => tx_raw_data(8*n+7 downto 8*n));
end generate;

-- On request, copy the memory-map buffer to the Tx-FIFO.
p_tx_copy : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- Read control:
        if (tx_reset = '1') then
            -- Reset to the idle state.
            tx_cpy_addr <= (others => '0');
            tx_cpy_rem  <= (others => '0');
            tx_cpy_busy <= '0';
        elsif (cfg_tx_start = '1') then
            -- On command, begin copying data.
            tx_cpy_addr <= (others => '0');
            tx_cpy_rem  <= cfg_tx_len;
            tx_cpy_busy <= '1';
        elsif (tx_cpy_rem > 4) then
            -- Continue copying until end-of-frame.
            tx_cpy_addr <= tx_cpy_addr + 1;
            tx_cpy_rem  <= tx_cpy_rem - 4;
            tx_cpy_busy <= '1';
        else
            -- Reset to the idle state.
            tx_cpy_addr <= (others => '0');
            tx_cpy_rem  <= (others => '0');
            tx_cpy_busy <= '0';
        end if;

        -- Matched-delay for address vs, data signals.
        tx_cpy_write <= tx_cpy_busy;
        if (tx_cpy_rem > 4) then
            tx_cpy_nlast <= 0;
            tx_cpy_last  <= '0';
        else
            tx_cpy_nlast <= to_integer(tx_cpy_rem);
            tx_cpy_last  <= '1';
        end if;
    end if;
end process;

-- Optionally remove VLAN tags from the outgoing stream.
-- (Software interface requires in-band signaling.)
gen_vtx1 : if VLAN_ENABLE generate
    u_vstrip : entity work.eth_frame_vstrip
        generic map(
        DEVADDR     => CFGBUS_ADDR_NONE,
        REGADDR     => CFGBUS_ADDR_NONE,
        IO_BYTES    => 4,
        VTAG_POLICY => VTAG_ADMIT_ALL)
        port map(
        in_data     => tx_cpy_data,
        in_write    => tx_cpy_write,
        in_nlast    => tx_cpy_nlast,
        in_commit   => tx_cpy_last,
        in_revert   => '0',
        in_error    => '0',
        out_data    => tx_vtg_data,
        out_vtag    => tx_vtg_vtag,
        out_write   => tx_vtg_write,
        out_nlast   => tx_vtg_nlast,
        out_commit  => tx_vtg_last,
        out_revert  => open,
        out_error   => open,
        clk         => cfg_cmd.clk,
        reset_p     => cfg_cmd.reset_p);
end generate;

gen_vtx0 : if not VLAN_ENABLE generate
    tx_vtg_data  <= tx_cpy_data;
    tx_vtg_write <= tx_cpy_write;
    tx_vtg_nlast <= tx_cpy_nlast;
    tx_vtg_last  <= tx_cpy_last;
    tx_vtg_vtag  <= (others => '0');
end generate;

-- Transmit FIFO for clock-crossing and width conversion.
tx_buf_meta <= tx_vtg_vtag & tx_cpu_meta;

u_tx_fifo : entity work.fifo_packet
    generic map(
    INPUT_BYTES     => RAM_BYTES,
    OUTPUT_BYTES    => IO_BYTES,
    BUFFER_KBYTES   => OBUF_KBYTES,
    META_WIDTH      => tx_out_meta'length)
    port map(
    in_clk          => cfg_cmd.clk,
    in_data         => tx_vtg_data,
    in_nlast        => tx_vtg_nlast,
    in_pkt_meta     => tx_buf_meta,
    in_last_commit  => tx_vtg_last,
    in_last_revert  => '0',
    in_write        => tx_vtg_write,
    in_reset        => tx_reset,
    out_clk         => tx_clk,
    out_data        => tx_data,
    out_nlast       => tx_nlast,
    out_pkt_meta    => tx_out_meta,
    out_valid       => tx_valid,
    out_ready       => tx_ready,
    reset_p         => cfg_cmd.reset_p);

-- Combinational logic for ConfigBus access to the memory-map blocks.
cfg_addr <= to_unsigned((cfg_cmd.regaddr - RT_ADDR_TXRX_DAT) mod RAM_WORDS, RAM_ADDRW);
cfg_tx_write <= bool2bit(cfgbus_wrcmd_range(cfg_cmd, DEVADDR, RT_ADDR_TXRX_DAT));

gen_lane : for n in 0 to RAM_BYTES-1 generate
    cfg_wstrb(n) <= cfg_tx_write and cfg_cmd.wstrb(n) and not tx_cpy_busy;
end generate;

cfg_acks(0) <= cfgbus_reply(cfg_status) when (cfg_reg_read = '1')
          else cfgbus_reply(cfg_rx_data) when (cfg_rx_read = '1')
          else cfgbus_idle;

-- Standard ConfigBus peripherals.
u_cfg_irq : cfgbus_interrupt
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => RT_ADDR_RX_IRQ)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(1),
    ext_toggle  => rx_irq_tog);

u_cfg_mask : cfgbus_register
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => RT_ADDR_TX_MASK,
    WR_ATOMIC   => true,
    WR_MASK     => cfgbus_mask_lsb(PORT_COUNT))
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(2),
    reg_val     => tx_cpu_meta);

-- Other ConfigBus interface logic.
p_cfg : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- Command strobes:
        cfg_rx_start <= bool2bit(cfgbus_wrcmd(cfg_cmd, DEVADDR, RT_ADDR_RX_CTRL));
        cfg_rx_read  <= bool2bit(cfgbus_rdcmd_range(cfg_cmd, DEVADDR, RT_ADDR_TXRX_DAT));
        cfg_tx_start <= bool2bit(cfgbus_wrcmd(cfg_cmd, DEVADDR, RT_ADDR_TX_CTRL));

        if (cfgbus_wrcmd(cfg_cmd, DEVADDR, RT_ADDR_TX_CTRL)) then
            cfg_tx_len <= unsigned(cfg_cmd.wdata(10 downto 0));
        end if;

        -- Status registers.
        if (cfgbus_rdcmd(cfg_cmd, DEVADDR, RT_ADDR_RX_CTRL)) then
            cfg_reg_read <= '1';
            cfg_status <= rx_cpu_meta & rx_cpu_len;
        elsif (cfgbus_rdcmd(cfg_cmd, DEVADDR, RT_ADDR_TX_CTRL)) then
            cfg_reg_read <= '1';
            cfg_status <= (31 => tx_cpy_busy, others => '0');
        else
            cfg_reg_read <= '0';
            cfg_status <= (others => 'X');
        end if;
    end if;
end process;

cfg_ack <= cfgbus_merge(cfg_acks);

end router2_mailmap;
