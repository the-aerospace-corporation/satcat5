--------------------------------------------------------------------------
-- Copyright 2019-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for port traffic statistics
--
-- This is a unit test for the traffic statistics block. It generates a
-- stream of random frame traffic, while concurrently requesting a series
-- of statistics reports. (This ensures that such boundaries come before,
-- during, and after traffic frames.) At the end of each trial, there is
-- a brief pause in traffic before comparing the total reported statistics
-- to the known reference values. The unit test runs a series of such
-- trials to evaluate different duration and flow-control conditions.
--
-- The complete test takes about 1.9 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;
use     work.switch_types.all;

entity port_statistics_tb is
    -- Unit testbench top level, no I/O ports
end port_statistics_tb;

architecture tb of port_statistics_tb is

constant COUNT_WIDTH : integer := 24;
subtype counter_t is unsigned(COUNT_WIDTH-1 downto 0);

-- Clock and reset generation.
signal clk_100  : std_logic := '0';
signal reset_p  : std_logic := '1';

-- Tx and Rx data streams.
signal rx_data      : port_rx_m2s := RX_M2S_IDLE;
signal tx_data      : port_tx_s2m := TX_S2M_IDLE;
signal tx_ctrl      : port_tx_m2s := TX_M2S_IDLE;

-- Test and reference counters.
signal uut_rx_byte  : counter_t := (others => '0');
signal uut_rx_frm   : counter_t := (others => '0');
signal uut_tx_byte  : counter_t := (others => '0');
signal uut_tx_frm   : counter_t := (others => '0');
signal tot_rx_byte  : counter_t := (others => '0');
signal tot_rx_frm   : counter_t := (others => '0');
signal tot_tx_byte  : counter_t := (others => '0');
signal tot_tx_frm   : counter_t := (others => '0');
signal ref_rx_byte  : counter_t := (others => '0');
signal ref_tx_byte  : counter_t := (others => '0');
signal uut_status   : std_logic_vector(31 downto 0);
signal ref_status   : port_status_t := (others => '0');

-- Test control.
signal test_index   : integer := 0;
signal test_start   : std_logic := '0';
signal test_running : std_logic := '0';
signal test_frames  : integer := 0;
signal test_rx_rate : real := 0.0;
signal test_tx_rate : real := 0.0;
signal stats_req_t  : std_logic := '0';

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Input stream generation.
p_src : process(clk_100)
    variable seed1  : positive := 1253870;
    variable seed2  : positive := 7861970;
    variable rand   : real := 0.0;

    -- Generate a random status word.
    impure function rand_status return port_status_t is
        variable tmp : port_status_t;
    begin
        for n in tmp'range loop
            uniform(seed1, seed2, rand);
            tmp(n) := bool2bit(rand < 0.5);
        end loop;
        return tmp;
    end function;

    -- Generate frame lengths from 8 - 64 bytes.
    impure function rand_len return integer is
    begin
        uniform(seed1, seed2, rand);
        return 8 + integer(floor(rand * 57.0));
    end function;

    -- Remaining bytes per frame, frames per trial.
    variable tx_brem, tx_frem : integer := 0;
    variable rx_brem, rx_frem : integer := 0;
begin
    if rising_edge(clk_100) then
        -- Randomize status at the start of each test.
        if (test_start = '1') then
            ref_status  <= rand_status;
        end if;

        -- Randomize length at the start of each new frame,
        -- and keep track of the total statistics.
        if (test_start = '1') then
            rx_frem     := test_frames - 1;
            rx_brem     := rand_len;
            ref_rx_byte <= to_unsigned(rx_brem, COUNT_WIDTH);
        elsif (rx_brem = 0 and rx_frem > 0) then
            rx_frem     := rx_frem - 1;
            rx_brem     := rand_len;
            ref_rx_byte <= ref_rx_byte + rx_brem;
        end if;

        if (test_start = '1') then
            tx_frem     := test_frames - 1;
            tx_brem     := rand_len;
            ref_tx_byte <= to_unsigned(tx_brem, COUNT_WIDTH);
        elsif (tx_brem = 0 and tx_frem > 0) then
            tx_frem     := tx_frem - 1;
            tx_brem     := rand_len;
            ref_tx_byte <= ref_tx_byte + tx_brem;
        end if;

        -- Rx stream generation.
        uniform(seed1, seed2, rand);
        if (rx_brem > 0 and rand < test_rx_rate) then
            rx_data.write   <= '1'; -- New data word
            rx_data.last    <= bool2bit(rx_brem = 1);
            rx_brem         := rx_brem - 1;
        else
            rx_data.write   <= '0'; -- No new data
            rx_data.last    <= '0';
        end if;

        -- Tx stream generation.
        uniform(seed1, seed2, rand);
        if (tx_data.valid = '1' and tx_ctrl.ready = '0') then
            null;   -- No change, hold previous value
        elsif (tx_brem > 0 and rand < test_tx_rate) then
            tx_data.valid   <= '1'; -- Generate new data word
            tx_data.last    <= bool2bit(tx_brem = 1);
            tx_brem         := tx_brem - 1;
        else
            tx_data.valid   <= '0'; -- Previous word consumed
            tx_data.last    <= '0';
        end if;

        uniform(seed1, seed2, rand);
        tx_ctrl.ready <= bool2bit(rand < test_tx_rate) or not test_running;

        -- Update the "test_running" flag.
        test_running <= bool2bit(tx_frem > 0 or tx_brem > 0
                              or rx_frem > 0 or rx_brem > 0);
    end if;
