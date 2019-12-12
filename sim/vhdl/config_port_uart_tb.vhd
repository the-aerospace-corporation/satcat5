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
-- Testbench for demo-board SPI+MDIO configuration using UART
--
-- This is the unit test for the config_port_uart block, which parses
-- simple UART commands to execute various control tasks, like changing
-- a GPIO flag or sending a few bytes over an MDIO or SPI bus.
--
-- The complete test takes just under 15.1 milliseconds.
--

library ieee;
use     ieee.math_real.all;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_types.all;
use     work.eth_frame_common.all;  -- For byte_t

entity config_port_uart_tb is
    -- Unit testbench top level, no I/O ports
end config_port_uart_tb;

architecture tb of config_port_uart_tb is

constant UART_BAUD : integer := 921600;

-- Clock and reset generation
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Unit under test
signal uart_host    : std_logic := '1';
signal spi_csb      : std_logic;
signal spi_sck      : std_logic;
signal spi_sdo      : std_logic;
signal mdio_clk     : std_logic;
signal mdio_data    : std_logic;
signal mdio_oe      : std_logic;
signal ctrl_out     : std_logic_vector(31 downto 0);

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

-- Unit under test
uut : entity work.config_port_uart
    generic map(
    CLKREF_HZ   => 100000000,
    UART_BAUD   => UART_BAUD,
    SPI_BAUD    => 2000000,
    SPI_MODE    => 1,
    MDIO_BAUD   => 2000000,
    MDIO_COUNT  => 1)
    port map(
    uart_rx     => uart_host,
    spi_csb     => spi_csb,
    spi_sck     => spi_sck,
    spi_sdo     => spi_sdo,
    mdio_clk(0)  => mdio_clk,
    mdio_data(0) => mdio_data,
    mdio_oe(0)  => mdio_oe,
    ctrl_out    => ctrl_out,
    ref_clk     => clk_100,
    ext_reset_p => reset_p);

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

    -- Send a single byte over UART.
    procedure uart_byte(data : byte_t) is
        constant ONE_BIT : time := 1000 ms / real(UART_BAUD);
    begin
        uart_host <= '0';           -- Start bit
        wait for ONE_BIT;
        for b in 0 to 7 loop        -- LSB first within each byte
            uart_host <= data(b);
            wait for ONE_BIT;       -- 8x Data bit
        end loop;
        uart_host <= '1';           -- Stop bit
        wait for ONE_BIT;
    end procedure;

    -- Send SLIP-encoded command over UART.
    procedure uart_send(data : std_logic_vector) is
        constant nbytes : integer := data'length / 8;
        variable next_byte : byte_t := (others => '0');
    begin
        -- Update diagnostic outputs
        cmd_index  <= cmd_index + 1;
        cmd_opcode <= data(8*nbytes-1 downto 8*nbytes-8);

        -- SLIP-encode each byte before sending.
        for n in nbytes-1 downto 0 loop -- Input is big-endian
            next_byte := data(8*n+7 downto 8*n);
            case next_byte is
                when x"C0" =>   -- Escape END token
                    uart_byte(x"DB");
                    uart_byte(x"DC");
                when x"DB" =>   -- Escape ESC token
                    uart_byte(x"DB");
                    uart_byte(x"DD");
                when others =>  -- Normal character
                    uart_byte(next_byte);
            end case;
        end loop;

        -- Send the end-of-frame token.
        uart_byte(x"C0");
    end procedure;

    -- Concatenate opcode and parameters.
    -- (Because ModelSim insists on flipping to/downto...)
    function make_cmd(opcode, params : std_logic_vector) return std_logic_vector is
        variable temp : std_logic_vector(params'length+7 downto 0) := opcode & params;
    begin
        return temp;
    end function;

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
        uart_send(make_cmd(OPCODE, params));
        wait for 10 us; -- Wait for execution

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
        uart_send(make_cmd(OPCODE, params));
        wait for 10 us;             -- Wait for start of execution
        wait until (mdio_oe = '0'); -- Wait for completion

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

        -- Send the command.
        uart_send(make_cmd(OPCODE, params));
        wait for 10 us;             -- Wait for start of execution
        wait until (spi_csb = '1'); -- Wait for completion

        -- Confirm execution.
        assert (spi_rcvd(8*nbytes-1 downto 0) = params)
            report "SPI mismatch" severity error;
    end procedure;

begin
    wait until (reset_p = '0');
    wait for 1 us;

    -- Some SLIP decoders require a preceeding START token.
    uart_byte(x"C0");

    for n in 1 to 100 loop
        uniform(seed1, seed2, rand);
        case integer(floor(rand*4.0)) is
            when 0 => gpo_check;
            when 1 => mdio_check(4);
            when 2 => spi_check(8);
            when 3 => spi_check(16);
            when others => null;
        end case;
    end loop;

    report "All tests completed!";
    wait;
end process;

end tb;
