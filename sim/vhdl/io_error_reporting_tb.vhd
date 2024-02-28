--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the UART-based error-reporting block
--
-- This testbench examines the error-reporting block output to confirm
-- correct operation under various conditions:
--      * No errors (periodic "OK" message)
--      * One error at a time (sparse)
--      * One error at a time (repeated)
--      * Multiple concurrent errors
--      * Randomized test sequences
--
-- The test will run indefinitely, with adequate coverage after ~10 msec.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.common_primitives.sync_toggle2pulse;

entity io_error_reporting_tb is
    -- Unit testbench top level, no I/O ports
end io_error_reporting_tb;

architecture tb of io_error_reporting_tb is

constant CLK_HZ     : integer := 100000000; -- Main clock rate (Hz)
constant OUT_BAUD   : integer := 921600;    -- UART baud rate (bps)
constant OK_CLOCKS  : integer := 20000;     -- Clocks per "OK" report
constant ERR_COUNT  : integer := 8;         -- Number of messages (max 16)

-- Clock and reset generation
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Unit under test.
signal err_uart     : std_logic;
signal err_strobe   : std_logic_vector(ERR_COUNT-1 downto 0) := (others => '0');

-- UART receiver.
signal rcvd_byte_t  : std_logic := '0';     -- Toggle (asynchronous)
signal rcvd_byte_s  : std_logic := '0';     -- Strobe (clk_100)
signal rcvd_data    : unsigned(7 downto 0) := (others => '0');

-- Message sorting.
type count_array is array(ERR_COUNT downto 0) of integer;
signal msg_count    : count_array := (others => 0);
signal msg_total    : integer := 0;
signal msg_idle     : integer := 0;

-- Test status.
signal test_index   : integer := 0;
signal test_reset   : std_logic := '0';
signal test_ref     : count_array := (others => 0);

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Unit under test.
uut: entity work.io_error_reporting
    generic map(
    CLK_HZ      => CLK_HZ,
    OUT_BAUD    => OUT_BAUD,
    OK_CLOCKS   => OK_CLOCKS,
    START_MSG   => "Startup",
    ERR_COUNT   => ERR_COUNT,
    ERR_MSG00   => "0a",
    ERR_MSG01   => "1bB",
    ERR_MSG02   => "2cCc",
    ERR_MSG03   => "3d",
    ERR_MSG04   => "4eE",
    ERR_MSG05   => "5fFf",
    ERR_MSG06   => "6g",
    ERR_MSG07   => "7hH")
    port map(
    err_uart    => err_uart,
    err_strobe  => err_strobe,
    err_clk     => clk_100,
    reset_p     => reset_p);

-- UART receiver is fully asynchronous.
p_uart : process
    constant HALF_BIT : time := (500 ms) / OUT_BAUD;
begin
    -- Wait for start bit.
    wait until falling_edge(err_uart);

    -- First bit starts 1.5 bit-intervals after falling edge.
    wait for HALF_BIT;
    for n in 0 to 7 loop    -- LSB first
        wait for 2*HALF_BIT;
        rcvd_data(n) <= err_uart;
    end loop;

    -- Send the byte-ready signal, then idle until stop bit.
    rcvd_byte_t <= not rcvd_byte_t;
    wait for 2*HALF_BIT;
end process;

-- Re-synchronize the byte-ready strobe.
hs_rcvd : sync_toggle2pulse
    port map(
    in_toggle   => rcvd_byte_t,
    out_strobe  => rcvd_byte_s,
    out_clk     => clk_100);

