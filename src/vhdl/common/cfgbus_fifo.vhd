--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- Asynchronous ConfigBus FIFO block.
--
-- This block contains a generic FIFO for connecting a ConfigBus register
-- to an AXI-stream.  It can support writes, reads, or both.  It is often
-- used as part of other ConfigBus blocks.
--
-- Each word written by the ConfigBus host appears at the "wr" port:
--  * First M LSBs map to "wr_data" (M = WR_DWIDTH).
--  * Next N LSBs map to "wr_meta" (N = WR_MWIDTH).
--  * If WR_DWIDTH + WR_MWIDTH < 32, then Bit 31 maps to "wr_last".
--    (Otherwise, the "wr_last" output is disabled.)
--  * Any remaining bits are discarded.
--
-- Each word accepted by the "rd" port can be read by the host:
--  * First M LSBs contain "rd_data" (M = RD_DWIDTH).
--  * Next N LSBs contain "rd_meta" (N = RD_MWIDTH).
--  * If RD_FLAGS is set, then:
--      * Bit 31 contains the "rd_last" strobe.
--      * Bit 30 indicates the read word is valid.
--      * Bit 29 indicates the write FIFO is full.
--  * Any remaining bits are reserved and should be ignored.
--
-- The total write width is limited to WR_DWIDTH + WR_MWIDTH <= 32.
-- The total read width is limited to RD_DWIDTH + RD_MWIDTH <= 29
-- when RD_FLAGS is set, <= 32 otherwise.
--
-- Where practical, the "write-full", "read-ready", and "read-last" flags
-- should be made available through a separate ConfigBus register.  This
-- allows the control software to poll these flags without disturbing the
-- read FIFO.  In such cases, set RD_FLAGS = false to avoid duplication.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;

entity cfgbus_fifo is
    generic (
    DEVADDR     : integer;              -- Peripheral address
    REGADDR     : integer := CFGBUS_ADDR_ANY;
    WR_DEPTH    : natural := 0;         -- Write FIFO depth = 2^N words
    WR_DWIDTH   : natural := 0;         -- Width of "wr_data" port
    WR_MWIDTH   : natural := 0;         -- Width of "wr_meta" port
    RD_DEPTH    : natural := 0;         -- Read FIFO depth = 2^N words
    RD_DWIDTH   : natural := 0;         -- Width of "rd_data" port
    RD_MWIDTH   : natural := 0;         -- Width of "rd_meta" port
    RD_FLAGS    : boolean := true);     -- Report full/valid flags in read?
    port (
    -- ConfigBus interface
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack;
    -- Control and status flags in ConfigBus clock domain.
    cfg_clear   : in  std_logic := '0';
    cfg_wr_full : out std_logic;        -- Write FIFO is full
    cfg_rd_last : out std_logic;        -- Read FIFO has last word
    cfg_rd_rdy  : out std_logic;        -- Read FIFO has data
    -- Write port (host to stream)
    wr_clk      : in  std_logic := '0';
    wr_data     : out std_logic_vector(WR_DWIDTH-1 downto 0);
    wr_meta     : out std_logic_vector(WR_MWIDTH-1 downto 0);
    wr_last     : out std_logic;
    wr_valid    : out std_logic;
    wr_ready    : in  std_logic := '1';
    -- Read port (stream to host)
    rd_clk      : in  std_logic := '0';
    rd_data     : in  std_logic_vector(RD_DWIDTH-1 downto 0) := (others => '0');
    rd_meta     : in  std_logic_vector(RD_MWIDTH-1 downto 0) := (others => '0');
    rd_last     : in  std_logic := '0';
    rd_valid    : in  std_logic := '0';
    rd_ready    : out std_logic);
end cfgbus_fifo;

architecture cfgbus_fifo of cfgbus_fifo is

-- Enable the write and read FIFOs?
constant WR_ENABLE  : boolean := (WR_DWIDTH + WR_MWIDTH > 0) and (WR_DEPTH > 0);
constant RD_ENABLE  : boolean := (RD_DWIDTH + RD_MWIDTH > 0) and (RD_DEPTH > 0);

-- All "cfg_xx" signals are in the ConfigBus clock domain.
signal cfg_regwr    : std_logic;
signal cfg_regrd    : std_logic;
signal fifo_reset   : std_logic;

signal cfg_wdata    : std_logic_vector(WR_DWIDTH-1 downto 0) := (others => '0');
signal cfg_wmeta    : std_logic_vector(WR_MWIDTH-1 downto 0) := (others => '0');
signal cfg_wlast    : std_logic := '0';
signal cfg_wready   : std_logic;
signal cfg_wfull    : std_logic;

signal cfg_rdata    : std_logic_vector(RD_DWIDTH-1 downto 0);
signal cfg_rmeta    : std_logic_vector(RD_MWIDTH-1 downto 0);
signal cfg_rlast    : std_logic;
signal cfg_rword    : cfgbus_word;
signal cfg_rflags   : cfgbus_word;
signal cfg_rvalid   : std_logic;

