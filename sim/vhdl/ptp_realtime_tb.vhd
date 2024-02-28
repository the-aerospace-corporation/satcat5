--------------------------------------------------------------------------
-- Copyright 2022-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for real-time PTP timestamps (ptp_realsof, ptp_realtime)
--
-- This is a unit test for various ConfigBus-controlled blocks for working
-- with realtime PTP timestamps.  It confirms that the RTC responds correctly
-- to all supported ConfigBus commands.
--
-- The complete test takes 0.6 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;
use     work.cfgbus_sim_tools.all;
use     work.ptp_types.all;

entity ptp_realtime_tb is
    -- Unit testbench top level, no I/O ports
end ptp_realtime_tb;

architecture tb of ptp_realtime_tb is

-- Define all relevant ConfigBus constants.
constant DEV_ADDR       : integer := 12;
constant REG_TIME_BASE  : integer := 34;
constant REG_SOF_BASE   : integer := 56;

constant REG_TIME_SECH  : integer := REG_TIME_BASE + 0;
constant REG_TIME_SECL  : integer := REG_TIME_BASE + 1;
constant REG_TIME_NSEC  : integer := REG_TIME_BASE + 2;
constant REG_TIME_CMD   : integer := REG_TIME_BASE + 4;
constant REG_TIME_RATE  : integer := REG_TIME_BASE + 5;

constant REG_SOF_SECH   : integer := REG_SOF_BASE + 0;
constant REG_SOF_SECL   : integer := REG_SOF_BASE + 1;
constant REG_SOF_NSEC   : integer := REG_SOF_BASE + 2;
constant REG_SOF_SUBNS  : integer := REG_SOF_BASE + 3;

constant OPCODE_NOOP    : cfgbus_word := x"00000000";
constant OPCODE_READ    : cfgbus_word := x"01000000";
constant OPCODE_WRITE   : cfgbus_word := x"02000000";
constant OPCODE_WPULSE  : cfgbus_word := x"03000000";
constant OPCODE_INCR    : cfgbus_word := x"04000000";

-- Packet stream for timestamp tests.
signal in_last      : std_logic := '0';
signal in_write     : std_logic := '0';

-- Current system time.
signal time_now     : ptp_time_t := PTP_TIME_ZERO;
signal time_rdref   : ptp_time_t := PTP_TIME_ZERO;
signal time_rdval   : ptp_time_t := PTP_TIME_ZERO;
signal time_sof     : ptp_time_t := PTP_TIME_ZERO;
signal time_read    : std_logic := '0';
signal time_write   : std_logic := '0';

-- ConfigBus interface.
signal cfg_opcode   : cfgbus_word := OPCODE_NOOP;
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;
signal cfg_acks     : cfgbus_ack_array(0 to 1);
signal cfg_rdval    : cfgbus_word;
signal test_index   : natural := 0;
signal pkt_start    : std_logic := '0';

begin

-- Clock and reset generation.
u_clk : cfgbus_clock_source
    port map(clk_out => cfg_cmd.clk);

-- Stream generation + latch start-of-frame timestamp.
p_stream : process(cfg_cmd.clk)
    constant PKT_LEN    : integer := 10;
    variable start_d    : std_logic := '0';
    variable word_ctr   : integer := PKT_LEN+1;
begin
    if rising_edge(cfg_cmd.clk) then
        -- Latch timestamp for various events.
        if (cfg_opcode = OPCODE_READ) then
            time_rdref <= time_now;     -- RTC read
        end if;
        if (in_write = '1' and word_ctr = 0) then
            time_sof <= time_now;       -- Start of frame
        end if;

        -- Count words in each "packet".
        if (pkt_start = '1' and start_d = '0') then
            word_ctr := 0;  -- Start new frame
        elsif (in_write = '1') then
            word_ctr := word_ctr + 1;
        end if;
        start_d := pkt_start;

        -- Generate WRITE and LAST strobes.
        in_write    <= bool2bit(word_ctr <= PKT_LEN);
        in_last     <= bool2bit(word_ctr  = PKT_LEN);

        -- Decode RTC commands; one-cycle delay is intentional.
        if (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, REG_TIME_CMD)) then
            cfg_opcode <= cfg_cmd.wdata and x"FF000000";
        else
            cfg_opcode <= OPCODE_NOOP;
        end if;
    end if;
end process;

-- Unit under test: Real-time clock.
uut_time : entity work.ptp_realtime
    generic map(
    CFG_CLK_HZ  => 100_000_000,
    DEV_ADDR    => DEV_ADDR,
    REG_BASE    => REG_TIME_BASE)
    port map(
    time_now    => time_now,
    time_read   => time_read,
    time_write  => time_write,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(0));

