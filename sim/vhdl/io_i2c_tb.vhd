--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the I2C interface blocks (controller and peripheral)
--
-- This testbench connects both I2C-interface variants back-to-back,
-- to confirm successful bidirectional communication.
--
-- The test runs in about 0.8 msec.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.i2c_constants.all;
use     work.router_sim_tools.all;

entity io_i2c_tb is
    -- Unit testbench, no I/O ports.
end io_i2c_tb;

architecture tb of io_i2c_tb is

-- I2C address for the device under test:
constant DEV_ADDR   : i2c_addr_t := "1011101";
constant DEV_WRITE  : i2c_data_t := DEV_ADDR & '0';
constant DEV_READ   : i2c_data_t := DEV_ADDR & '1';

-- Set clock-divider for 1 Mbps operation:
constant CFG_CLKDIV : i2c_clkdiv_t :=
    i2c_get_clkdiv(100_000_000, 1_000_000);

-- Clock and reset generation
signal clk_100  : std_logic := '0';
signal reset_p  : std_logic := '1';

-- Peripheral signals
signal dev_rx_data  : i2c_data_t;
signal dev_rx_write : std_logic;
signal dev_rx_start : std_logic;
signal dev_rx_rdreq : std_logic;
signal dev_rx_stop  : std_logic;
signal dev_tx_data  : i2c_data_t;
signal dev_tx_valid : std_logic;
signal dev_tx_ready : std_logic;

-- I2C bus
signal sclk_i       : std_logic;
signal sclk_o       : std_logic_vector(1 downto 0);
signal sdata_i      : std_logic;
signal sdata_o      : std_logic_vector(1 downto 0);

-- Controller signals
signal tx_opcode    : i2c_cmd_t;
signal tx_data      : i2c_data_t;
signal tx_valid     : std_logic;
signal tx_ready     : std_logic;
signal rx_data      : i2c_data_t;
signal rx_write     : std_logic;
signal bus_stop     : std_logic;
signal bus_noack    : std_logic;

-- High-level test control
signal test_index   : natural := 0;
signal cmd_opcode   : i2c_cmd_t := CMD_DELAY;
signal cmd_data     : i2c_data_t := (others => '0');
signal cmd_write    : std_logic := '0';
signal cmd_run      : std_logic := '0';
signal fifo_valid   : std_logic;

begin

-- Clock and reset generation
clk_100 <= not clk_100 after 5.00 ns;
reset_p <= '0' after 1 us;

-- Model an I2C peripheral with 256 registers:
--  * Register write: Write register address then contents
--  * Register read: Write register address, restart, read contents
p_dev : process(clk_100)
    type array_t is array(255 downto 0) of i2c_data_t;
    variable mem    : array_t := (others => (others => '0'));
    variable reg    : integer := 0;
    variable wfirst : std_logic := '1';
    variable wdog   : natural := 0;
begin
    if rising_edge(clk_100) then
        -- Reset the "first byte" flag on each START token.
        if (reset_p = '1' or dev_rx_start = '1') then
            wfirst := '1';
        end if;

        -- Handle writes:
        if (dev_rx_write = '1') then
            if (wfirst = '1') then
                -- First write sets the register address.
                reg := u2i(dev_rx_data);
                wfirst := '0';
            else
                -- Subsequent writes set new value and auto-incrment.
                mem(reg) := dev_rx_data;
                reg := (reg + 1) mod 256;
            end if;
        end if;

        -- Handle reads:
        if (reset_p = '1') then
            dev_tx_data  <= (others => '0');
            dev_tx_valid <= '0';    -- Global reset
        elsif (dev_rx_rdreq = '1') then
            assert (dev_tx_valid = '0' or dev_tx_ready = '1')
                report "Unexpected read-request." severity error;
            dev_tx_data  <= mem(reg);
            dev_tx_valid <= '1';    -- Read next register
            reg := (reg + 1) mod 256;
        elsif (dev_tx_ready = '1') then
            dev_tx_valid <= '0';    -- Data consumed
        end if;

        -- Other sanity checks:
        if (dev_rx_start = '1' or dev_rx_stop = '1') then
            assert (dev_tx_valid = '0')
                report "Unexpected read state." severity error;
        end if;

        if (sclk_i = '1') then
            wdog := 0;
        else
            wdog := wdog + 1;
            if (wdog = 8*CFG_CLKDIV) then
                report "Excess clock-stretching." severity error;
            end if;
        end if;
    end if;
end process;

-- Unit under test: Peripheral
uut_dev : entity work.io_i2c_peripheral
    port map(
    sclk_o      => sclk_o(0),
    sclk_i      => sclk_i,
    sdata_o     => sdata_o(0),
    sdata_i     => sdata_i,
    i2c_addr    => DEV_ADDR,
    rx_data     => dev_rx_data,
    rx_write    => dev_rx_write,
    rx_start    => dev_rx_start,
    rx_rdreq    => dev_rx_rdreq,
    rx_stop     => dev_rx_stop,
    tx_data     => dev_tx_data,
    tx_valid    => dev_tx_valid,
    tx_ready    => dev_tx_ready,
    ref_clk     => clk_100,
    reset_p     => reset_p);

-- I2C bus is active-low with a central pullup resistor.
-- (i.e., Each signal is "low" if any device pulls it low, high otherwise.)
sclk_i  <= and_reduce(sclk_o);
sdata_i <= and_reduce(sdata_o);