-- Count received messages based on received bytes.
p_count : process(clk_100)
begin
    if rising_edge(clk_100) then
        if (test_reset = '1') then
            -- Reset counters at start of test.
            msg_count   <= (others => 0);
            msg_total   <= 0;
        elsif (rcvd_byte_s = '1') then
            -- Check received character.  If it's the start of a known message,
            -- count it.  Ignore everything else.
            case rcvd_data is
                when x"30" => msg_count(0) <= msg_count(0) + 1; -- ASCII '0' (MSG00)
                when x"31" => msg_count(1) <= msg_count(1) + 1; -- ASCII '1' (MSG01)
                when x"32" => msg_count(2) <= msg_count(2) + 1; -- ASCII '2' (MSG02)
                when x"33" => msg_count(3) <= msg_count(3) + 1; -- ASCII '3' (MSG03)
                when x"34" => msg_count(4) <= msg_count(4) + 1; -- ASCII '4' (MSG04)
                when x"35" => msg_count(5) <= msg_count(5) + 1; -- ASCII '5' (MSG05)
                when x"36" => msg_count(6) <= msg_count(6) + 1; -- ASCII '6' (MSG06)
                when x"37" => msg_count(7) <= msg_count(7) + 1; -- ASCII '7' (MSG07)
                when x"4F" => msg_count(8) <= msg_count(8) + 1; -- ASCII 'O' ("OK")
                when x"0A" => msg_total <= msg_total + 1;       -- ASCII Line-feed
                when x"00" => report "Unexpected NULL character" severity error;
                when others => null;
            end case;
        end if;

        -- Maintain idle counter.
        if (test_reset = '1' or err_uart = '0') then
            msg_idle <= 0;
        else
            msg_idle <= msg_idle + 1;
        end if;
    end if;
end process;

-- Overall test control, including error-strobe generation.
p_test : process
    -- PRNG state
    variable seed1  : positive := 1234;
    variable seed2  : positive := 5678;
    variable rand   : real := 0.0;

    -- Initial setup for start of test.
    procedure test_start is
    begin
        wait until rising_edge(clk_100);
        report "Starting test #" & integer'image(test_index+1);
        test_reset  <= '1';
        test_index  <= test_index + 1;
        test_ref    <= (ERR_COUNT => 1, others => 0);
        wait until rising_edge(clk_100);
        test_reset  <= '0';
    end procedure;

    -- Send an error strobe and increment expected-message counter.
    procedure test_send(idx : integer; incr : boolean := true) is
        variable idx2 : integer := idx;
    begin
        -- If requested, randomize message index.
        if (idx < 0) then
            uniform(seed1, seed2, rand);
            idx2 := integer(floor(rand * real(ERR_COUNT)));
        end if;
        -- If enabled, increment reference counter.
        if (incr) then
            test_ref(idx2) <= test_ref(idx2) + 1;
        end if;
        -- Send the specified pulse.
        wait until rising_edge(clk_100);
        err_strobe(idx2) <= '1';
        wait until rising_edge(clk_100);
        err_strobe(idx2) <= '0';
        wait for 1 us;
    end procedure;

    -- End of test checking, including the "OK" message.
    procedure test_finish is
        variable total : integer := 0;
    begin
        -- Wait long enough for an "OK" message to be sent.
        while (msg_idle < OK_CLOCKS/2) loop
            wait until rising_edge(clk_100);
        end loop;
        for n in 0 to OK_CLOCKS loop
            wait until rising_edge(clk_100);
        end loop;
        -- Check that each counter matches expected value.
        for n in test_ref'reverse_range loop
            total := total + test_ref(n);
            assert (test_ref(n) = msg_count(n))
                report "Receiver mismatch for message #" & integer'image(n)
                    & ": expected " & integer'image(test_ref(n))
                    & " got " & integer'image(msg_count(n))
                severity error;
        end loop;
        assert (msg_total = total)
            report "Total message-count mismatch: expected "
                & integer'image(total) & " got " & integer'image(msg_total)
            severity error;
    end procedure;
begin
    -- Wait for reset.
    wait until reset_p = '0';
    wait for 1 us;

    -- Test #0: Confirm startup message received.
    wait for 200 us;
    assert (msg_total = 1)
        report "Missing startup message." severity error;

    -- Test #1: No errors.
    test_start;
    test_finish;

    -- Test #2-4: Single error.
    test_start;
    test_send(0);
    test_finish;

    test_start;
    test_send(1);
    test_finish;

    test_start;
    test_send(7);
    test_finish;

    -- Test 5: Repeated error (no masking)
    test_start;
    test_send(2);
    test_send(2);
    test_finish;

    -- Test 6: Repeated error (with masking)
    test_start;
    test_send(3);
    test_send(3);
    test_send(3, false);    -- Masked
    test_finish;

    -- Test 7: Queueing of concurrent errors.
    test_start;
    test_send(4);
    test_send(5);
    test_send(6);
    test_finish;

    -- Test 8+: Random test with two errors.
    -- (Note: Never masked, even if the same message is chosen twice.)
    loop
        test_start;
        test_send(-1);  -- Random
        test_send(-1);  -- Random
        test_finish;
    end loop;
end process;

end tb;
