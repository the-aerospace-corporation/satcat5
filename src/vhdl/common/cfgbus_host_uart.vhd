--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- ConfigBus host with Ethernet-over-UART interface
--
-- This module is a thin wrapper for "cfgbus_host_eth" that attaches it
-- to a SLIP-encoded UART port.  The UART can be operated in write-only
-- mode, or with a reply line to enable reads.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;
use     work.eth_frame_common.all;

entity cfgbus_host_uart is
    generic (
    CFG_ETYPE   : mac_type_t := x"5C01";
    CFG_MACADDR : mac_addr_t := x"5A5ADEADBEEF";
    CLKREF_HZ   : positive;         -- Reference clock rate (Hz)
    UART_BAUD   : positive;         -- Input and output rate (bps)
    UART_REPLY  : boolean;          -- Enable reply UART?
    CHECK_FCS   : boolean;          -- Verify command checksum? Or ignore?
    RD_TIMEOUT  : positive := 16);  -- ConfigBus read timeout (clocks)
    port (
    -- ConfigBus host interface.
    cfg_cmd     : out cfgbus_cmd;
    cfg_ack     : in  cfgbus_ack;

    -- UART port
    uart_rxd    : in  std_logic;
    uart_txd    : out std_logic;    -- Optional (see above)

    -- Other control
    sys_clk     : in  std_logic;
    reset_p     : in  std_logic);
end cfgbus_host_uart;

architecture cfgbus_host_uart of cfgbus_host_uart is

-- UART clock-divider is fixed at build-time.
constant UART_CLKDIV : unsigned(15 downto 0) :=
    to_unsigned(clocks_per_baud_uart(CLKREF_HZ, UART_BAUD), 16);

-- Rx datapath
signal rx_raw_data      : byte_t;
signal rx_raw_write     : std_logic;
signal rx_dec_data      : byte_t;
signal rx_dec_last      : std_logic;
signal rx_dec_write     : std_logic;
signal rx_chk_data      : byte_t;
signal rx_chk_commit    : std_logic;
signal rx_chk_revert    : std_logic;
signal rx_chk_write     : std_logic;
signal rx_fifo_data     : byte_t;
signal rx_fifo_last     : std_logic;
signal rx_fifo_valid    : std_logic;
signal rx_fifo_ready    : std_logic;

-- Tx datapath
signal tx_pkt_data      : byte_t;
signal tx_pkt_last      : std_logic;
signal tx_pkt_valid     : std_logic;
signal tx_pkt_ready     : std_logic;
signal tx_enc_data      : byte_t;
signal tx_enc_valid     : std_logic;
signal tx_enc_ready     : std_logic;

begin

-- Rx datapath: UART and SLIP decoder.
u_rx_uart : entity work.io_uart_rx
    port map(
    uart_rxd    => uart_rxd,
    rx_data     => rx_raw_data,
    rx_write    => rx_raw_write,
    rate_div    => UART_CLKDIV,
    refclk      => sys_clk,
    reset_p     => reset_p);

u_rx_slip : entity work.slip_decoder
    port map(
    in_data     => rx_raw_data,
    in_write    => rx_raw_write,
    out_data    => rx_dec_data,
    out_last    => rx_dec_last,
    out_write   => rx_dec_write,
    decode_err  => open,
    refclk      => sys_clk,
    reset_p     => reset_p);

-- Rx datapath: Optionally verify FCS.
gen_fcs1 : if CHECK_FCS generate
    u_chk : entity work.eth_frame_check
        generic map(
        ALLOW_MCTRL => true,
        ALLOW_RUNT  => true,
        STRIP_FCS   => true)
        port map(
        in_data     => rx_dec_data,
        in_last     => rx_dec_last,
        in_write    => rx_dec_write,
        out_data    => rx_chk_data,
        out_write   => rx_chk_write,
        out_commit  => rx_chk_commit,
        out_revert  => rx_chk_revert,
        out_error   => open,
        clk         => sys_clk,
        reset_p     => reset_p);
end generate;

gen_fcs0 : if not CHECK_FCS generate
    rx_chk_data     <= rx_dec_data;
    rx_chk_write    <= rx_dec_write;
    rx_chk_commit   <= rx_dec_last;
    rx_chk_revert   <= '0';
end generate;

-- Rx datapath: Command FIFO
u_fifo : entity work.fifo_packet
    generic map(
    INPUT_BYTES     => 1,
    OUTPUT_BYTES    => 1,
    BUFFER_KBYTES   => 2,
    MAX_PACKETS     => 16)
    port map(
    in_clk          => sys_clk,
    in_data         => rx_chk_data,
    in_last_commit  => rx_chk_commit,
    in_last_revert  => rx_chk_revert,
    in_write        => rx_chk_write,
    in_overflow     => open,
    out_clk         => sys_clk,
    out_data        => rx_fifo_data,
    out_last        => rx_fifo_last,
    out_valid       => rx_fifo_valid,
    out_ready       => rx_fifo_ready,
    out_overflow    => open,
    reset_p         => reset_p);

-- ConfigBus host.
u_host : entity work.cfgbus_host_eth
    generic map(
    CFG_ETYPE   => CFG_ETYPE,
    CFG_MACADDR => CFG_MACADDR,
    APPEND_FCS  => true,
    MIN_FRAME   => 0,
    RD_TIMEOUT  => RD_TIMEOUT)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    rx_data     => rx_fifo_data,
    rx_last     => rx_fifo_last,
    rx_valid    => rx_fifo_valid,
    rx_ready    => rx_fifo_ready,
    tx_data     => tx_pkt_data,
    tx_last     => tx_pkt_last,
    tx_valid    => tx_pkt_valid,
    tx_ready    => tx_pkt_ready,
    irq_out     => open,
    txrx_clk    => sys_clk,
    reset_p     => reset_p);

-- Tx datapath: SLIP encoder and UART.
gen_uart1 : if UART_REPLY generate
    u_tx_slip : entity work.slip_encoder
        port map(
        in_data     => tx_pkt_data,
        in_last     => tx_pkt_last,
        in_valid    => tx_pkt_valid,
        in_ready    => tx_pkt_ready,
        out_data    => tx_enc_data,
        out_valid   => tx_enc_valid,
        out_ready   => tx_enc_ready,
        refclk      => sys_clk,
        reset_p     => reset_p);

    u_tx_uart : entity work.io_uart_tx
        port map(
        uart_txd    => uart_txd,
        tx_data     => tx_enc_data,
        tx_valid    => tx_enc_valid,
        tx_ready    => tx_enc_ready,
        rate_div    => UART_CLKDIV,
        refclk      => sys_clk,
        reset_p     => reset_p);
end generate;

gen_uart0 : if not UART_REPLY generate
    uart_txd        <= '1';             -- UARTs are idle-high
    tx_pkt_ready    <= '1';             -- Discard all replies
    tx_enc_data     <= (others => '0'); -- Unused
    tx_enc_valid    <= '0';             -- Unused
    tx_enc_ready    <= '0';             -- Unused
end generate;

end cfgbus_host_uart;
