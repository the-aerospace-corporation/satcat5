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
-- Testbench for SPI+MDIO configuration and status reporting using Ethernet
--
-- This is the unit test for the config_port_eth block, which parses
-- simple Ethernet frames to execute various control tasks, like changing
-- a GPIO flag or sending a few bytes over an MDIO or SPI bus.
--
-- The status-reporting function of this block is already covered by the
-- "config_send_status" unit test; that logic is not repeated here.
--
-- The complete test takes less than 3.2 milliseconds.
--

library ieee;
use     ieee.math_real.all;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;  -- For byte_t
use     work.switch_types.all;      -- For port_tx_*

entity config_port_eth_tb is
    -- Unit testbench top level, no I/O ports
end config_port_eth_tb;

architecture tb of config_port_eth_tb is

-- Set EtherType for configuration commands
constant CFG_ETYPE : std_logic_vector(15 downto 0) := x"5C01";

-- Clock and reset generation
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Unit under test
signal tx_data      : port_tx_m2s;
signal tx_ctrl      : port_tx_s2m;
signal spi_csb      : std_logic;
signal spi_sck      : std_logic;
signal spi_sdo      : std_logic;
signal mdio_clk     : std_logic;
signal mdio_data    : std_logic;
signal mdio_oe      : std_logic;
signal ctrl_out     : std_logic_vector(31 downto 0);

-- Ethernet data stream
signal eth_data     : byte_t := (others => '0');
signal eth_last     : std_logic := '0';
signal eth_valid    : std_logic := '0';
signal eth_ready    : std_logic;

-- SPI and MDIO receivers
signal spi_rcvd     : std_logic_vector(127 downto 0) := (others => '0');
signal mdio_rcvd    : std_logic_vector(127 downto 0) := (others => '0');

-- Overall test status
signal cmd_index    : integer := 0;
signal cmd_opcode   : byte_t := (others => '0');

begin

-- Clock and reset generation
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Remap signal names for the Ethernet stream.
eth_ready       <= tx_ctrl.ready;
tx_data.data    <= eth_data;
tx_data.last    <= eth_last;
tx_data.valid   <= eth_valid;

-- Unit under test
uut : entity work.config_port_eth
    generic map(
    CLKREF_HZ       => 100000000,
    SPI_BAUD        => 2000000,
    SPI_MODE        => 1,
    MDIO_BAUD       => 2000000,
    MDIO_COUNT      => 1,
    CFG_ETYPE       => CFG_ETYPE,
    STAT_BYTES      => 8)       -- Not tested
    port map(
    rx_data         => open,    -- Not tested
    tx_data         => tx_data,
    tx_ctrl         => tx_ctrl,
    status_val      => (others => '0'),
    spi_csb         => spi_csb,
    spi_sck         => spi_sck,
    spi_sdo         => spi_sdo,
    mdio_clk(0)     => mdio_clk,
    mdio_data(0)    => mdio_data,
    mdio_oe(0)      => mdio_oe,
    ctrl_out        => ctrl_out,
    ref_clk         => clk_100,
    ext_reset_p     => reset_p);

