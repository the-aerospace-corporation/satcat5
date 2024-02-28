--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the fixed-integer-ratio resampling block
--
-- This testbench cperates the "io_resample_fixed" block with several
-- different configurations. It provides an oversampled input signal
-- at a known phase-offset, then confirms that the unit under test
-- locks to the correct offset and adjusts timestamps accordingly.
--
-- The test completes in less than 1 msec.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.ptp_types.all;
use     work.router_sim_tools.all;

entity io_resample_fixed_helper is
    generic (
    IO_WIDTH    : positive;     -- Tx/Rx width (internal)
    OVERSAMPLE  : positive;     -- Oversampling ratio
    MSB_FIRST   : boolean);     -- Serial I/O order
    port (
    test_done   : out std_logic);
end io_resample_fixed_helper;

architecture tb of io_resample_fixed_helper is

subtype wide_t is std_logic_vector(IO_WIDTH*OVERSAMPLE-1 downto 0);
subtype word_t is std_logic_vector(IO_WIDTH-1 downto 0);

-- System clock and reset.
signal clk100       : std_logic := '1';

-- Unit under test.
signal tx_in_data   : word_t := (others => '0');
signal tx_out_data  : wide_t;
signal tx_out_ref   : wide_t := (others => '0');
signal rx_in_data   : wide_t := (others => '0');
signal rx_in_time   : tstamp_t := (others => '0');
signal rx_out_data  : word_t;
signal rx_out_ref   : word_t := (others => '0');
signal rx_out_time  : tstamp_t;
signal rx_out_tref  : tstamp_t := (others => '0');
signal rx_out_lock  : std_logic;

-- High-level test control.
signal test_check   : std_logic := '0';
signal test_enable  : std_logic := '0';
signal test_ontime  : integer range 0 to OVERSAMPLE-1 := 0;

begin

-- Clock generation.
clk100 <= not clk100 after 5 ns;

-- Generate input and reference streams.
p_input : process(clk100)
    -- Generate all data LSB-first, then flip as needed.
    function set_order(x: std_logic_vector) return std_logic_vector is
    begin
        if MSB_FIRST then return flip_vector(x);
                     else return x; end if;
    end function;

    constant TPAR : tstamp_t := get_tstamp_incr(100_000_000);
    constant TBIT : tstamp_t := tstamp_div(TPAR, IO_WIDTH * OVERSAMPLE);
    variable prev_bit : std_logic := '0';
    variable tmp_word : word_t := (others => '0');
    variable tmp_wide : wide_t := (others => '0');
begin
    if rising_edge(clk100) then
        -- Randomize the transmit data.
        if (test_enable = '1') then
            tmp_word := rand_vec(IO_WIDTH);
            for n in tmp_wide'range loop
                tmp_wide(n) := tmp_word(n / OVERSAMPLE);
            end loop;
            tx_in_data <= set_order(tmp_word);
            tx_out_ref <= set_order(tmp_wide);
        else
            tx_in_data <= (others => '0');
            tx_out_ref <= (others => '0');
        end if;

        -- Randomize the received data and apply phase offset.
        -- Note: Store last bit from previous word for carryover.
        if (test_enable = '1') then
            tmp_word := rand_vec(IO_WIDTH);
            for n in tmp_wide'range loop
                if (n < test_ontime) then
                    tmp_wide(n) := prev_bit;
                else
                    tmp_wide(n) := tmp_word((n - test_ontime) / OVERSAMPLE);
                end if;
            end loop;
            prev_bit   := tmp_word(IO_WIDTH-1);
            rx_in_data <= set_order(tmp_wide);
            rx_out_ref <= set_order(tmp_word);
        else
            rx_in_data <= (others => '0');
            rx_out_ref <= (others => '0');
        end if;

        -- Input timestamp simply increments on each clock cycle.
        rx_in_time <= rx_in_time + TPAR;

        -- Calculate the expected output timestamp.
        rx_out_tref <= rx_in_time + TPAR + tstamp_mult(TBIT, test_ontime);
    end if;
end process;

