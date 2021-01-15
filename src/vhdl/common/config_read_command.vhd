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
-- Read and execute GPIO/SPI/MDIO configuration commands
--
-- This block implements a byte-stream receiver that parses simple commands
-- to control various configuration interfaces on the Xilinx/Microsemi demo
-- board.  These include an SPI interface, one or more MDIO interfaces for
-- various Ethernet PHY transceivers, as well as discrete GPIO.
--
-- Each frame is parsed as follows:
--    * Host sends opcode byte:
--         0x10        = Start SPI command
--         0x11        = Set new GPO value
--         0x20 - 0x3F = Send MDIO command to Nth output
--         All others reserved
--    * Host sends argument bytes:
--      * In SPI mode, each byte is sent immediately, MSB first.
--        Each RTS frame is a single chip-select transaction.
--      * In MDIO mode, MSB-first bytes are buffered. At end of packet,
--        data is sent in one contiguous burst per 802.3 Part 3 standard.
--        User must include preamble, start, write, and other tokens.
--      * In GPO mode, send bytes MSB-first.  All outputs will be
--        updated simultaneously, at the end of each 32-bit word.
--
-- Note: If MDIO is enabled, then this block requires packet-at-a-time flow
-- control.  i.e., The "valid" strobe for the first byte should not be raised
-- until the entire frame has been received.  This is directly compatible with
-- fifo_packet, but UART-based interfaces will need to buffer frame contents.
--
-- Currently this block is write-only, it doesn't support SPI/MDIO reads
-- or any other status indicators.  These features may be added in a
-- future version.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity config_read_command is
    generic (
    -- Baud rates and port-counts.
    CLKREF_HZ   : integer;          -- Main clock rate (Hz)
    SPI_BAUD    : integer;          -- SPI baud rate (bps), or -1 to disable
    SPI_MODE    : integer;          -- SPI mode index (0-3)
    MDIO_BAUD   : integer;          -- MDIO baud rate (bps), or -1 to disable
    MDIO_COUNT  : integer;          -- Number of MDIO ports
    -- GPO initial state (optional)
    GPO_RSTVAL  : std_logic_vector(31 downto 0) := (others => '0'));
    port (
    -- Command stream
    cmd_data    : in  byte_t;
    cmd_last    : in  std_logic;
    cmd_valid   : in  std_logic;
    cmd_ready   : out std_logic;

    -- SPI command interface
    spi_csb     : out std_logic;    -- Chip select
    spi_sck     : out std_logic;    -- Clock
    spi_sdo     : out std_logic;    -- Data (FPGA to ASIC)

    -- MDIO interface for each port
    mdio_clk    : out std_logic_vector(MDIO_COUNT-1 downto 0);
    mdio_data   : out std_logic_vector(MDIO_COUNT-1 downto 0);
    mdio_oe     : out std_logic_vector(MDIO_COUNT-1 downto 0);

    -- General-purpose outputs (internal or external)
    ctrl_out    : out std_logic_vector(31 downto 0);

    -- System interface
    ref_clk     : in  std_logic;    -- Reference clock
    reset_p     : in  std_logic);
end config_read_command;

architecture rtl of config_read_command is

-- Calculate clock-count per UART bit (round nearest).
subtype mdio_vec is std_logic_vector(MDIO_COUNT-1 downto 0);

-- Upstream flow control.
signal cmd_write    : std_logic;

-- Command/opcode parser.
signal opcode_spi   : std_logic := '0';
signal opcode_gpo   : std_logic := '0';
signal opcode_mdio  : std_logic := '0';
signal mdio_oe_vec  : mdio_vec := (others => '0');

-- Flow-control from the SPI and MDIO state machines.
signal spi_valid    : std_logic := '0';
signal spi_ready    : std_logic;
signal mdio_valid   : std_logic := '0';
signal mdio_ready   : std_logic;

-- Registers for all output signals.
signal gpo_reg      : std_logic_vector(31 downto 0) := GPO_RSTVAL;
signal mdio_clk_i   : std_logic;
signal mdio_data_i  : std_logic;
signal mdio_oe_any  : std_logic;

-- Keep Vivado from renaming signals.
attribute keep : string;
attribute keep of gpo_reg : signal is "true";

begin

-- Drive all output signals.
ctrl_out <= gpo_reg;

gen_mdio : for n in mdio_clk'range generate
    mdio_clk(n)  <= mdio_clk_i and mdio_oe_vec(n);
    mdio_data(n) <= mdio_data_i or not mdio_oe_vec(n);
    mdio_oe(n)   <= mdio_oe_any and mdio_oe_vec(n);
end generate;

-- Upstream flow control.
cmd_ready <= spi_ready and mdio_ready;
cmd_write <= cmd_valid and spi_ready and mdio_ready;