-- SPI and MDIO receivers
p_spi : process(spi_sck)
begin
    if falling_edge(spi_sck) and (spi_csb = '0') then
        -- Just a big shift register, MSB first.
        -- Use falling edge of clock to mimic Mode-1 receiver.
        spi_rcvd <= spi_rcvd(spi_rcvd'left-1 downto 0) & spi_sdo;
    end if;
end process;

p_mdio : process(mdio_clk)
begin
    if rising_edge(mdio_clk) then
        -- Just a big shift register, MSB first.
        mdio_rcvd <= mdio_rcvd(mdio_rcvd'left-1 downto 0) & mdio_data;
    end if;
end process;

p_mcheck :process(clk_100)
    variable mdio_data_d : std_logic := '1';
begin
    if rising_edge(clk_100) then
        -- Sanity check: Data should only change when clock is low.
        if (mdio_data /= mdio_data_d) then
            assert (mdio_clk = '0')
                report "Unexpected MDIO transition" severity error;
        end if;
        mdio_data_d := mdio_data;
    end if;
end process;

-- Overall test control
p_test : process
    -- PRNG state
    variable seed1  : positive := 1234;
    variable seed2  : positive := 5678;
    variable rand   : real := 0.0;

    -- Send a single byte over the AXI pipe.
    procedure send_byte(data : byte_t; last : std_logic) is
    begin
        -- First byte --> Wait until next clock edge
        if (eth_valid = '0') then
            wait until rising_edge(tx_ctrl.clk);
        end if;
        -- Latch and hold the next byte until it's accepted.
        eth_data    <= data;
        eth_last    <= last;
        eth_valid   <= '1';
        wait until rising_edge(tx_ctrl.clk) and (eth_ready = '1');
        -- Last byte --> Idle for one clock cycle
        if (last = '1') then
            eth_data    <= (others => '0');
            eth_last    <= '0';
            eth_valid   <= '0';
            wait until rising_edge(tx_ctrl.clk);
        end if;
    end procedure;

    -- Send an entire frame over the AXI pipe.
    procedure send_frame(data : std_logic_vector) is
        constant nbytes : integer := data'length / 8;
        variable next_byte : byte_t := (others => '0');
    begin
        -- Update diagnostic outputs
        cmd_index  <= cmd_index + 1;
        cmd_opcode <= data(8*nbytes-97 downto 8*nbytes-104);

        -- Send each byte.
        for n in nbytes-1 downto 0 loop -- Input is big-endian
            next_byte := data(8*n+7 downto 8*n);
            send_byte(next_byte, bool2bit(n=0));
        end loop;

        -- Short delay before returning.
        wait for 10 us;
    end procedure;

    -- Concatenate opcode and parameters.
    -- (Because ModelSim insists on flipping to/downto...)
    function make_cmd(opcode, params : std_logic_vector) return std_logic_vector is
        constant HEADER : std_logic_vector(111 downto 0) :=
            x"536174436174" & x"DEADBEEFCAFE" & CFG_ETYPE;
        variable temp : std_logic_vector(params'length+119 downto 0) :=
            HEADER & opcode & params;
    begin
        return temp;
    end function;

    -- Send a command with a different EtherType, and confirm null effect.
    procedure null_check is
        constant NULL_PKT : std_logic_vector(151 downto 0) :=
            x"536174436174" & x"DEADBEEFCAFE" & x"1234" & x"11" & x"0BADC0DE";
        variable ctrl_prev : std_logic_vector(31 downto 0) := ctrl_out;
    begin
        -- Send the command, which should be filtered.
        send_frame(NULL_PKT);

        -- Confirm non-execution.
        assert (ctrl_out = ctrl_prev)
            report "Command not filtered" severity error;
    end procedure;

    -- Send random GPO command and check successful execution.
    procedure gpo_check is
        constant OPCODE : byte_t := x"11";
        variable params : std_logic_vector(31 downto 0);
    begin
        -- Randomize command parameters.
        for n in params'range loop
            uniform(seed1, seed2, rand);
            params(n) := bool2bit(rand < 0.5);
        end loop;

        -- Send the command.
        send_frame(make_cmd(OPCODE, params));

        -- Confirm execution.
        assert (ctrl_out = params)
            report "GPO mismatch" severity error;
    end procedure;

    -- Send random MDIO command and check successful execution.
    procedure mdio_check(constant nbytes : integer) is
        constant OPCODE : byte_t := x"20";
        variable params : std_logic_vector(8*nbytes-1 downto 0);
    begin
        -- Randomize command parameters.
        for n in params'range loop
            uniform(seed1, seed2, rand);
            params(n) := bool2bit(rand < 0.5);
        end loop;

        -- Send the command and wait for completion.
        send_frame(make_cmd(OPCODE, params));
        wait until rising_edge(clk_100) and (mdio_oe = '0');

        -- Confirm execution.
        assert (mdio_rcvd(8*nbytes-1 downto 0) = params)
            report "MDIO mismatch" severity error;
    end procedure;

    -- Send random SPI command and check successful execution.
    procedure spi_check(constant nbytes : integer) is
        constant OPCODE : byte_t := x"10";
        variable params : std_logic_vector(8*nbytes-1 downto 0);
    begin
        -- Randomize command parameters.
        for n in params'range loop
            uniform(seed1, seed2, rand);
            params(n) := bool2bit(rand < 0.5);
        end loop;

        -- Send the command and wait for completion.
        send_frame(make_cmd(OPCODE, params));
        wait until rising_edge(clk_100) and (spi_csb = '1');

        -- Confirm execution.
        assert (spi_rcvd(8*nbytes-1 downto 0) = params)
            report "SPI mismatch" severity error;
    end procedure;

begin
    wait until (reset_p = '0');
    wait for 1 us;

    for n in 1 to 100 loop
        uniform(seed1, seed2, rand);
        case integer(floor(rand*5.0)) is
            when 0 => null_check;
            when 1 => gpo_check;
            when 2 => mdio_check(4);
            when 3 => spi_check(8);
            when 4 => spi_check(16);
            when others => null;
        end case;
    end loop;

    report "All tests completed!";
    wait;
end process;

end tb;