-- Unit under test: Timestamp generation.
uut_sof : entity work.ptp_realsof
    generic map(
    DEV_ADDR    => DEV_ADDR,
    REG_BASE    => REG_SOF_BASE)
    port map(
    in_tnow     => time_now,
    in_last     => in_last,
    in_write    => in_write,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(1));

-- Helper object for ConfigBus reads
cfg_ack <= cfgbus_merge(cfg_acks);

u_read_latch : cfgbus_read_latch
    port map(
    cfg_cmd => cfg_cmd,
    cfg_ack => cfg_ack,
    readval => cfg_rdval);

-- Command interface.
p_test : process
    -- Start-of-test setup.
    procedure test_start(lbl: string) is
    begin
        wait for 1 us;
        test_index <= test_index + 1;
        report "Starting test #" & integer'image(test_index+1) & ": " & lbl;
    end procedure;

    -- Helper function for reading RTC or SOF time into "time_rdval".
    procedure shared_read(reg_base: integer) is
    begin
        cfgbus_readwait(cfg_cmd, cfg_ack, DEV_ADDR, reg_base + 0);
        time_rdval.sec(47 downto 32) <= signed(cfg_rdval(15 downto 0));
        cfgbus_readwait(cfg_cmd, cfg_ack, DEV_ADDR, reg_base + 1);
        time_rdval.sec(31 downto  0) <= signed(cfg_rdval);
        cfgbus_readwait(cfg_cmd, cfg_ack, DEV_ADDR, reg_base + 2);
        time_rdval.nsec <= unsigned(cfg_rdval);
        cfgbus_readwait(cfg_cmd, cfg_ack, DEV_ADDR, reg_base + 3);
        time_rdval.subns <= unsigned(cfg_rdval(15 downto 0));
        wait until rising_edge(cfg_cmd.clk);
    end procedure;

    -- Send a packet and read SOF time, storing result in "time_rdval".
    procedure sof_refresh is
    begin
        pkt_start <= '1'; wait for 100 ns;
        pkt_start <= '0'; wait for 100 ns;
        shared_read(REG_SOF_BASE);
    end procedure;

    -- Read RTC time, storing result in "time_rdval".
    procedure rtc_read is
    begin
        cfgbus_write(cfg_cmd, DEV_ADDR, REG_TIME_CMD, OPCODE_READ);
        shared_read(REG_TIME_BASE);
    end procedure;

    -- Write RTC time.
    procedure rtc_write(sec, nsec: integer) is
    begin
        cfgbus_write(cfg_cmd, DEV_ADDR, REG_TIME_SECH, x"00000000");
        cfgbus_write(cfg_cmd, DEV_ADDR, REG_TIME_SECL, i2s(sec, 32));
        cfgbus_write(cfg_cmd, DEV_ADDR, REG_TIME_NSEC, i2s(nsec, 32));
        cfgbus_write(cfg_cmd, DEV_ADDR, REG_TIME_CMD,  OPCODE_WRITE);
    end procedure;

    -- Write RTC time at next pulse
    procedure rtc_write_pulse(sec, nsec: integer) is
    begin
        cfgbus_write(cfg_cmd, DEV_ADDR, REG_TIME_SECH, x"00000000");
        cfgbus_write(cfg_cmd, DEV_ADDR, REG_TIME_SECL, i2s(sec, 32));
        cfgbus_write(cfg_cmd, DEV_ADDR, REG_TIME_NSEC, i2s(nsec, 32));
        cfgbus_write(cfg_cmd, DEV_ADDR, REG_TIME_CMD,  OPCODE_WPULSE);
    end procedure;

    -- Increment RTC time.
    procedure rtc_incr(sec, nsec: integer) is
    begin
        cfgbus_write(cfg_cmd, DEV_ADDR, REG_TIME_SECH, x"00000000");
        cfgbus_write(cfg_cmd, DEV_ADDR, REG_TIME_SECL, i2s(sec, 32));
        cfgbus_write(cfg_cmd, DEV_ADDR, REG_TIME_NSEC, i2s(nsec, 32));
        cfgbus_write(cfg_cmd, DEV_ADDR, REG_TIME_CMD,  OPCODE_INCR);
    end procedure;

    -- Adjust RTC frequency offset.
    procedure rtc_adjust(offset: integer) is
        variable tmp : std_logic_vector(63 downto 0)
            := std_logic_vector(shift_left(to_signed(offset, 64), 8));
    begin
        cfgbus_write(cfg_cmd, DEV_ADDR, REG_TIME_RATE, tmp(63 downto 32));
        cfgbus_write(cfg_cmd, DEV_ADDR, REG_TIME_RATE, tmp(31 downto 0));
        cfgbus_readwait(cfg_cmd, cfg_ack, DEV_ADDR, REG_TIME_RATE);
    end procedure;
