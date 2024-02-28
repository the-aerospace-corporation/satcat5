--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- ConfigBus host with AXI4-Lite interface
--
-- This module acts as a ConfigBus host, accepting read and write commands
-- over AXI4-Lite and acting as a bridge for those commands.
--
-- The AXI address space is divided as follows:
--  * 2 bits    Padding (byte to word conversion)
--  * 10 bits   Register address (0-1023)
--  * 8 bits    Device address (0-255)
--  * All remaining MSBs are ignored.
--
-- If possible, this device should be given a 20-bit address space (1 MiB).
-- If this space is reduced, then the block will operate correctly but upper
-- device addresses may not be accessible.
--
-- Write throughput is 100%.  Due to the "one pending transaction" rule,
-- read throughput depends on the round-trip command-to-ack latency.  It
-- will never exceed 50%.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;

entity cfgbus_host_axi is
    generic (
    RD_TIMEOUT  : positive := 16;       -- ConfigBus read timeout (clocks)
    ADDR_WIDTH  : positive := 32;       -- AXI-Lite address width
    BASE_ADDR   : natural := 0);        -- AXI-Lite base address
    port (
    -- ConfigBus host interface.
    cfg_cmd     : out cfgbus_cmd;
    cfg_ack     : in  cfgbus_ack;

    -- AXI-Lite interface
    axi_clk     : in  std_logic;
    axi_aresetn : in  std_logic;
    axi_irq     : out std_logic;
    axi_awaddr  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    axi_awvalid : in  std_logic;
    axi_awready : out std_logic;
    axi_wdata   : in  cfgbus_word;
    axi_wstrb   : in  cfgbus_wstrb := (others => '1');
    axi_wvalid  : in  std_logic;
    axi_wready  : out std_logic;
    axi_bresp   : out std_logic_vector(1 downto 0);
    axi_bvalid  : out std_logic;
    axi_bready  : in  std_logic;
    axi_araddr  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    axi_arvalid : in  std_logic;
    axi_arready : out std_logic;
    axi_rdata   : out cfgbus_word;
    axi_rresp   : out std_logic_vector(1 downto 0);
    axi_rvalid  : out std_logic;
    axi_rready  : in  std_logic);
end cfgbus_host_axi;

architecture cfgbus_host_axi of cfgbus_host_axi is

-- Address word = 12-bit spare + 8-bit device + 10-bit register.
subtype sub_addr_s is std_logic_vector(29 downto 0);
subtype sub_addr_u is unsigned(29 downto 0);
signal awaddr_trim  : sub_addr_u;
signal araddr_trim  : sub_addr_u;
signal reset_p      : std_logic;
signal interrupt    : std_logic;

-- Write state machine.
signal wr_awready   : std_logic;
signal wr_wready    : std_logic;
signal wr_awbusy    : std_logic;
signal wr_awpend    : std_logic := '0';
signal wr_wpend     : std_logic := '0';
signal wr_execute   : std_logic;
signal wr_addr      : sub_addr_u := (others => '0');
signal wr_data      : cfgbus_word := (others => '0');
signal wr_wstrb     : cfgbus_wstrb := (others => '0');

-- FIFO for read commands.
signal cfifo_addr   : sub_addr_s;
signal cfifo_write  : std_logic;
signal cfifo_valid  : std_logic;
signal cfifo_ready  : std_logic;
signal cfifo_full   : std_logic;
signal cfifo_reset  : std_logic;
signal rd_execute   : std_logic := '0';
signal rd_pending   : std_logic := '0';

-- Timeouts and error detection.
signal int_cmd      : cfgbus_cmd;
signal int_ack      : cfgbus_ack;

-- FIFO for read responses.
signal dfifo_write  : std_logic;
signal dfifo_valid  : std_logic;
signal dfifo_hfull  : std_logic;
signal axi_rerror   : std_logic;

begin

-- AXI uses an active-low reset (asynchronous assert, sync clear).
reset_p     <= not axi_aresetn;

-- Drive top-level AXI signals.
axi_irq     <= interrupt;
axi_awready <= wr_awready;
axi_wready  <= wr_wready;
axi_bresp   <= "00";    -- Always respond with "OK"
axi_bvalid  <= wr_awpend and wr_wpend;
axi_arready <= not cfifo_full;
axi_rvalid  <= dfifo_valid and axi_aresetn;
axi_rresp   <= "10" when (axi_rerror = '1') else "00";