-- Simulation-only: Rule check for upstream flow control.
p_check : process(ref_clk)
    variable mid_frame : std_logic := '0';
begin
    if rising_edge(ref_clk) then
        if (reset_p = '1') then
            mid_frame := '0';
        elsif (cmd_write = '1') then
            mid_frame := not cmd_last;
        elsif (mid_frame = '1') then
            assert (cmd_valid = '1')
                report "All-or-nothing flow-control violation!"
                severity warning;
        end if;
    end if;
end process;

-- Command/opcode parser.
p_opcode : process(ref_clk)
    variable data_int : integer range 0 to 255;
    variable opcode_rcvd : std_logic := '0';
begin
    if rising_edge(ref_clk) then
        if ((reset_p = '1') or (cmd_write = '1' and cmd_last = '1')) then
            -- End of command, clear all opcode flags.
            -- (But leave the separate MDIO enables until next command.)
            opcode_rcvd  := '0';
            opcode_spi   <= '0';
            opcode_gpo   <= '0';
            opcode_mdio  <= '0';
        elsif (cmd_write = '1' and opcode_rcvd = '0') then
            -- First byte in frame, set the new opcode flag.
            data_int := to_integer(unsigned(cmd_data));
            opcode_rcvd := '1';
            if (data_int = 16#10#) then
                opcode_spi <= '1';
            elsif (data_int = 16#11#) then
                opcode_gpo <= '1';
            elsif (data_int >= 16#20# and data_int < 16#20# + MDIO_COUNT) then
                opcode_mdio <= '1';
                for n in mdio_oe_vec'range loop
                    mdio_oe_vec(n) <= bool2bit(data_int = 16#20# + n);
                end loop;
            else
                report "Unknown opcode: " &
                    integer'image(data_int)
                    severity warning;
            end if;
        end if;
    end if;
end process;

-- GPO state machine.
p_gpo : process(ref_clk)
    variable byte_count : integer range 0 to 3 := 0;
    variable word_sreg  : std_logic_vector(23 downto 0) := (others => '0');
begin
    if rising_edge(ref_clk) then
        -- Update the final output register.
        if (reset_p = '1') then
            gpo_reg <= GPO_RSTVAL;
        elsif (cmd_write = '1' and byte_count = 3) then
            gpo_reg <= word_sreg & cmd_data;
        end if;

        -- Update shift register, MSB first.
        if (opcode_gpo = '1' and cmd_write = '1') then
            word_sreg := word_sreg(15 downto 0) & cmd_data;
        end if;

        -- Update counter state.
        if (opcode_gpo = '0') then
            byte_count := 0;
        elsif (cmd_write = '1' and byte_count < 3) then
            byte_count := byte_count + 1;
        elsif (cmd_write = '1') then
            byte_count := 0;
        end if;
    end if;
end process;

-- SPI interface
gen_spi_en : if (SPI_BAUD > 0) generate
    spi_valid <= cmd_valid and opcode_spi;
    u_spi : entity work.io_spi_clkout
        generic map(
        CLKREF_HZ   => CLKREF_HZ,
        SPI_BAUD    => SPI_BAUD,
        SPI_MODE    => SPI_MODE)
        port map(
        cmd_data    => cmd_data,
        cmd_last    => cmd_last,
        cmd_valid   => spi_valid,
        cmd_ready   => spi_ready,
        spi_csb     => spi_csb,
        spi_sck     => spi_sck,
        spi_sdo     => spi_sdo,
        ref_clk     => ref_clk,
        reset_p     => reset_p);
end generate;

gen_spi_no : if (SPI_BAUD <= 0) generate
    spi_ready   <= '1';
    spi_csb     <= '1';
    spi_sck     <= '0';
    spi_sdo     <= '0';
end generate;

-- MDIO interface
gen_mdio_en : if (MDIO_BAUD > 0) generate
    mdio_valid <= cmd_valid and opcode_mdio;
    u_mdio : entity work.io_mdio_writer
        generic map(
        CLKREF_HZ   => CLKREF_HZ,
        MDIO_BAUD   => MDIO_BAUD)
        port map(
        cmd_data    => cmd_data,
        cmd_last    => cmd_last,
        cmd_valid   => mdio_valid,
        cmd_ready   => mdio_ready,
        mdio_clk    => mdio_clk_i,
        mdio_data   => mdio_data_i,
        mdio_oe     => mdio_oe_any,
        ref_clk     => ref_clk,
        reset_p     => reset_p);
end generate;

gen_mdio_no : if (MDIO_BAUD <= 0) generate
    mdio_ready  <= '1';
    mdio_clk_i  <= '1';
    mdio_data_i <= '1';
    mdio_oe_any <= '0';
end generate;

end rtl;