end process;

-- Drive remaining port signals.
rx_data.clk     <= clk_100 after 1 ns;
rx_data.data    <= (others => '0');
rx_data.rxerr   <= '0';
rx_data.rate    <= get_rate_word(1000);
rx_data.status  <= ref_status;
rx_data.reset_p <= reset_p;

tx_data.data    <= (others => '0');
tx_ctrl.clk     <= clk_100 after 1 ns;
tx_ctrl.txerr   <= '0';
tx_ctrl.reset_p <= reset_p;

-- Unit under test
uut : entity work.port_statistics
    generic map(
    COUNT_WIDTH => COUNT_WIDTH)
    port map(
    stats_req_t => stats_req_t,
    rcvd_bytes  => uut_rx_byte,
    rcvd_frames => uut_rx_frm,
    sent_bytes  => uut_tx_byte,
    sent_frames => uut_tx_frm,
    status_clk  => clk_100,
    status_word => uut_status,
    err_port    => PORT_ERROR_NONE, -- Not tested
    rx_data     => rx_data,
    tx_data     => tx_data,
    tx_ctrl     => tx_ctrl);

-- Running sum over each trial.
p_sum : process(clk_100)
    variable stats_req_d : std_logic := '0';
begin
    if rising_edge(clk_100) then
        if (test_start = '1') then
            -- Reset at start of test.
            tot_rx_byte  <= (others => '0');
            tot_rx_frm   <= (others => '0');
            tot_tx_byte  <= (others => '0');
            tot_tx_frm   <= (others => '0');
        elsif (stats_req_t /= stats_req_d) then
            -- Start/end of interval. Increment total by the previously
            -- latched results, before the outputs refresh.
            tot_rx_byte  <= tot_rx_byte + uut_rx_byte;
            tot_rx_frm   <= tot_rx_frm  + uut_rx_frm;
            tot_tx_byte  <= tot_tx_byte + uut_tx_byte;
            tot_tx_frm   <= tot_tx_frm  + uut_tx_frm;
        end if;
        stats_req_d := stats_req_t;
    end if;
end process;

-- Overall test control
p_test : process
    function u2str(x : unsigned) return string is
    begin
        return integer'image(to_integer(x));
    end function;

    procedure run_trial(ri,ro:real; nfrm:integer) is
    begin
        -- Set test conditions.
        report "Starting test #" & integer'image(test_index + 1);
        test_index   <= test_index + 1;
        test_frames  <= nfrm;
        test_rx_rate <= ri;
        test_tx_rate <= ro;

        -- Send the "start" strobe to begin data streaming.
        wait until rising_edge(clk_100);
        test_start <= '1';
        wait until rising_edge(clk_100);
        test_start <= '0';

        -- Toggle the "request" line every microsecond, until the
        -- randomizer source finishes the requested frame count.
        wait for 1 us;
        while (test_running = '1') loop
            stats_req_t <= not stats_req_t;
            wait for 1 us;
        end loop;

        -- Flush the pipeline with at least two more "request" toggles.
        for n in 1 to 2 loop
            stats_req_t <= not stats_req_t;
            wait for 1 us;
        end loop;

        -- Confirm total outputs match expectations.
        assert (tot_rx_byte = ref_rx_byte)
            report "Rx byte mismatch: got " & u2str(tot_rx_byte)
                & ", expected " & u2str(ref_rx_byte) severity error;
        assert (tot_tx_byte = ref_tx_byte)
            report "Tx byte mismatch: got " & u2str(tot_tx_byte)
                & ", expected " & u2str(ref_tx_byte) severity error;
        assert (tot_rx_frm = test_frames)
            report "Rx frame mismatch: got " & u2str(tot_rx_frm)
                & ", expected " & integer'image(test_frames) severity error;
        assert (tot_tx_frm = test_frames)
            report "Tx frame mismatch: got " & u2str(tot_tx_frm)
                & ", expected " & integer'image(test_frames) severity error;
        assert (uut_status(31 downto 16) = i2s(1000, 16))
            report "Status-rate mismatch." severity error;
        assert (uut_status(7 downto 0) = ref_status)
            report "Status-word mismatch." severity error;
    end procedure;
begin
    -- Wait for reset.
    wait until (reset_p = '0');
    wait for 1 us;

    -- Each trial has different length and flow-control conditions:
    run_trial(0.1, 0.9, 100);
    run_trial(0.3, 0.7, 100);
    run_trial(0.5, 0.5, 100);
    run_trial(0.7, 0.3, 100);
    run_trial(0.9, 0.1, 100);
    run_trial(1.0, 1.0, 1000);

    report "All tests completed!";
    wait;
end process;

end tb;