signal ack          : cfgbus_ack := cfgbus_idle;

begin

-- Drive top-level outputs.
cfg_ack     <= ack;
cfg_wr_full <= cfg_wfull;
cfg_rd_last <= cfg_rlast;
cfg_rd_rdy  <= cfg_rvalid;

-- Size conversion and sanity checks.
assert (WR_DWIDTH + WR_MWIDTH <= CFGBUS_WORD_SIZE);
assert (RD_DWIDTH + RD_MWIDTH <= CFGBUS_WORD_SIZE);
assert (RD_DWIDTH + RD_MWIDTH <= CFGBUS_WORD_SIZE-3 or not RD_FLAGS);

gen_wdata : if (WR_DWIDTH > 0) generate
    cfg_wdata <= cfg_cmd.wdata(WR_DWIDTH-1 downto 0);
end generate;

gen_wmeta : if (WR_MWIDTH > 0) generate
    cfg_wmeta <= cfg_cmd.wdata(WR_DWIDTH+WR_MWIDTH-1 downto WR_DWIDTH);
end generate;

gen_wlast : if (WR_MWIDTH + WR_MWIDTH < CFGBUS_WORD_SIZE) generate
    cfg_wlast <= cfg_cmd.wdata(cfg_cmd.wdata'left);
end generate;

cfg_rword <= resize(cfg_rmeta & cfg_rdata, CFGBUS_WORD_SIZE)
    when (cfg_rvalid = '1') else (others => '0');

cfg_rflags <= (
    31 => cfg_rlast,
    30 => cfg_rvalid,
    29 => cfg_wfull,
    others => '0');

-- Generate register-write and register-read strobes.
cfg_regwr <= bool2bit(cfgbus_wrcmd(cfg_cmd, DEVADDR, REGADDR));
cfg_regrd <= bool2bit(cfgbus_rdcmd(cfg_cmd, DEVADDR, REGADDR));

-- Clear FIFOs on reset or on external clear request.
fifo_reset <= cfg_cmd.reset_p or cfg_clear;

-- FIFO for write stream:
gen_wr1 : if WR_ENABLE generate
    cfg_wfull <= not cfg_wready;

    u_fifo_wr : entity work.fifo_smol_async
        generic map(
        IO_WIDTH    => WR_DWIDTH,
        META_WIDTH  => WR_MWIDTH,
        DEPTH_LOG2  => WR_DEPTH)
        port map(
        in_clk      => cfg_cmd.clk,
        in_data     => cfg_wdata,
        in_meta     => cfg_wmeta,
        in_last     => cfg_wlast,
        in_valid    => cfg_regwr,
        in_ready    => cfg_wready,
        out_clk     => wr_clk,
        out_data    => wr_data,
        out_meta    => wr_meta,
        out_last    => wr_last,
        out_valid   => wr_valid,
        out_ready   => wr_ready,
        reset_p     => fifo_reset);
end generate;

gen_wr0 : if not WR_ENABLE generate
    cfg_wfull   <= '0';
    cfg_wready  <= '0';
    wr_data     <= (others => '0');
    wr_meta     <= (others => '0');
    wr_last     <= '0';
    wr_valid    <= '0';
end generate;

-- FIFO for read stream:
gen_rd1 : if RD_ENABLE generate
    u_fifo_rd : entity work.fifo_smol_async
        generic map(
        IO_WIDTH    => RD_DWIDTH,
        META_WIDTH  => RD_MWIDTH,
        DEPTH_LOG2  => RD_DEPTH)
        port map(
        in_clk      => rd_clk,
        in_data     => rd_data,
        in_meta     => rd_meta,
        in_last     => rd_last,
        in_valid    => rd_valid,
        in_ready    => rd_ready,
        out_clk     => cfg_cmd.clk,
        out_data    => cfg_rdata,
        out_meta    => cfg_rmeta,
        out_last    => cfg_rlast,
        out_valid   => cfg_rvalid,
        out_ready   => cfg_regrd,
        reset_p     => fifo_reset);
end generate;

gen_rd0 : if not RD_ENABLE generate
    rd_ready    <= '0';
    cfg_rdata   <= (others => '0');
    cfg_rmeta   <= (others => '0');
    cfg_rlast   <= '0';
    cfg_rvalid  <= '0';
end generate;

-- Latch the read-response.
p_read : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        if (cfg_regrd = '0') THEN
            ack <= cfgbus_idle;
        elsif (RD_FLAGS) then
            ack <= cfgbus_reply(cfg_rword or cfg_rflags);
        else
            ack <= cfgbus_reply(cfg_rword);
        end if;
    end if;
end process;

end cfgbus_fifo;
