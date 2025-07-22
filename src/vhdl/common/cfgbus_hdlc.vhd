--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- ConfigBus-controlled HDLC peripheral
--
-- This block implements a flexible, software-controlled HDLC peripheral. Tx
-- and Rx data are held in a small FIFO, for byte-by-byte polling by the host
-- controller. This block raises a ConfigBus interrupt whenever new data is
-- available. When hdlc_txready is de-asserted, this block will finish
-- transmitting the current frame, then halt transmission, until it is
-- re-asserted.
--
-- The following optional features are available:
--     * FCS strip/append
--     * SLIP encoding/decoding
--     * Frame zero padding
--
-- Control is handled through four ConfigBus registers:
-- (All bits not explicitly mentioned are reserved; write zeros.)
--  * REGADDR = 0: Interrupt control
--      Refer to cfgbus_common::cfgbus_interrupt
--  * REGADDR = 1: Configuration
--      Any write to this register resets the HDLC and clears all FIFOs.
--      Bit 15-00: Clock divider ratio (BAUD_HZ = REF_CLK / N)
--  * REGADDR = 2: Status (Read only)
--      Bit 03-03: Error flag (SLIP decode error)
--      Bit 02-02: Running / busy
--      Bit 01-01: Command FIFO full
--      Bit 00-00: Read FIFO has data
--  * REGADDR = 3: Data
--      Write: Queue a data byte for transmission
--          Bit 11-08: Command opcode
--              0x0 Send byte
--              0x1 Send EOF
--              (All other codes reserved)
--          Bit 07-00: Transmit byte
--      Read: Read next byte from receive FIFO
--          Bit 08-08: Received byte valid
--          Bit 07-00: Received byte, if applicable
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;

-- Define a package with useful constants.
package cfgbus_hdlc_constants is
    -- Define command codes
    subtype hdlc_cmd_t is std_logic_vector(3 downto 0);
    constant CMD_WR  : hdlc_cmd_t := x"0";
    constant CMD_EOF : hdlc_cmd_t := x"1";
end package;

---------------------------- Main block ----------------------------

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.cfgbus_common.all;
use     work.cfgbus_hdlc_constants.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity cfgbus_hdlc is
    generic(
    DEVADDR       : integer;          -- Control register address
    FCS_ENABLE    : boolean;          -- Append FCS on Tx, and strip FCS on Rx?
    SLIP_ENABLE   : boolean;          -- SLIP encode on Tx, and decode on Rx?
    INJECT_ENABLE : boolean;          -- Inject a command code into the byte stream
    CMD_CODE      : byte_t;           -- Command code to prepend the TX stream with
    FRAME_BYTES   : natural;          -- 0 for variable length, > 0 for zero pad
    MSB_FIRST     : boolean := false; -- false for LSb first
    FIFO_LOG2     : integer);         -- Tx/Rx FIFO depth = 2^N
    port(
    -- External HDLC signals.
    hdlc_txclk   : out std_logic;
    hdlc_txdata  : out std_logic;
    hdlc_txready : in  std_logic;

    hdlc_rxclk   : in  std_logic;
    hdlc_rxdata  : in  std_logic;

    -- Command interface, including reference clock.
    cfg_cmd      : in  cfgbus_cmd;
    cfg_ack      : out cfgbus_ack);
end cfgbus_hdlc;

architecture cfgbus_hdlc of cfgbus_hdlc is

constant BUFFER_KBYTES : positive := div_ceil(2**FIFO_LOG2, 1000);

-- Transmit data
signal cmd_opcode : hdlc_cmd_t;
signal cmd_data   : byte_t;
signal cmd_valid  : std_logic;
signal cmd_ready  : std_logic;
signal cmd_busy   : std_logic;

signal dly_data   : byte_t;
signal dly_valid  : std_logic;
signal dly_last   : std_logic;
signal dly_ready  : std_logic;
signal dly_wren   : std_logic;

signal adj_data   : byte_t;
signal adj_valid  : std_logic;
signal adj_last   : std_logic;
signal adj_ready  : std_logic;

signal slp_data   : byte_t;
signal slp_valid  : std_logic;
signal slp_last   : std_logic;
signal slp_ready  : std_logic;

