--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation
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
-- SPI+MDIO configuration and status reporting using Ethernet
--
-- This block acts as a virtual internal port, typically off the low-speed
-- switch_core block.  It will periodically broadcast status information
-- using the config_send_status block; see that block for format info.
--
-- Incoming packets are filtered by EtherType.  The contents of any packet
-- with a matching Ethertype are forwarded to the config_read_command block;
-- see that block for format info.  Typical uses include power control of
-- high-speed ports, or loading MDIO configuration commands.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.switch_types.all;
use     work.synchronization.all;

entity config_port_eth is
    generic (
    -- Baud rates and port-counts.
    CLKREF_HZ   : integer;          -- Main clock rate (Hz)
    SPI_BAUD    : integer;          -- SPI baud rate (bps), or -1 to disable
    SPI_MODE    : integer;          -- SPI mode index (0-3)
    MDIO_BAUD   : integer;          -- MDIO baud rate (bps), or -1 to disable
    MDIO_COUNT  : integer;          -- Number of MDIO ports
    -- GPO initial state (optional)
    GPO_RSTVAL  : std_logic_vector(31 downto 0) := (others => '0');
    -- Set EtherType for configuration commands
    CFG_ETYPE   : std_logic_vector(15 downto 0) := x"5C01";
    -- Parameters for the status report
    STAT_BYTES  : integer;          -- Bytes per status message
    STAT_ETYPE  : std_logic_vector(15 downto 0) := x"5C00";
    STAT_DEST   : std_logic_vector(47 downto 0) := x"FFFFFFFFFFFF";
    STAT_SOURCE : std_logic_vector(47 downto 0) := x"536174436174");
    port (
    -- Internal Ethernet port.
    rx_data     : out port_rx_m2s;
    tx_data     : in  port_tx_m2s;
    tx_ctrl     : out port_tx_s2m;

    -- Status word
    status_val  : in  std_logic_vector(8*STAT_BYTES-1 downto 0);

    -- SPI interface
    spi_csb     : out std_logic;    -- Chip select
    spi_sck     : out std_logic;    -- Clock
    spi_sdo     : out std_logic;    -- Data (FPGA to ASIC)

    -- MDIO interface(s)
    mdio_clk    : out std_logic_vector(MDIO_COUNT-1 downto 0);
    mdio_data   : out std_logic_vector(MDIO_COUNT-1 downto 0);
    mdio_oe     : out std_logic_vector(MDIO_COUNT-1 downto 0);

    -- General-purpose outputs (internal or external)
    ctrl_out    : out std_logic_vector(31 downto 0);

    -- System interface
    ref_clk     : in  std_logic;    -- Reference clock
    ext_reset_p : in  std_logic := '0';  -- Async. reset (choose one)
    ext_reset_n : in  std_logic := '1'); -- Async. reset (choose one)
end config_port_eth;

architecture rtl of config_port_eth is

-- Global externally-triggered reset.
signal ext_rst_any      : std_logic;
signal reset_p          : std_logic;

-- Filtered Ethernet frames.
signal filt_next        : std_logic;
signal cfg_match        : std_logic := '0';
signal cfg_data         : byte_t;
signal cfg_last         : std_logic;
signal cfg_valid        : std_logic;
signal cfg_ready        : std_logic;

begin

-- External reset may be of either polarity.
-- (User typically chooses one, but could conceivably use both.)
ext_rst_any <= ext_reset_p or not ext_reset_n;

u_reset : sync_reset
    generic map(KEEP_ATTR => "false")
    port map(
    in_reset_p  => ext_rst_any,
    out_reset_p => reset_p,
    out_clk     => ref_clk);

-- Status reporting block.
rx_data.clk     <= ref_clk;
rx_data.rxerr   <= '0';
rx_data.reset_p <= reset_p;

u_status : entity work.config_send_status
    generic map(
    MSG_BYTES   => STAT_BYTES,
    MSG_ETYPE   => STAT_ETYPE,
    MAC_DEST    => STAT_DEST,
    MAC_SOURCE  => STAT_SOURCE,
    AUTO_DELAY  => CLKREF_HZ)   -- Send once per second
    port map(
    status_val  => status_val,
    status_wr   => '0',         -- Automatic Tx only
    out_data    => rx_data.data,
    out_last    => rx_data.last,
    out_valid   => rx_data.write,
    out_ready   => '1',         -- No flow control
    clk         => ref_clk,
    reset_p     => reset_p);

-- Filter incoming data by EtherType.
tx_ctrl.clk     <= ref_clk;
tx_ctrl.ready   <= cfg_ready or not cfg_match;
tx_ctrl.txerr   <= '0';
tx_ctrl.reset_p <= reset_p;

filt_next <= tx_data.valid and (cfg_ready or not cfg_match);

p_filter : process(ref_clk)
    constant ETYPE1 : byte_t := CFG_ETYPE(15 downto 8);
    constant ETYPE2 : byte_t := CFG_ETYPE( 7 downto 0);
    variable bcount : integer range 0 to 14 := 0;
    variable bmatch : std_logic := '0';
begin
    if rising_edge(ref_clk) then
        -- Set or clear the "match" and pre-match flags.
        if (reset_p = '1') then
            cfg_match <= '0';
        elsif (filt_next = '1') then
            if (tx_data.last = '1') then
                cfg_match <= '0';
            elsif (bcount = 13 and tx_data.data = ETYPE2) then
                cfg_match <= bmatch;
            end if;
        end if;

        if (filt_next = '1' and bcount = 12) then
            bmatch := bool2bit(tx_data.data = ETYPE1);
        end if;

        -- Count off first 14 bytes in each frame. (DST, SRC, ETYPE)
        if (reset_p = '1') then
            bcount := 0;
        elsif (filt_next = '1') then
            if (tx_data.last = '1') then
                bcount := 0;
            elsif (bcount < 14) then
                bcount := bcount + 1;
            end if;
        end if;
    end if;
end process;

cfg_data  <= tx_data.data;
cfg_last  <= tx_data.last;
cfg_valid <= tx_data.valid and cfg_match;

-- Parse commands and drive each interface.
u_cmd : entity work.config_read_command
    generic map(
    CLKREF_HZ   => CLKREF_HZ,
    SPI_BAUD    => SPI_BAUD,
    SPI_MODE    => SPI_MODE,
    MDIO_BAUD   => MDIO_BAUD,
    MDIO_COUNT  => MDIO_COUNT,
    GPO_RSTVAL  => GPO_RSTVAL)
    port map(
    cmd_data    => cfg_data,
    cmd_last    => cfg_last,
    cmd_valid   => cfg_valid,
    cmd_ready   => cfg_ready,
    spi_csb     => spi_csb,
    spi_sck     => spi_sck,
    spi_sdo     => spi_sdo,
    mdio_clk    => mdio_clk,
    mdio_data   => mdio_data,
    mdio_oe     => mdio_oe,
    ctrl_out    => ctrl_out,
    ref_clk     => ref_clk,
    reset_p     => reset_p);

end rtl;
