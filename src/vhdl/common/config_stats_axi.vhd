--------------------------------------------------------------------------
-- Copyright 2020 The Aerospace Corporation
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
-- Port traffic statistics (with AXI-Lite interface)
--
-- This module instantiates a port_statistics block for each attached
-- Ethernet port, and makes the results available on a memory-mapped
-- AXI-lite interface.
--
-- A write to any of the mapped registers refreshes the statistics
-- counters.  (The write address and write value are ignored.)
--
-- Once refreshed, each register reports total observed traffic since
-- the previous refresh.  There are four registers for each port:
--   * Broadcast bytes received (from device to switch)
--   * Broadcast frames received
--   * Total bytes received (from device to switch)
--   * Total frames received
--   * Total bytes sent (from switch to device)
--   * Total frames sent
-- The register map is a consecutive array of 32-bit words (uint32_t),
-- starting from the specified base address (default zero).
-- The first six registers are for port 0, the next six for port 1,
-- and so on.  Reads can be in any order, but must be word-aligned.
-- Reads beyond the end of the array will always return zero.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.switch_types.all;

entity config_stats_axi is
    generic (
    PORT_COUNT  : integer;
    COUNT_WIDTH : natural := 32;        -- Internal counter width (16-32 bits)
    ADDR_WIDTH  : natural := 32;        -- AXI-Lite address width
    BASE_ADDR   : natural := 0);        -- Base address (see above)
    port (
    -- Generic internal port interface (monitor only)
    rx_data     : in  array_rx_m2s(PORT_COUNT-1 downto 0);
    tx_data     : in  array_tx_m2s(PORT_COUNT-1 downto 0);
    tx_ctrl     : in  array_tx_s2m(PORT_COUNT-1 downto 0);

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
end config_stats_axi;

architecture config_stats_axi of config_stats_axi is

-- Statistics module for each port.
constant WORD_COUNT : natural := 6 * PORT_COUNT;
subtype stat_word is unsigned(COUNT_WIDTH-1 downto 0);
type stats_array_t is array(WORD_COUNT-1 downto 0) of stat_word;
signal stats_req_t  : std_logic := '0';
signal stats_array  : stats_array_t := (others => (others => '0'));

-- FIFO for read commands.
signal fifo_raddr   : std_logic_vector(ADDR_WIDTH-1 downto 0);
signal fifo_write   : std_logic;
signal fifo_valid   : std_logic;
signal fifo_read    : std_logic;
signal fifo_full    : std_logic;
signal fifo_reset   : std_logic;

-- Read state machine.
signal read_data    : std_logic_vector(31 downto 0) := (others => '0');
signal read_valid   : std_logic := '0';

begin

-- Statistics module for each port.
gen_stats : for n in 0 to PORT_COUNT-1 generate
    u_stats : entity work.port_statistics
        generic map(COUNT_WIDTH => COUNT_WIDTH)
        port map(
        stats_req_t => stats_req_t,
        bcst_bytes  => stats_array(6*n+0),
        bcst_frames => stats_array(6*n+1),
        rcvd_bytes  => stats_array(6*n+2),
        rcvd_frames => stats_array(6*n+3),
        sent_bytes  => stats_array(6*n+4),
        sent_frames => stats_array(6*n+5),
        rx_data     => rx_data(n),
        tx_data     => tx_data(n),
        tx_ctrl     => tx_ctrl(n));
end generate;

-- AXI-Write to any address toggles the "request" signal.
axi_awready <= '1';     -- Always ready to accept address (request-toggle)
axi_wready  <= '1';     -- Always ready to accept data (ignored)
axi_bresp   <= "00";    -- Always respond with "OK"
axi_bvalid  <= '1';

p_axi_wr : process(axi_clk)
begin
    if rising_edge(axi_clk) then
        if (axi_awvalid = '1') then
            stats_req_t <= not stats_req_t;
        end if;
    end if;
end process;

-- AXI-Read from any address gets put into a FIFO.
axi_arready <= not fifo_full;
fifo_write  <= axi_arvalid and not fifo_full;
fifo_read   <= fifo_valid and (axi_rready or not read_valid);
fifo_reset  <= not axi_aresetn;

u_fifo : entity work.smol_fifo
    generic map(
    IO_WIDTH    => ADDR_WIDTH,
    DEPTH_LOG2  => 4)
    port map(
    in_data     => axi_araddr,
    in_write    => fifo_write,
    out_data    => fifo_raddr,
    out_valid   => fifo_valid,
    out_read    => fifo_read,
    fifo_full   => fifo_full,
    clk         => axi_clk,
    reset_p     => fifo_reset);

-- Respond to AXI reads:
axi_rdata   <= read_data;
axi_rvalid  <= read_valid;
axi_rresp   <= "00";    -- Always respond with "OK"

p_axi_rd : process(axi_clk, axi_aresetn)
    variable idx_tmp : natural;
begin
    if (axi_aresetn = '0') then
        read_data   <= (others => '0');
        read_valid  <= '0';
    elsif rising_edge(axi_clk) then
        -- Read new data? (i.e., Buffer vacant or just consumed.)
        if (axi_rready = '1' or read_valid = '0') then
            -- Convert byte-address to index (must be 32-bit word-aligned).
            idx_tmp := to_integer((unsigned(fifo_raddr) - BASE_ADDR) / 4);
            -- Grab counter word from the specified address.
            if (idx_tmp < WORD_COUNT) then
                read_data <= std_logic_vector(resize(stats_array(idx_tmp), 32));
            else
                read_data <= (others => '0');
            end if;
            read_valid <= fifo_valid;
        end if;
    end if;
end process;

end config_stats_axi;