signal tx_data    : byte_t;
signal tx_valid   : std_logic;
signal tx_last    : std_logic;
signal tx_ready   : std_logic;

-- Received data
signal rx_data    : byte_t;
signal rx_write   : std_logic;
signal rx_last    : std_logic;

signal dec_data   : byte_t;
signal dec_write  : std_logic;
signal dec_last   : std_logic;

signal pkt_data   : byte_t;
signal pkt_write  : std_logic;
signal pkt_last   : std_logic;

-- ConfigBus interface
signal cfg_word   : cfgbus_word;
signal cfg_rate   : unsigned(15 downto 0);
signal cfg_reset  : std_logic;

begin

-- Tx and Rx HDLCs
u_tx : entity work.io_hdlc_tx
    generic map(
    FRAME_BYTES => FRAME_BYTES,
    MSB_FIRST   => MSB_FIRST)
    port map(
    hdlc_clk   => hdlc_txclk,
    hdlc_data  => hdlc_txdata,
    hdlc_ready => hdlc_txready,
    tx_data    => tx_data,
    tx_valid   => tx_valid,
    tx_last    => tx_last,
    tx_ready   => tx_ready,
    rate_div   => cfg_rate,
    refclk     => cfg_cmd.clk,
    reset_p    => cfg_reset);

u_rx : entity work.io_hdlc_rx
    generic map(
    BUFFER_KBYTES => BUFFER_KBYTES,
    MSB_FIRST     => MSB_FIRST)
    port map(
    hdlc_clk  => hdlc_rxclk,
    hdlc_data => hdlc_rxdata,
    rx_data   => rx_data,
    rx_write  => rx_write,
    rx_last   => rx_last,
    refclk    => cfg_cmd.clk,
    reset_p   => cfg_reset);

gen_inj : if INJECT_ENABLE generate
    blk_inj : block is
    begin
        u_cmd_inj : entity work.packet_prefix
            generic map(
            PREFIX => CMD_CODE)
            port map(
            in_data   => slp_data,
            in_last   => slp_last,
            in_valid  => slp_valid,
            in_ready  => slp_ready,
            out_data  => tx_data,
            out_last  => tx_last,
            out_valid => tx_valid,
            out_ready => tx_ready,
            refclk    => cfg_cmd.clk,
            reset_p   => cfg_reset);
    end block;
end generate;

no_inj : if not INJECT_ENABLE generate
    blk_no_inj : block is
    begin
        tx_data   <= slp_data;
        tx_valid  <= slp_valid;
        tx_last   <= slp_last;
        slp_ready <= tx_ready;
    end block;
end generate;

gen_slip : if SLIP_ENABLE generate
    blk_slip : block is
        signal unpad_data  : byte_t;
        signal unpad_write : std_logic := '0';
    begin
        -- Tx SLIP
        u_slip_enc : entity work.slip_encoder
            generic map(START_TOKEN => false)
            port map(
            in_data   => adj_data,
            in_last   => adj_last,
            in_valid  => adj_valid,
            in_ready  => adj_ready,
            out_data  => slp_data,
            out_last  => slp_last,
            out_valid => slp_valid,
            out_ready => slp_ready,
            refclk    => cfg_cmd.clk,
            reset_p   => cfg_reset);
            

        -- Rx SLIP
        u_unpad : process(cfg_cmd.clk)
            variable ignore : std_logic := '0';
        begin
            if rising_edge(cfg_cmd.clk) then
                if (cfg_reset = '1') then
                    ignore      := '0';
                    unpad_write <= '0';
                elsif (ignore = '1') then
                    unpad_write <= '0';
                    if (rx_write = '1') and (rx_last = '1') then
                        ignore := '0';
                    end if;
                else
                    unpad_data  <= rx_data;
                    unpad_write <= rx_write;
                    if (rx_write = '1') and (rx_last = '0')
                            and (rx_data  = SLIP_FEND) then
                        ignore := '1';
                    end if;
                end if;
            end if;
        end process;

        u_slip_dec : entity work.slip_decoder
            generic map(WAIT_LOCK => false)
            port map(
            in_data   => unpad_data,
            in_write  => unpad_write,
            out_data  => dec_data,
            out_write => dec_write,
            out_last  => dec_last,
            reset_p   => cfg_reset,
            refclk    => cfg_cmd.clk);
    end block;