begin
    -- Initial setup.
    cfgbus_reset(cfg_cmd);
    wait for 1 us;

    -- Set RTC and wait for rollover.
    test_start("Rollover-wait");
    rtc_write(1, 999_998_000);
    rtc_read;   -- Read before rollover
    assert (time_rdval = time_rdref) report "Read mismatch.";
    assert (time_rdval.sec = 1) report "Write failed.";
    wait for 4 us;
    rtc_read;   -- Read after rollover
    assert (time_rdval = time_rdref) report "Read mismatch.";
    assert (time_rdval.sec = 2) report "Bad rollover (sec).";
    assert (time_rdval.nsec > 2_000) report "Bad rollover (nsec).";

    -- Increment through a rollover.
    test_start("Rollover-incr");
    rtc_write(3, 750_000_000);
    rtc_read;   -- Read before rollover
    assert (time_rdval = time_rdref) report "Read mismatch";
    assert (time_rdval.sec = 3) report "Write failed.";
    rtc_incr(0, 500_000_000);
    rtc_read;   -- Read after rollover
    assert (time_rdval = time_rdref) report "Read mismatch";
    assert (time_rdval.sec = 4) report "Bad rollover (sec).";
    assert (time_rdval.nsec > 250_000_000) report "Bad rollover (nsec).";

    -- Test that time is latched in correctly on a time_read pulse.
    test_start("Read-pulse");
    rtc_write(0, 0);                -- Start stopwatch
    wait for 10 us;
    time_read <= '1';               -- Latch time after 10us
    wait until rising_edge(cfg_cmd.clk);
    time_read <= '0';
    wait for 10 us;
    shared_read(REG_TIME_BASE);     -- Reads cfgbus time regs
    assert (9_500 < time_rdval.nsec and time_rdval.nsec < 10_500)
        report "Bad read at pulse: " & integer'image(to_integer(time_rdval.nsec));

    -- Test that time is latched in correctly on a time_write pulse.
    test_start("Write-pulse");
    rtc_write(0, 0);                -- Start stopwatch
    rtc_write_pulse(100, 0);        -- Queue 100s, 0ns at next pulse
    wait for 20 us;
    time_write <= '1';              -- Trigger 10us long pulse
    wait for 10 us;
    time_write <= '0';
    wait for 90 us;
    rtc_read;                       -- End stopwatch, expect 100us
    assert (time_rdval = time_rdref) report "Read mismatch";
    assert (99_500 < time_rdval.nsec and time_rdval.nsec < 100_500)
        report "Bad write at pulse: " & integer'image(to_integer(time_rdval.nsec));
    wait for 10 us;                 -- Settle, confirm write pulse resets OK
    rtc_write_pulse(102, 500_000_000); -- Queue 102.5s at next pulse
    wait for 50 us;
    time_write <= '1';              -- Trigger 10us long pulse
    wait for 10 us;
    time_write <= '0';
    wait for 90 us;
    rtc_read;                       -- End stopwatch, expect 102.5001s
    assert (time_rdval = time_rdref) report "Read mismatch";
    assert (500_099_500 < time_rdval.nsec and time_rdval.nsec < 500_100_500)
        report "Bad write pulse reset: " & integer'image(to_integer(time_rdval.nsec));

    -- Rate-adjustment test.
    test_start("Rate-adjust-dn");
    rtc_adjust(-1_000_000_000);     -- 2.3% slowdown
    rtc_write(0, 0);                -- Start stopwatch
    wait for 100 us;
    rtc_read;                       -- End stopwatch
    assert (time_rdval = time_rdref) report "Read mismatch";
    assert (97_500 < time_rdval.nsec and time_rdval.nsec < 98_000)
        report "Rate mismatch: " & integer'image(to_integer(time_rdval.nsec));

    test_start("Rate-adjust-up");
    rtc_adjust(1_000_000_000);      -- 2.3% speedup
    rtc_write(0, 0);                -- Start stopwatch
    wait for 100 us;
    rtc_read;                       -- End stopwatch
    assert (time_rdval = time_rdref) report "Read mismatch";
    assert (102_000 < time_rdval.nsec and time_rdval.nsec < 102_500)
        report "Rate mismatch: " & integer'image(to_integer(time_rdval.nsec));

    -- Check start-of-frame timestamps.
    test_start("Start-of-frame");
    for n in 1 to 10 loop
        sof_refresh;
        assert (time_rdval = time_sof) report "SOF mismatch.";
    end loop;

    report "All tests completed!";
    wait;
end process;

end tb;