-- Unit under test.
uut : entity work.io_resample_fixed
    generic map(
    IO_CLK_HZ   => 100_000_000,
    IO_WIDTH    => IO_WIDTH,
    OVERSAMPLE  => OVERSAMPLE,
    MSB_FIRST   => MSB_FIRST)
    port map(
    tx_in_data  => tx_in_data,
    tx_out_data => tx_out_data,
    rx_clk      => clk100,
    rx_in_data  => rx_in_data,
    rx_in_time  => rx_in_time,
    rx_out_data => rx_out_data,
    rx_out_time => rx_out_time,
    rx_out_lock => rx_out_lock);

-- Check the outputs.
p_check : process(clk100)
    variable rx_lock_dly : std_logic := '0';
begin
    if rising_edge(clk100) then
        if (test_check = '1' and rx_out_lock = '1') then
            assert (tx_out_data = tx_out_ref)
                report "Tx data mismatch." severity error;
            assert (rx_out_data = rx_out_ref)
                report "Rx data mismatch." severity error;
            assert (tstamp_diff(rx_out_time, rx_out_tref) <= 2)
                report "Rx time mismatch." severity error;
        end if;

        if (test_check = '1') then
            assert (rx_out_lock = rx_lock_dly)
                report "Unexpected lock change." severity error;
        end if;
        rx_lock_dly := rx_out_lock;
    end if;
end process;

-- High-level test control.
p_test : process
    procedure test_random_alignment is
    begin
        test_check  <= '0';
        test_enable <= '1';
        test_ontime <= rand_int(OVERSAMPLE);
        wait for 10 us;
        test_check  <= '1';
        assert (rx_out_lock = '1')
            report "Signal acquisition failed." severity error;
        wait for 10 us;
    end procedure;

    procedure test_signal_shutdown is
    begin
        test_check  <= '0';
        test_enable <= '0';
        wait for 5 us;
        test_check  <= '1';
        assert (rx_out_lock = '0')
            report "Locked after signal shutdown." severity error;
        assert (rx_out_time = TSTAMP_DISABLED)
            report "Bad time after signal shutdown." severity error;
        wait for 5 us;
    end procedure;
begin
    -- Initial setup.
    test_check  <= '0';
    test_done   <= '0';
    test_enable <= '0';
    test_ontime <= 0;

    -- Test we can acquire lock in any alignment.
    for n in 1 to 10 loop
        test_random_alignment;
        test_signal_shutdown;
    end loop;

    -- Confirm we can re-acquire without a shutdown.
    for n in 1 to 20 loop
        test_random_alignment;
    end loop;

    -- All tests completed.
    test_done <= '1';

    -- Keep running indefinitely.
    loop
        test_random_alignment;
    end loop;
end process;

end tb;


---------------------------------------------------------------------


library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity io_resample_fixed_tb is
    -- Unit testbench, no I/O ports.
end io_resample_fixed_tb;

architecture tb of io_resample_fixed_tb is

component io_resample_fixed_helper is
    generic (
    IO_WIDTH    : positive;     -- Tx/Rx width (internal)
    OVERSAMPLE  : positive;     -- Oversampling ratio
    MSB_FIRST   : boolean);     -- Serial I/O order
    port (
    test_done   : out std_logic);
end component;

signal test_done : std_logic_vector(0 to 3);

begin

-- Instantiate each test configuration.
uut0 : io_resample_fixed_helper
    generic map(
    IO_WIDTH    => 4,
    OVERSAMPLE  => 3,
    MSB_FIRST   => true)
    port map(
    test_done   => test_done(0));

uut1 : io_resample_fixed_helper
    generic map(
    IO_WIDTH    => 5,
    OVERSAMPLE  => 4,
    MSB_FIRST   => true)
    port map(
    test_done   => test_done(1));

uut2 : io_resample_fixed_helper
    generic map(
    IO_WIDTH    => 6,
    OVERSAMPLE  => 5,
    MSB_FIRST   => false)
    port map(
    test_done   => test_done(2));

uut3 : io_resample_fixed_helper
    generic map(
    IO_WIDTH    => 7,
    OVERSAMPLE  => 6,
    MSB_FIRST   => false)
    port map(
    test_done   => test_done(3));

-- Print a log message once all "done" flags are raised.
p_test : process
begin
    wait until and_reduce(test_done) = '1';
    report "All tests completed!";
    wait;
end process;

end tb;