-- Address conversion for read and write addresses.
awaddr_trim <= convert_address(axi_awaddr, BASE_ADDR, 30);
araddr_trim <= convert_address(axi_araddr, BASE_ADDR, 30);

-- Write state machine and ConfigBus arbitration.
-- (One write command at a time, wait for response to be accepted,
--  read commands are issued whenever writes are idle.)
wr_execute  <= wr_awpend and wr_wpend and axi_bready;
wr_awready  <= wr_execute or not wr_awpend;
wr_wready   <= wr_execute or not wr_wpend;
wr_awbusy   <= (axi_awvalid and wr_awready)
            or (wr_awpend and not wr_execute);

p_wctrl : process(axi_clk, axi_aresetn)
begin
    if (axi_aresetn = '0') then
        wr_awpend   <= '0';
        wr_wpend    <= '0';
        interrupt   <= '0';
    elsif rising_edge(axi_clk) then
        if (axi_awvalid = '1' and wr_awready = '1') then
            wr_awpend   <= '1'; -- Command accepted
        elsif (wr_execute = '1') then
            wr_awpend   <= '0'; -- Response consumed
        end if;

        if (axi_wvalid = '1' and wr_wready = '1') then
            wr_wpend    <= '1'; -- Data accepted
        elsif (wr_execute = '1') then
            wr_wpend    <= '0'; -- Response consumed
        end if;

        interrupt <= int_ack.irq;
    end if;
end process;

p_wdata : process(axi_clk)
begin
    if rising_edge(axi_clk) then
        -- Execute read when there's a command in FIFO and write is idle.
        rd_execute <= cfifo_valid and cfifo_ready;

        -- Latch write or read address.
        if (axi_awvalid = '1' and wr_awready = '1') then
            wr_addr <= awaddr_trim;
        elsif (cfifo_valid = '1' and cfifo_ready = '1') then
            wr_addr <= unsigned(cfifo_addr);
        end if;

        -- Latch data word.
        if (axi_wvalid = '1' and wr_wready = '1') then
            wr_data     <= axi_wdata;
            wr_wstrb    <= axi_wstrb;
        end if;
    end if;
end process;

-- AXI-Read from any address gets put into a FIFO.
-- Addresses are pulled when it is safe to do so (see above).
cfifo_write <= axi_arvalid and not cfifo_full;
cfifo_ready <= not (wr_awbusy or dfifo_hfull or rd_pending or rd_execute);

u_cfifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => 30,
    DEPTH_LOG2  => 4)
    port map(
    in_data     => std_logic_vector(araddr_trim),
    in_write    => cfifo_write,
    out_data    => cfifo_addr,
    out_valid   => cfifo_valid,
    out_read    => cfifo_ready,
    fifo_full   => cfifo_full,
    clk         => axi_clk,
    reset_p     => reset_p);

-- Drive each ConfigBus signal.
int_cmd.clk     <= axi_clk;
int_cmd.sysaddr <= to_integer(wr_addr(29 downto 18));
int_cmd.devaddr <= to_integer(wr_addr(17 downto 10));
int_cmd.regaddr <= to_integer(wr_addr(9 downto 0));
int_cmd.wdata   <= wr_data;
int_cmd.wstrb   <= wr_wstrb;
int_cmd.wrcmd   <= wr_execute;
int_cmd.rdcmd   <= rd_execute;
int_cmd.reset_p <= reset_p;

-- Timeouts and error detection.
u_timeout : cfgbus_timeout
    generic map(
    RD_TIMEOUT  => RD_TIMEOUT)
    port map(
    host_cmd    => int_cmd,
    host_ack    => int_ack,
    host_wait   => rd_pending,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack);

-- ConfigBus responses are also put into a FIFO.
-- (Use "last" flag to indicate timeouts or other errors.)
dfifo_write <= int_ack.rdack or int_ack.rderr;

u_dfifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => 32,
    DEPTH_LOG2  => 4)
    port map(
    in_data     => int_ack.rdata,
    in_last     => int_ack.rderr,
    in_write    => dfifo_write,
    out_data    => axi_rdata,
    out_last    => axi_rerror,
    out_valid   => dfifo_valid,
    out_read    => axi_rready,
    fifo_hfull  => dfifo_hfull,
    clk         => axi_clk,
    reset_p     => reset_p);

end cfgbus_host_axi;
