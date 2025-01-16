--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the PPS input and output blocks
--
-- This unit test configures the PPS output block with a series of
-- CPU-configured phase offsets, inspecting the output to confirm
-- the correct alignment.  Then, it confirms the PPS input block
-- reports edge transitions with the expected phase offset.
--
-- The complete test takes 0.9 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.ptp_types.all;

entity ptp_pps_tb_helper is
    generic (
    PAR_COUNT   : positive;     -- Number of samples per clock
    DITHER_EN   : boolean;      -- Enable dither on output?
    MSB_FIRST   : boolean);     -- Parallel bit order
end ptp_pps_tb_helper;

architecture ptp_pps_tb_helper of ptp_pps_tb_helper is

-- To keep simulation time low, run at ~100,000 speedup factor.
-- (i.e., Simulation clock is 100 MHz, but we pretend it's 999 Hz.)
constant PAR_CLK_HZ : positive := 999;

-- Set maximum allowed error based on the serial sample time.
constant TSAMP_SEC  : real := 1.0 / real(PAR_CLK_HZ * PAR_COUNT);
constant MAX_ERROR  : real := 1.5 * TSAMP_SEC;

-- ConfigBus register addresses:
constant DEV_ADDR   : integer := 42;
constant REG_PPSI   : integer := 43;
constant REG_PPSO   : integer := 44;

-- Test sgnals
signal clk_100      : std_logic := '1';
signal ref_rtc      : ptp_time_t := PTP_TIME_ZERO;
signal ref_pps      : std_logic_vector(PAR_COUNT-1 downto 0) := (others => '0');
signal uut_pps      : std_logic_vector(PAR_COUNT-1 downto 0);

-- High-level test control
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;
signal test_phase   : tstamp_t := (others => '0');
signal test_rising  : std_logic := '0';
signal test_check   : std_logic := '0';

begin

-- Clock generation.
clk_100 <= not clk_100 after 5.0 ns;    -- 1 / (2*5 ns) = 100 MHz
cfg_cmd.clk <= clk_100;

-- Generate the reference signals.
p_rtc : process(clk_100)
    constant INCR   : tstamp_t := get_tstamp_incr(PAR_CLK_HZ);
    constant TSAMP  : real := 1.0 / real(PAR_CLK_HZ * PAR_COUNT);
    variable phase  : real := 0.0;
    variable subns  : tstamp_t := (others => '0');
    variable pval, wrap : std_logic := '0';
begin
    if rising_edge(clk_100) then
        -- Free-running reference counter.
        if (subns + INCR >= TSTAMP_ONE_SEC) then
            subns := subns + INCR - TSTAMP_ONE_SEC;
            wrap  := '1';
        else
            subns := subns + INCR;
            wrap  := '0';
        end if;

        -- Convert counter to seconds/nanoseconds/subnanoto RTC format.
        ref_rtc.sec     <= ref_rtc.sec + u2i(wrap);
        ref_rtc.nsec    <= subns(47 downto 16);
        ref_rtc.subns   <= subns(15 downto 0);

        -- Generate the reference PPS, allowing some uncertainty for dither.
        for n in ref_pps'range loop
            phase := real(n) * TSAMP + get_time_sec(subns - test_phase);
            phase := phase mod 1.0;
            if (TSAMP <= phase and phase <= 0.5 - TSAMP) then
                pval := test_rising;        -- First half of cycle
            elsif (0.5 + TSAMP <= phase and phase <= 1.0 - TSAMP) then
                pval := not test_rising;    -- Second half of cycle
            else
                pval := 'Z';                -- Margin for rounding error
            end if;
            if (MSB_FIRST) then
                ref_pps(PAR_COUNT-n-1) <= pval;
            else
                ref_pps(n) <= pval;
            end if;
        end loop;
    end if;
end process;

-- UUT: PPS output
uut_out : entity work.ptp_pps_out
    generic map(
    PAR_CLK_HZ  => PAR_CLK_HZ,
    PAR_COUNT   => PAR_COUNT,
    DEV_ADDR    => DEV_ADDR,
    REG_ADDR    => REG_PPSO,
    DITHER_EN   => DITHER_EN,
    MSB_FIRST   => MSB_FIRST)
    port map(
    par_clk     => clk_100,
    par_rtc     => ref_rtc,
    par_pps_out => uut_pps,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => open);

-- UUT: PPS input
uut_in : entity work.ptp_pps_in
    generic map(
    DEV_ADDR    => DEV_ADDR,
    REG_ADDR    => REG_PPSI,
    PAR_CLK_HZ  => PAR_CLK_HZ,
    PAR_COUNT   => PAR_COUNT,
    MSB_FIRST   => MSB_FIRST)
    port map(
    par_clk     => clk_100,
    par_rtc     => ref_rtc,
    par_pps_in  => uut_pps,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack);

-- Check PPS signal against the reference.
p_check : process(clk_100)
    variable ok : boolean;
begin
    if rising_edge(clk_100) then
        if (test_check = '1') then
            ok := true;
            for n in ref_pps'range loop
                ok := ok and (ref_pps(n) = 'Z' or ref_pps(n) = uut_pps(n));
            end loop;
            assert (ok) report "PPS mismatch" severity error;
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    procedure wait_fifo_read(idx: natural) is
    begin
        wait until rising_edge(cfg_cmd.clk) and (cfg_ack.rdata(30) = '1');
        assert (cfg_ack.rdata(31) = bool2bit(idx = 3))
            report "LAST mismatch at index " & integer'image(idx) severity error;
    end procedure;

    procedure run_one(phase : real; edge: std_logic) is
        -- Workaround: HALF_SEC should be a constant, but ISIM initializes it to "UUU..."
        variable HALF_SEC : tstamp_t := shift_right(TSTAMP_ONE_SEC, 1);
        variable tsec, tsub, tdiff : tstamp_t := (others => '0');
    begin
        -- Set the new test conditions.
        test_phase  <= get_tstamp_sec(phase);
        test_rising <= edge;
        test_check  <= '0';
        -- Configure the PPS output. (Write 2x then read.)
        wait until rising_edge(cfg_cmd.clk);
        cfg_cmd.regaddr <= REG_PPSO;
        cfg_cmd.wrcmd   <= '1';
        cfg_cmd.wdata   <= edge & i2s(0, 15) & std_logic_vector(test_phase(47 downto 32));
        wait until rising_edge(cfg_cmd.clk);
        cfg_cmd.wdata   <= std_logic_vector(test_phase(31 downto 0));
        wait until rising_edge(cfg_cmd.clk);
        cfg_cmd.wrcmd   <= '0';
        cfg_cmd.rdcmd   <= '1';
        wait until rising_edge(cfg_cmd.clk);
        cfg_cmd.rdcmd   <= '0';
        -- Clear and configure input FIFO. (Write once.)
        wait until rising_edge(cfg_cmd.clk);
        cfg_cmd.regaddr <= REG_PPSI;
        cfg_cmd.wrcmd   <= '1';
        cfg_cmd.wdata   <= i2s(0, 31) & edge;
        wait until rising_edge(cfg_cmd.clk);
        cfg_cmd.wrcmd   <= '0';
        -- Wait for dust to settle, then clear FIFO again.
        wait for 1 us;
        wait until rising_edge(cfg_cmd.clk);
        cfg_cmd.wrcmd   <= '1';
        wait until rising_edge(cfg_cmd.clk);
        cfg_cmd.wrcmd   <= '0';
        wait for 1 us;
        -- Ready to start checking outputs and polling FIFO.
        test_check      <= '1';
        cfg_cmd.rdcmd   <= '1';
        for n in 1 to 10 loop
            -- Each pulse timestamp has four consecutive sub-words.
            -- (REG_PPSI uses bit 30 as the "data valid" flag.)
            wait_fifo_read(0);
            tsec(47 downto 24) := unsigned(cfg_ack.rdata(23 downto 0));
            wait_fifo_read(1);
            tsec(23 downto  0) := unsigned(cfg_ack.rdata(23 downto 0));
            wait_fifo_read(2);
            tsub(47 downto 24) := unsigned(cfg_ack.rdata(23 downto 0));
            wait_fifo_read(3);
            tsub(23 downto  0) := unsigned(cfg_ack.rdata(23 downto 0));
            -- Calculate the difference from the expected timestamp.
            tdiff := tsub - test_phase;
            while (signed(tdiff) < signed(not HALF_SEC)) loop
                tdiff := tdiff + TSTAMP_ONE_SEC;
            end loop;
            while (tdiff >= HALF_SEC) loop
                tdiff := tdiff - TSTAMP_ONE_SEC;
            end loop;
            -- Report the raw measurement:
            report "Pulse detected: " & integer'image(to_integer(tsec))
                & " at delta = " & real'image(get_time_sec(tdiff));
            assert (abs(get_time_sec(tdiff)) < MAX_ERROR)
                report "Offset mismatch." severity error;
        end loop;
        test_check      <= '0';
        cfg_cmd.rdcmd   <= '0';
    end procedure;
begin
    -- Reset the ConfigBus interface.
    test_phase      <= (others => '0');
    test_rising     <= '0';
    test_check      <= '0';
    cfg_cmd.devaddr <= DEV_ADDR;
    cfg_cmd.regaddr <= 0;
    cfg_cmd.wdata   <= (others => '0');
    cfg_cmd.wstrb   <= (others => '1');
    cfg_cmd.wrcmd   <= '0';
    cfg_cmd.rdcmd   <= '0';
    cfg_cmd.reset_p <= '1';
    wait for 1 us;
    cfg_cmd.reset_p <= '0';
    wait for 1 us;
    -- Run a test at various offsets.
    run_one(-0.4000, '0');
    run_one(-0.3214, '1');
    run_one(-0.2098, '0');
    run_one(-0.1185, '1');
    run_one( 0.0003, '0');
    run_one( 0.1577, '1');
    run_one( 0.2222, '0');
    run_one( 0.3681, '1');
    run_one( 0.4321, '0');
    report "All tests completed!";
    wait;
end process;

end ptp_pps_tb_helper;

--------------------------------------------------------------------------

entity ptp_pps_tb is
    -- Testbench --> No I/O ports
end ptp_pps_tb;

architecture tb of ptp_pps_tb is

begin

-- Instantiate each test configuration:
uut0 : entity work.ptp_pps_tb_helper
    generic map(
    PAR_COUNT   => 6,
    DITHER_EN   => false,
    MSB_FIRST   => true);

uut1 : entity work.ptp_pps_tb_helper
    generic map(
    PAR_COUNT   => 8,
    DITHER_EN   => true,
    MSB_FIRST   => false);

end tb;