end generate;

no_gen_slip : if not SLIP_ENABLE generate
    blk_no_slip : block is
    begin
        slp_data   <= adj_data;
        slp_valid  <= adj_valid;
        slp_last   <= adj_last;
        adj_ready  <= slp_ready;

        dec_data  <= rx_data;
        dec_write <= rx_write;
        dec_last  <= rx_last;
    end block;
end generate;

gen_fcs : if FCS_ENABLE generate
    blk_fcs : block is
        signal chk_data   : byte_t;
        signal chk_write  : std_logic;
        signal chk_result : frm_result_t;
    begin
        -- Tx FCS
        u_eth_adj : entity work.eth_frame_adjust
            generic map(STRIP_FCS => false)
            port map(
            in_data   => dly_data,
            in_last   => dly_last,
            in_valid  => dly_valid,
            in_ready  => dly_ready,
            out_data  => adj_data,
            out_last  => adj_last,
            out_valid => adj_valid,
            out_ready => adj_ready,
            clk       => cfg_cmd.clk,
            reset_p   => cfg_reset);

        -- Rx FCS
        u_eth_chk : entity work.eth_frame_check
            generic map(STRIP_FCS => true)
            port map(
            in_data    => dec_data,
            in_last    => dec_last,
            in_write   => dec_write,
            out_data   => chk_data,
            out_write  => chk_write,
            out_result => chk_result,
            clk        => cfg_cmd.clk,
            reset_p    => cfg_reset);

        u_pkt : entity work.fifo_packet
            generic map(
            INPUT_BYTES   => 1,
            OUTPUT_BYTES  => 1,
            BUFFER_KBYTES => BUFFER_KBYTES)
            port map(
            in_clk         => cfg_cmd.clk,
            in_data        => chk_data,
            in_last_commit => chk_result.commit,
            in_last_revert => chk_result.revert,
            in_write       => chk_write,
            in_overflow    => open,
            out_clk        => cfg_cmd.clk,
            out_data       => pkt_data,
            out_last       => pkt_last,
            out_valid      => pkt_write,
            out_ready      => '1',
            out_overflow   => open,
            reset_p        => cfg_reset);
    end block;
end generate;

no_gen_fcs : if not FCS_ENABLE generate
    blk_no_fcs : block is
    begin
        adj_data  <= dly_data;
        adj_valid <= dly_valid;
        adj_last  <= dly_last;
        dly_ready <= adj_ready;

        pkt_data  <= dec_data;
        pkt_write <= dec_write;
        pkt_last  <= dec_last;
    end block;
end generate;

p_ctrl : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        if (cfg_reset = '1') then
            dly_wren <= '0';
        elsif (cmd_valid = '1' and cmd_ready = '1') then
            dly_data   <= cmd_data;
            dly_wren   <= bool2bit(cmd_opcode = CMD_WR);
        end if;
    end if;
end process;

-- Delay commands by one to set LAST strobe
dly_valid <= dly_wren and cmd_valid;
dly_last  <= dly_wren and bool2bit(cmd_opcode = CMD_EOF);
cmd_ready <= dly_ready or not dly_wren;
cmd_busy  <= cmd_valid or not cmd_ready;

-- Extract configuration parameters:
cfg_rate <= unsigned(cfg_word(15 downto 0));

-- ConfigBus interface
u_cfg : entity work.cfgbus_multiserial
    generic map(
    DEVADDR     => DEVADDR,
    CFG_MASK    => x"0000FFFF",
    CFG_RSTVAL  => x"0000FFFF",
    IRQ_RXDATA  => true,
    FIFO_LOG2   => FIFO_LOG2)
    port map(
    cmd_opcode  => cmd_opcode,
    cmd_data    => cmd_data,
    cmd_valid   => cmd_valid,
    cmd_ready   => cmd_ready,
    rx_data     => pkt_data,
    rx_write    => pkt_write,
    cfg_reset   => cfg_reset,
    cfg_word    => cfg_word,
    status_busy => cmd_busy,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack);

end cfgbus_hdlc;