-- Unit under test: Controller
uut_ctrl : entity work.io_i2c_controller
    port map(
    sclk_o      => sclk_o(1),
    sclk_i      => sclk_i,
    sdata_o     => sdata_o(1),
    sdata_i     => sdata_i,
    cfg_clkdiv  => CFG_CLKDIV,
    tx_opcode   => tx_opcode,
    tx_data     => tx_data,
    tx_valid    => tx_valid,
    tx_ready    => tx_ready,
    rx_data     => rx_data,
    rx_write    => rx_write,
    bus_stop    => bus_stop,
    bus_noack   => bus_noack,
    ref_clk     => clk_100,
    reset_p     => reset_p);

-- Small FIFO for queueing test commands.
tx_valid <= fifo_valid and cmd_run;

u_fifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => cmd_data'length,
    META_WIDTH  => cmd_opcode'length)
    port map(
    in_data     => cmd_data,
    in_meta     => cmd_opcode,
    in_write    => cmd_write,
    out_data    => tx_data,
    out_meta    => tx_opcode,
    out_valid   => fifo_valid,
    out_read    => tx_ready,
    clk         => clk_100,
    reset_p     => reset_p);

-- High-level test control.
p_test : process
    -- Get Nth byte starting from MSB.
    function get_byte(x : std_logic_vector; n : natural) return i2c_data_t is
        constant tmp : i2c_data_t := x(x'left-8*n downto x'left-8*n-7);
    begin
        return tmp;
    end function;

    -- Queue up a single command.
    procedure queue(op : i2c_cmd_t; dat : i2c_data_t := (others => '0')) is
    begin
        wait until rising_edge(clk_100);
        cmd_opcode  <= op;
        cmd_data    <= dat;
        cmd_write   <= '1';
        wait until rising_edge(clk_100);
        cmd_write   <= '0';
    end procedure;

    -- Execute queued commands.
    procedure execute(noack : std_logic := '0'; data : std_logic_vector := "") is
        constant nread : natural := data'length / 8;
    begin
        -- Unlock command FIFO to start the test.
        report "Starting test #" & integer'image(test_index+1);
        test_index  <= test_index + 1;
        cmd_run     <= '1';
        -- Check each read word.
        for n in 0 to nread-1 loop
            wait until rising_edge(rx_write);
            assert (rx_data = get_byte(data, n))
                report "Read-data mismatch." severity error;
        end loop;
        -- Wait until we're done and check NOACK flag.
        wait until rising_edge(bus_stop);
        assert (bus_noack = noack)
            report "NOACK mismatch." severity error;
        -- Cleanup for next test.
        wait for 10 us;
        assert (sclk_i = '1' and sdata_i = '1')
            report "Expected idle bus." severity error;
        cmd_run <= '0';
    end procedure;

    -- Execute a bus transaction with another device.
    procedure i2c_other(nbytes : positive) is
        variable addr : i2c_data_t := DEV_WRITE;
    begin
        -- Generate a random address that's not the DUT.
        while (addr = DEV_WRITE or addr = DEV_READ) loop
            addr := rand_vec(8);
        end loop;
        -- Queue up the appropriate commands.
        if (addr(0) = '1') then
            queue(CMD_START);   -- Read
            queue(CMD_TXBYTE, addr);
            for n in 1 to nbytes-1 loop
                queue(CMD_RXBYTE);
            end loop;
            queue(CMD_RXFINAL);
            queue(CMD_STOP);
        else
            queue(CMD_START);   -- Write
            queue(CMD_TXBYTE, addr);
            for n in 1 to nbytes loop
                queue(CMD_TXBYTE, rand_vec(8));
            end loop;
            queue(CMD_STOP);
        end if;
        -- Execute transaction.
        execute(noack => '1');
    end procedure;

    -- Execute one or more register writes.
    procedure i2c_write(regaddr : natural; data : std_logic_vector) is
        constant nbytes : positive := data'length / 8;
    begin
        -- Queue up the write command.
        queue(CMD_START);
        queue(CMD_TXBYTE, DEV_WRITE);
        queue(CMD_TXBYTE, i2s(regaddr, 8));
        for n in 0 to nbytes-1 loop
            queue(CMD_TXBYTE, get_byte(data, n));
        end loop;
        queue(CMD_STOP);
        -- Execute.
        execute(noack => '0');
    end procedure;

    -- Execute one or more register reads, checking reply.
    procedure i2c_read(regaddr : natural; data : std_logic_vector) is
        constant nbytes : positive := data'length / 8;
    begin
        -- Queue up the read command.
        queue(CMD_START);
        queue(CMD_TXBYTE, DEV_WRITE);
        queue(CMD_TXBYTE, i2s(regaddr, 8));
        queue(CMD_RESTART);
        queue(CMD_TXBYTE, DEV_READ);
        for n in 1 to nbytes-1 loop
            queue(CMD_RXBYTE);
        end loop;
        queue(CMD_RXFINAL);
        queue(CMD_STOP);
        -- Execute.
        execute(data => data);
    end procedure;

    constant TESTVEC1 : std_logic_vector(15 downto 0) := x"1234";
    constant TESTVEC2 : std_logic_vector(63 downto 0) := x"DEADBEEFCAFED00D";
begin
    -- Wait for end of reset.
    wait for 2 us;

    -- Short write, then read back.
    i2c_write(5, TESTVEC1);
    i2c_other(3);
    i2c_read(5, TESTVEC1);

    -- Longer write, then read back in parts.
    i2c_write(123, TESTVEC2);
    i2c_other(5);
    i2c_read(123, TESTVEC2(63 downto 32));
    i2c_other(6);
    i2c_read(127, TESTVEC2(31 downto 24));
    i2c_read(128, TESTVEC2(23 downto 16));
    i2c_read(129, TESTVEC2(15 downto 8));
    i2c_read(130, TESTVEC2(7 downto 0));
    i2c_other(10);

    report "All tests completed!";
    wait;
end process;

end tb;
