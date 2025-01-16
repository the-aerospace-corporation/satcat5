--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the UART interface blocks (Tx, Rx)
--
-- This testbench connects the transmit and receive UARTs back-to-back,
-- to confirm successful bidirectional communication at different baud
-- rates and the logic that applies and detect "break" signals.
--
-- The complete test takes 2.6 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.byte_t;
use     work.router_sim_tools.all;

entity io_uart_tb is
    -- Unit test has no top-level I/O.
end io_uart_tb;

architecture tb of io_uart_tb is

constant RATE_WIDTH : positive := 8;

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Tx and Rx streams.
signal tx_data      : byte_t := (others => 'X');
signal tx_valid     : std_logic := '0';
signal tx_ready     : std_logic;
signal tx_break     : std_logic := '0';

signal rx_data      : byte_t;
signal rx_write     : std_logic;
signal rx_break     : std_logic;

-- Other test and control signals.
signal uart         : std_logic;
signal rate_div     : unsigned(RATE_WIDTH-1 downto 0) := (others => '1');
signal ref_data     : byte_t;
signal ref_wren     : std_logic;
signal ref_valid    : std_logic;
signal test_index   : natural := 0;

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;  -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;

-- FIFO for reference data (Rx should always match delayed Tx).
ref_wren <= tx_valid and tx_ready;

u_ref : entity work.fifo_smol_sync
    generic map(IO_WIDTH => 8)
    port map(
    in_data     => tx_data,
    in_write    => ref_wren,
    out_data    => ref_data,
    out_valid   => ref_valid,
    out_read    => rx_write,
    clk         => clk_100,
    reset_p     => reset_p);

-- Unit under test.
uut_tx : entity work.io_uart_tx
    generic map (
    RATE_WIDTH  => RATE_WIDTH)
    port map(
    uart_txd    => uart,
    tx_data     => tx_data,
    tx_valid    => tx_valid,
    tx_ready    => tx_ready,
    tx_break    => tx_break,
    rate_div    => rate_div,
    refclk      => clk_100,
    reset_p     => reset_p);

uut_rx : entity work.io_uart_rx
    generic map(
    RATE_WIDTH  => RATE_WIDTH,
    DEBUG_WARN  => false)
    port map(
    uart_rxd    => uart,
    rx_data     => rx_data,
    rx_write    => rx_write,
    rx_break    => rx_break,
    rate_div    => rate_div,
    refclk      => clk_100,
    reset_p     => reset_p);

-- Check received data against reference stream.
p_check : process(clk_100)
begin
    if rising_edge(clk_100) then
        if (ref_valid = '0') then
            assert (rx_write = '0') report "DATA unexpected" severity error;
        elsif (rx_write = '1') then
            assert (rx_data = ref_data) report "DATA mismatch" severity error;
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    -- Transmit a few bytes at the current baud rate.
    -- Optionally assert the "break" request after N clock cycles.
    procedure test_one(data: std_logic_vector; brk_start, brk_len : natural) is
        variable tx_len  : natural := data'length / 8;
        variable tx_idx  : natural := 0;
        variable rx_idx  : natural := 0;
        variable brk_rem : natural := brk_start + brk_len;
        variable brk_rx  : natural := 0;
    begin
        -- Update the test index.
        report "Starting test #" & integer'image(test_index + 1);
        test_index <= test_index + 1;
        -- Transmit each byte in the sequence, with a parallel state
        -- machine that asserts BREAK request at the designated time.
        wait until rising_edge(clk_100);
        while (tx_idx < tx_len or rx_idx < tx_len or brk_rem > 0) loop
            -- Transmit stream flow-control.
            if (tx_valid = '0' or tx_ready = '1') then
                if (tx_idx < tx_len) then
                    tx_data  <= get_packet_bytes(data, tx_idx, 1);
                    tx_valid <= '1';
                    tx_idx   := tx_idx + 1;
                else
                    tx_data  <= (others => 'X');
                    tx_valid <= '0';
                end if;
            end if;
            -- Count received bytes.
            if (rx_write = '1') then
                rx_idx := rx_idx + 1;
            end if;
            if (rx_break = '1') then
                brk_rx := brk_rx + 1;
            end if;
            -- Update the "tx_break" signal.
            tx_break <= bool2bit(0 < brk_rem and brk_rem <= brk_len);
            if (brk_rem > brk_len) then
                tx_break <= '0';    -- Waiting for start.
                brk_rem  := brk_rem - 1;
            elsif (brk_rem > 0) then
                tx_break <= '1';    -- Waiting for end.
                brk_rem  := brk_rem - 1;
            else
                tx_break <= '0';    -- Done / idle.
            end if;
            wait until rising_edge(clk_100);
        end loop;
        -- If we asserted BREAK during the test, confirm the receiver noticed.
        assert (brk_len = 0 or brk_rx > 0)
            report "Missing BREAK detect" severity error;
    end procedure;

    -- Run a sequence of tests at the specified rate divider.
    procedure run_all(rate : positive) is
    begin
        -- Set the baud-rate for this series of tests.
        rate_div <= to_unsigned(rate, RATE_WIDTH);
        -- Run a few basic tests with data only.
        test_one(rand_bytes(12), 0, 0);
        test_one(rand_bytes(256), 0, 0);
        -- Request a "break" signal at various time-offsets.
        -- (Trying to find edge cases in the transition between modes.)
        for n in 100 to 200 loop
            test_one(rand_bytes(16), n, 20*rate);
        end loop;
    end procedure;
begin
    -- Drive all signals controlled by this process.
    rate_div    <= (others => '1');
    tx_data     <= (others => 'X');
    tx_valid    <= '0';
    tx_break    <= '0';
    wait until reset_p = '0';
    wait for 1 us;

    -- Repeat the test series at different baud rates.
    run_all(2);
    run_all(10);

    report "All tests completed!";
    wait;
end process;

end tb;
